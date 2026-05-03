import { afterEach, describe, expect, test } from "bun:test";
import { join } from "node:path";
import { readFileSync, readdirSync, statSync } from "node:fs";
import { buildRelease } from "../../cli/src/build";
import { stageCliFixture } from "../helpers/cli-fixture";
import { fileExists, readJson, rmTemp, sha256 } from "../helpers/fs";
import { withCwd } from "../helpers/withCwd";

let cleanup: string[] = [];

afterEach(() => {
  for (const d of cleanup) rmTemp(d);
  cleanup = [];
});

function listAllFiles(root: string): string[] {
  const out: string[] = [];
  function walk(dir: string) {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const p = join(dir, entry.name);
      if (entry.isDirectory()) walk(p);
      else if (entry.isFile()) out.push(p);
    }
  }
  walk(root);
  return out.map((p) => p.slice(root.length + 1)).sort();
}

describe("napi build --release", () => {
  test("produces the expected npm scaffolding", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    expect(fileExists(join(dir, "npm", "fcli", "package.json"))).toBe(true);
    expect(fileExists(join(dir, "npm", "fcli", "index.js"))).toBe(true);
    expect(fileExists(join(dir, "npm", "fcli", "binding.js"))).toBe(true);

    const bindingDir = join(dir, "npm", "fcli", "@fixture", "binding-darwin-arm64");
    expect(fileExists(join(bindingDir, "package.json"))).toBe(true);
    expect(fileExists(join(bindingDir, "fcli.node"))).toBe(true);
  }, 120_000);

  test("main package.json has optionalDependencies for each platform", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    const main = readJson(join(dir, "npm", "fcli", "package.json"));
    expect(main.name).toBe("fcli");
    expect(main.type).toBe("module");
    expect(main.main).toBe("index.js");
    expect(Object.keys(main.optionalDependencies).sort()).toEqual([
      "@fixture/binding-darwin-arm64",
      "@fixture/binding-freebsd-x64",
      "@fixture/binding-linux-arm-gnu",
      "@fixture/binding-linux-arm-musl",
      "@fixture/binding-linux-arm64-gnu",
      "@fixture/binding-linux-arm64-musl",
      "@fixture/binding-linux-x64-gnu",
      "@fixture/binding-linux-x64-musl",
      "@fixture/binding-win32-arm64",
      "@fixture/binding-win32-x64",
    ]);
    for (const v of Object.values(main.optionalDependencies)) {
      expect(v).toBe("0.0.0");
    }
    expect(main.files).toContain("index.js");
    expect(main.files).toContain("binding.js");
  }, 180_000);

  test("binding.js contains musl detection + suffix-based loader", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    const binding = readFileSync(join(dir, "npm", "fcli", "binding.js"), "utf-8");
    expect(binding).toContain("isMusl");
    expect(binding).toContain("@fixture");
    expect(binding).toContain("fcli.node");
  }, 120_000);

  test("platform package.json has correct os/cpu fields", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    const pkg = readJson(
      join(dir, "npm", "fcli", "@fixture", "binding-darwin-arm64", "package.json"),
    );
    expect(pkg.name).toBe("@fixture/binding-darwin-arm64");
    expect(pkg.os).toEqual(["darwin"]);
    expect(pkg.cpu).toEqual(["arm64"]);
    expect(pkg.main).toBe("fcli.node");
  }, 120_000);

  test("subsequent runs are idempotent: byte-identical for all non-.node files", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));
    const npmRoot = join(dir, "npm");
    const initial = listAllFiles(npmRoot);
    const initialHashes: Record<string, string> = {};
    for (const f of initial) initialHashes[f] = sha256(join(npmRoot, f));

    await new Promise((r) => setTimeout(r, 50));

    await withCwd(dir, () => buildRelease("fast"));

    const second = listAllFiles(npmRoot);
    expect(second).toEqual(initial);

    for (const f of initial) {
      const newHash = sha256(join(npmRoot, f));
      if (f.endsWith(".node")) {
        expect(newHash).toBeDefined();
      } else {
        expect(newHash).toBe(initialHashes[f]!);
      }
    }
  }, 180_000);

  test("preserves user-edited fields on the main package.json across rebuilds", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    const pkgPath = join(dir, "npm", "fcli", "package.json");
    const pkg = readJson(pkgPath);
    pkg.description = "user-set description";
    pkg.repository = { type: "git", url: "https://example.com/me" };
    pkg.homepage = "https://example.com/me";
    pkg.keywords = ["zig", "napi"];
    require("node:fs").writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");

    await withCwd(dir, () => buildRelease("fast"));

    const after = readJson(pkgPath);
    expect(after.description).toBe("user-set description");
    expect(after.repository).toEqual({ type: "git", url: "https://example.com/me" });
    expect(after.homepage).toBe("https://example.com/me");
    expect(after.keywords).toEqual(["zig", "napi"]);
    // Policy fields still come from build.zig.
    expect(after.name).toBe("fcli");
    expect(after.main).toBe("index.js");
  }, 180_000);

  test("preserves user-edited index.js across rebuilds", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    const indexPath = join(dir, "npm", "fcli", "index.js");
    const customIndex =
      "// user wrapper\nimport binding from './binding.js';\nexport default { ...binding, hello: () => 'world' };\n";
    require("node:fs").writeFileSync(indexPath, customIndex);

    await withCwd(dir, () => buildRelease("fast"));

    expect(readFileSync(indexPath, "utf-8")).toBe(customIndex);
  }, 180_000);

  test("renaming the scope in build.zig migrates bindings on the next rebuild", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    // Pretend the user got further along: bumped the version, edited the scope.
    const mainPath = join(dir, "npm", "fcli", "package.json");
    const main = readJson(mainPath);
    main.version = "1.4.2";
    for (const k of Object.keys(main.optionalDependencies)) {
      main.optionalDependencies[k] = "1.4.2";
    }
    require("node:fs").writeFileSync(mainPath, JSON.stringify(main, null, 2) + "\n");

    const buildZigPath = join(dir, "build.zig");
    const buildZig = readFileSync(buildZigPath, "utf-8");
    require("node:fs").writeFileSync(
      buildZigPath,
      buildZig.replace(`.scope = "@fixture"`, `.scope = "@renamed"`),
    );

    await withCwd(dir, () => buildRelease("fast"));

    const after = readJson(mainPath);
    // Version preserved, scope migrated, optionalDependencies in lockstep.
    expect(after.version).toBe("1.4.2");
    const keys = Object.keys(after.optionalDependencies);
    expect(keys.every((k) => k.startsWith("@renamed/"))).toBe(true);
    expect(Object.values(after.optionalDependencies).every((v) => v === "1.4.2")).toBe(true);

    // Old scope dir is gone, new one has the bindings.
    const oldScopeDir = join(dir, "npm", "fcli", "@fixture");
    const newScopeDir = join(dir, "npm", "fcli", "@renamed");
    expect(require("node:fs").existsSync(oldScopeDir)).toBe(false);
    expect(require("node:fs").existsSync(newScopeDir)).toBe(true);

    // Each new binding's package.json is at the new version.
    const bindPkg = readJson(join(newScopeDir, "binding-darwin-arm64", "package.json"));
    expect(bindPkg.name).toBe("@renamed/binding-darwin-arm64");
    expect(bindPkg.version).toBe("1.4.2");
  }, 240_000);

  test("removing a platform from .platforms drops its binding directory", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    const dropped = join(dir, "npm", "fcli", "@fixture", "binding-freebsd-x64");
    expect(require("node:fs").existsSync(dropped)).toBe(true);

    const buildZigPath = join(dir, "build.zig");
    const buildZig = readFileSync(buildZigPath, "utf-8");
    require("node:fs").writeFileSync(
      buildZigPath,
      buildZig.replace("                .freebsd_x64,\n", ""),
    );

    await withCwd(dir, () => buildRelease("fast"));

    expect(require("node:fs").existsSync(dropped)).toBe(false);
    const main = readJson(join(dir, "npm", "fcli", "package.json"));
    expect(main.optionalDependencies["@fixture/binding-freebsd-x64"]).toBeUndefined();
  }, 240_000);

  test("refreshes binding.js even when the user changed it", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));

    const bindingPath = join(dir, "npm", "fcli", "binding.js");
    const original = readFileSync(bindingPath, "utf-8");
    require("node:fs").writeFileSync(bindingPath, "// stale junk\n");

    await withCwd(dir, () => buildRelease("fast"));

    expect(readFileSync(bindingPath, "utf-8")).toBe(original);
  }, 180_000);
});
