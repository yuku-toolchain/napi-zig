import {
  existsSync,
  readdirSync,
  statSync,
  mkdirSync,
  copyFileSync,
  writeFileSync,
  readFileSync,
  rmSync,
} from "node:fs";
import { join, relative } from "node:path";
import { arch, platform } from "node:os";
import {
  Spinner,
  TaskList,
  banner,
  blank,
  bullet,
  c,
  done,
  fail as uiFail,
  formatSize,
  note as uiNote,
  plain,
  warn as uiWarn,
} from "./ui";
import { CLI_VERSION, run } from "./utils";

export interface BuildDevOptions {
  // Suppress the per-file `info` lines about created/copied loader and .d.ts
  // files. Used by `napi new` for a quiet scaffold flow.
  quiet?: boolean;
}

const HOST_TARGET = `${normalizePlatform(platform())}-${normalizeArch(arch())}`;

function normalizePlatform(p: string): string {
  if (p === "darwin") return "darwin";
  if (p === "linux") return "linux";
  if (p === "win32") return "win32";
  return p;
}

function normalizeArch(a: string): string {
  if (a === "arm64") return "arm64";
  if (a === "x64") return "x64";
  return a;
}

function formatOptimize(opt: string | undefined): string {
  if (!opt) return "Debug";
  switch (opt) {
    case "fast":
      return "ReleaseFast";
    case "safe":
      return "ReleaseSafe";
    case "small":
      return "ReleaseSmall";
    default:
      return opt;
  }
}

export async function buildDev(
  optimize: string | undefined,
  options?: BuildDevOptions,
): Promise<void> {
  const optFlag = optimize ? ` --release=${optimize}` : "";
  const quiet = options?.quiet ?? false;

  if (!quiet) {
    banner("napi-zig", `${CLI_VERSION}  ·  build  ·  ${formatOptimize(optimize)}`);
    bullet(`Target  ${c.bold(HOST_TARGET)}`);
    bullet(`Mode    ${c.bold(formatOptimize(optimize))}`);
    blank();
  }

  const sp = new Spinner(`Compiling for ${c.bold(HOST_TARGET)}`).start();
  try {
    await run(`zig build${optFlag}`);
  } catch (e) {
    sp.fail(`Build failed`);
    const stderr = String((e as { stderr?: string }).stderr ?? "");
    if (stderr) console.error(stderr.trim());
    throw e;
  }
  sp.succeed(`Compiled for ${c.bold(HOST_TARGET)}`);

  const libDir = join(process.cwd(), "zig-out", "lib");
  if (!existsSync(libDir)) return;

  let totalSize = 0;
  const generated: { kind: "loader" | "dts" | "node"; name: string; size: number }[] = [];

  for (const file of readdirSync(libDir)) {
    if (!file.endsWith(".node")) continue;

    const name = file.replace(".node", "");
    const nodePath = join(libDir, file);
    if (existsSync(nodePath)) {
      const size = statSync(nodePath).size;
      totalSize += size;
      generated.push({ kind: "node", name: `zig-out/lib/${file}`, size });
    }

    const loaderPath = join(process.cwd(), `${name}.js`);
    if (!existsSync(loaderPath)) {
      writeFileSync(loaderPath, `module.exports = require('./zig-out/lib/${file}');\n`);
      generated.push({ kind: "loader", name: `${name}.js`, size: statSync(loaderPath).size });
    }

    const dtsSource = join(libDir, `${name}.d.ts`);
    if (existsSync(dtsSource)) {
      const dest = join(process.cwd(), `${name}.d.ts`);
      copyFileSync(dtsSource, dest);
      generated.push({ kind: "dts", name: `${name}.d.ts`, size: statSync(dest).size });
    }
  }

  if (!quiet && generated.length > 0) {
    blank();
    plain(c.dim("Output"));
    const labelWidth = generated.reduce((w, g) => Math.max(w, g.name.length), 0);
    for (const g of generated) {
      const sizeStr = c.gray(formatSize(g.size));
      const padding = " ".repeat(labelWidth - g.name.length + 2);
      const tag = g.kind === "node" ? c.cyan("•") : c.gray("•");
      plain(`   ${tag}  ${g.name}${padding}${sizeStr}`);
    }
    blank();
    done(`Build complete  ${c.dim("·")}  ${c.bold(formatSize(totalSize))} compiled`);
  }
}

export async function buildRelease(optimize: string): Promise<void> {
  const optFlag = ` --release=${optimize}`;

  banner("napi-zig", `${CLI_VERSION}  ·  cross-compile  ·  ${formatOptimize(optimize)}`);

  // zig's WriteFiles step adds without removing, so a renamed scope leaves
  // stale dirs in zig-out/npm that the reconciler would otherwise copy back.
  const srcBase = join(process.cwd(), "zig-out", "npm");
  if (existsSync(srcBase)) rmSync(srcBase, { recursive: true, force: true });

  const expectedTargets = detectExpectedTargets();
  const targets = expectedTargets.length > 0 ? expectedTargets : ["all platforms"];

  const grid = new TaskList(
    `Cross-compiling`,
    targets.map((t) => ({ id: t, label: t, state: "active" as const })),
    { columns: 3, hint: c.dim(formatOptimize(optimize)) },
  ).start();

  const completed = new Set<string>();
  const poll = setInterval(() => {
    const built = listBuiltTargets(srcBase);
    for (const t of built) {
      if (!completed.has(t)) {
        completed.add(t);
        grid.setState(t, "ok");
      }
    }
  }, 250);

  let buildErr: unknown;
  try {
    await run(`zig build -Dnpm=true${optFlag}`);
  } catch (e) {
    buildErr = e;
  }
  clearInterval(poll);

  const built = listBuiltTargets(srcBase);
  for (const t of targets) {
    if (built.has(t)) grid.setState(t, "ok");
    else if (buildErr) grid.setState(t, "fail");
    else grid.setState(t, "skip", "not generated");
  }

  if (buildErr) {
    grid.finish(false, `Cross-compilation failed`);
    blank();
    const stderr = String((buildErr as { stderr?: string }).stderr ?? "");
    if (stderr) console.error(stderr.trim());
    throw buildErr;
  }

  grid.finish(true, `Compiled ${c.bold(String(built.size))} platforms`);

  const destBase = join(process.cwd(), "npm");

  if (!existsSync(srcBase)) {
    blank();
    uiFail("No npm output found in zig-out/npm/.");
    uiNote("Make sure your build.zig uses addLib with .npm config.");
    process.exit(1);
  }

  blank();

  const generatedPkgs = readdirSync(srcBase).filter((n) =>
    statSync(join(srcBase, n)).isDirectory(),
  );

  const syncTasks: { id: string; label: string }[] = [];
  for (const pkgName of generatedPkgs) {
    const srcPkg = join(srcBase, pkgName);
    syncTasks.push({ id: `main:${pkgName}`, label: `${pkgName}` });
    for (const rel of listBindingDirs(srcPkg)) {
      syncTasks.push({ id: `bind:${pkgName}:${rel}`, label: `${pkgName}/${rel}` });
    }
  }

  const syncList = new TaskList(`Syncing npm packages`, syncTasks, { columns: 1 }).start();

  const notes: string[] = [];

  for (const pkgName of generatedPkgs) {
    const srcPkg = join(srcBase, pkgName);
    const destPkg = join(destBase, pkgName);

    const fresh = !existsSync(destPkg);
    mkdirSync(destPkg, { recursive: true });

    syncList.setState(`main:${pkgName}`, "active");
    const result = reconcilePackage(srcPkg, destPkg, (rel) => {
      syncList.setState(`bind:${pkgName}:${rel}`, "active");
    });
    notes.push(...result.notes);
    syncList.setState(`main:${pkgName}`, "ok", fresh ? "created" : "reconciled");
    for (const rel of result.bindings) {
      syncList.setState(
        `bind:${pkgName}:${rel}`,
        "ok",
        result.freshBindings.has(rel) ? "new" : undefined,
      );
    }
  }

  syncList.finish(true, `Synced ${c.bold(String(syncTasks.length))} packages`);

  if (notes.length > 0) {
    blank();
    plain(c.dim("Notes"));
    for (const n of notes) plain(`   ${c.gray("›")}  ${n}`);
  }

  if (existsSync(destBase)) {
    const generated = new Set(generatedPkgs);
    const orphans = readdirSync(destBase)
      .filter((n) => statSync(join(destBase, n)).isDirectory())
      .filter((n) => !generated.has(n));

    if (orphans.length > 0) {
      blank();
      uiWarn(
        `Orphan director${orphans.length > 1 ? "ies" : "y"} in npm/: ${orphans
          .map((n) => `npm/${n}/`)
          .join(", ")}`,
      );
      uiNote(`These do not match any package generated by build.zig. If you renamed`);
      uiNote(`the addon's .name, copy any user fields from the old main package.json`);
      uiNote(`into the new one and delete the orphan folder(s).`);
    }
  }

  blank();
  done(`Cross-compilation complete`);
}

function detectExpectedTargets(): string[] {
  const npmDir = join(process.cwd(), "npm");
  if (existsSync(npmDir)) {
    const found = new Set<string>();
    for (const addon of readdirSync(npmDir)) {
      const addonDir = join(npmDir, addon);
      if (!statSync(addonDir).isDirectory()) continue;
      for (const scope of readdirSync(addonDir)) {
        if (!scope.startsWith("@")) continue;
        const scopeDir = join(addonDir, scope);
        if (!statSync(scopeDir).isDirectory()) continue;
        for (const binding of readdirSync(scopeDir)) {
          if (binding.startsWith("binding-")) {
            found.add(binding.slice("binding-".length));
          }
        }
      }
    }
    if (found.size > 0) return [...found].sort();
  }

  return [
    "linux-x64-gnu",
    "linux-arm64-gnu",
    "linux-x64-musl",
    "linux-arm64-musl",
    "darwin-x64",
    "darwin-arm64",
    "win32-x64",
    "win32-arm64",
    "freebsd-x64",
    "wasm32-wasi",
  ];
}

function listBuiltTargets(srcBase: string): Set<string> {
  const out = new Set<string>();
  if (!existsSync(srcBase)) return out;
  for (const addon of readdirSync(srcBase)) {
    const addonDir = join(srcBase, addon);
    if (!statSync(addonDir).isDirectory()) continue;
    for (const scope of readdirSync(addonDir)) {
      if (!scope.startsWith("@")) continue;
      const scopeDir = join(addonDir, scope);
      if (!statSync(scopeDir).isDirectory()) continue;
      for (const binding of readdirSync(scopeDir)) {
        if (!binding.startsWith("binding-")) continue;
        const bindDir = join(scopeDir, binding);
        if (!statSync(bindDir).isDirectory()) continue;
        const hasBinary = readdirSync(bindDir).some(
          (f) => f.endsWith(".node") || f.endsWith(".wasm"),
        );
        if (hasBinary) out.add(binding.slice("binding-".length));
      }
    }
  }
  return out;
}

interface ReconcileResult {
  notes: string[];
  bindings: string[];
  freshBindings: Set<string>;
}

function reconcilePackage(
  src: string,
  dest: string,
  onBindingStart?: (rel: string) => void,
): ReconcileResult {
  const notes: string[] = [];

  const existingMain = readJson(join(dest, "package.json")) ?? {};
  const generatedMain = readJson(join(src, "package.json")) ?? {};
  const version = (existingMain.version as string | undefined) ?? "0.0.0";

  const oldScopes = scopesFromOptionalDeps(existingMain.optionalDependencies);
  const newScopes = scopesFromOptionalDeps(generatedMain.optionalDependencies);
  if (oldScopes.size > 0 && !setsEqual(oldScopes, newScopes)) {
    notes.push(
      `Scope changed: ${formatScopes(oldScopes)} → ${formatScopes(newScopes)}. Migrating bindings.`,
    );
  }

  const merged = mergeMainPackageJson(existingMain, generatedMain, version);
  writeJson(join(dest, "package.json"), merged);

  for (const f of ["binding.js", "index.d.ts"]) {
    const srcF = join(src, f);
    if (existsSync(srcF)) copyFileSync(srcF, join(dest, f));
  }

  // index.js is the user's seam: seed once, then leave it alone.
  const srcIndex = join(src, "index.js");
  const destIndex = join(dest, "index.js");
  if (!existsSync(destIndex) && existsSync(srcIndex)) {
    copyFileSync(srcIndex, destIndex);
  }

  const newBindings = listBindingDirs(src);
  const newBindingSet = new Set(newBindings);
  const freshBindings = new Set<string>();

  for (const rel of newBindings) {
    onBindingStart?.(rel);
    const srcBind = join(src, rel);
    const destBind = join(dest, rel);
    const fresh = !existsSync(destBind);
    if (fresh) freshBindings.add(rel);
    mkdirSync(destBind, { recursive: true });

    for (const f of readdirSync(srcBind)) {
      if (f.endsWith(".node") || f.endsWith(".wasm")) {
        copyFileSync(join(srcBind, f), join(destBind, f));
      }
    }

    const generated = readJson(join(srcBind, "package.json")) ?? {};
    const existing = readJson(join(destBind, "package.json")) ?? undefined;
    const mergedBind = mergeBindingPackageJson(existing, generated, version);
    writeJson(join(destBind, "package.json"), mergedBind);
  }

  for (const rel of listBindingDirs(dest)) {
    if (!newBindingSet.has(rel)) {
      rmSync(join(dest, rel), { recursive: true, force: true });
    }
  }

  // an entire scope renamed will leave the old scope dir empty after the loop above.
  for (const entry of readdirSync(dest)) {
    if (!entry.startsWith("@")) continue;
    const scopeDir = join(dest, entry);
    if (!statSync(scopeDir).isDirectory()) continue;
    if (readdirSync(scopeDir).length === 0) rmSync(scopeDir, { recursive: true });
  }

  return { notes, bindings: newBindings, freshBindings };
}

const MAIN_POLICY_FIELDS = new Set([
  "name",
  "type",
  "main",
  "types",
  "files",
  "optionalDependencies",
  "version",
]);

const BINDING_POLICY_FIELDS = new Set(["name", "os", "cpu", "libc", "main", "files", "version"]);

// start from generated (canonical field order + policy fields), layer the
// existing file's user fields on top, then force version + lockstep deps.
function mergeMainPackageJson(
  existing: Record<string, unknown>,
  generated: Record<string, unknown>,
  version: string,
): Record<string, unknown> {
  const out: Record<string, unknown> = { ...generated };
  const policy = policyFields(MAIN_POLICY_FIELDS, generated);

  for (const [k, v] of Object.entries(existing)) {
    if (!policy.has(k)) out[k] = v;
  }

  out.files = mergeFiles(arrayOfStrings(existing.files), arrayOfStrings(generated.files));

  if (out.optionalDependencies && typeof out.optionalDependencies === "object") {
    const deps: Record<string, string> = {};
    for (const k of Object.keys(out.optionalDependencies as Record<string, unknown>)) {
      deps[k] = version;
    }
    out.optionalDependencies = deps;
  }

  out.version = version;
  return out;
}

function mergeBindingPackageJson(
  existing: Record<string, unknown> | undefined,
  generated: Record<string, unknown>,
  version: string,
): Record<string, unknown> {
  const out: Record<string, unknown> = { ...generated };

  if (existing) {
    const policy = policyFields(BINDING_POLICY_FIELDS, generated);
    for (const [k, v] of Object.entries(existing)) {
      if (!policy.has(k)) out[k] = v;
    }
  }

  out.version = version;
  return out;
}

// `repository` is opt-in: when build.zig sets `.npm.repository`, the
// generator emits the field and we treat it as policy so the build.zig
// value wins. when it's not set, generated has no `repository`, the
// rule below is a no-op, and any user-edited value in package.json is
// preserved as before.
function policyFields(base: Set<string>, generated: Record<string, unknown>): Set<string> {
  if (!("repository" in generated)) return base;
  const out = new Set(base);
  out.add("repository");
  return out;
}

// Canonical entries (index.js, binding.js, index.d.ts) must always be present
// for the package to load; everything else is the user's to add.
function mergeFiles(existing: string[], canonical: string[]): string[] {
  if (existing.length === 0) return canonical;
  const seen = new Set<string>();
  const merged: string[] = [];
  for (const f of existing) {
    if (!seen.has(f)) {
      seen.add(f);
      merged.push(f);
    }
  }
  for (const f of canonical) {
    if (!seen.has(f)) {
      seen.add(f);
      merged.push(f);
    }
  }
  return merged;
}

function arrayOfStrings(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v.filter((x): x is string => typeof x === "string");
}

function listBindingDirs(root: string): string[] {
  const result: string[] = [];
  for (const scope of readdirSync(root)) {
    if (!scope.startsWith("@")) continue;
    const scopePath = join(root, scope);
    if (!statSync(scopePath).isDirectory()) continue;

    for (const bind of readdirSync(scopePath)) {
      const bindPath = join(scopePath, bind);
      if (!statSync(bindPath).isDirectory()) continue;
      result.push(relative(root, bindPath));
    }
  }
  return result;
}

function scopesFromOptionalDeps(deps: unknown): Set<string> {
  const out = new Set<string>();
  if (!deps || typeof deps !== "object") return out;
  for (const k of Object.keys(deps as Record<string, unknown>)) {
    if (k.startsWith("@")) {
      const scope = k.split("/")[0];
      if (scope) out.add(scope);
    }
  }
  return out;
}

function setsEqual<T>(a: Set<T>, b: Set<T>): boolean {
  if (a.size !== b.size) return false;
  for (const v of a) if (!b.has(v)) return false;
  return true;
}

function formatScopes(s: Set<string>): string {
  if (s.size === 0) return "(none)";
  return [...s].join(", ");
}

function readJson(path: string): Record<string, unknown> | undefined {
  if (!existsSync(path)) return undefined;
  return JSON.parse(readFileSync(path, "utf-8")) as Record<string, unknown>;
}

function writeJson(path: string, value: Record<string, unknown>): void {
  writeFileSync(path, JSON.stringify(value, null, 2) + "\n");
}
