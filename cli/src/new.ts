import { existsSync, mkdirSync, readdirSync, writeFileSync } from "node:fs";
import { join, resolve } from "node:path";
import { randomBytes } from "node:crypto";
import prompts from "prompts";
import ora from "ora";
import { detect, getUserAgent } from "package-manager-detector/detect";
import { resolveCommand } from "package-manager-detector/commands";
import type { Agent, AgentName } from "package-manager-detector";
import { CLI_VERSION, bold, green, run } from "./utils";
import { buildDev } from "./build";

const NAPI_ZIG_GIT = "git+https://github.com/yuku-toolchain/napi-zig.git/#HEAD";

const SUPPORTED_PMS = ["npm", "yarn", "pnpm", "bun"] as const;
type Pm = (typeof SUPPORTED_PMS)[number];

export interface NewOptions {
  name?: string;
  pm?: string;
}

export async function scaffoldNew(options: NewOptions): Promise<void> {
  const name = await resolveProjectName(options.name);
  const targetDir = resolve(process.cwd(), name);
  if (existsSync(targetDir) && readdirSync(targetDir).length > 0) {
    ora().fail(`Directory ${name} already exists and is not empty`);
    process.exit(1);
  }

  const pm = await resolvePackageManager(options.pm);

  const writeSpinner = ora("Scaffolding project...").start();
  mkdirSync(targetDir, { recursive: true });
  writeFiles(targetDir, name, pm);
  writeSpinner.succeed(`Scaffolded ${bold(name)}`);

  await runInstall(pm, targetDir);
  await runZigFetch(targetDir);
  await runInitialBuild(targetDir);

  printNextSteps(name, pm);
}

async function resolveProjectName(initial: string | undefined): Promise<string> {
  if (initial) {
    const err = validateName(initial);
    if (err !== true) {
      ora().fail(err);
      process.exit(1);
    }
    return initial;
  }
  const r = await prompts(
    {
      type: "text",
      name: "value",
      message: "Project name:",
      validate: (v: string) => validateName(v),
    },
    { onCancel: () => process.exit(1) },
  );
  if (!r.value) process.exit(1);
  return r.value as string;
}

async function resolvePackageManager(initial: string | undefined): Promise<Pm> {
  if (initial && (SUPPORTED_PMS as readonly string[]).includes(initial)) {
    return initial as Pm;
  }
  const detected = await detect().catch(() => null);
  const fallback = parseUserAgent(getUserAgent());
  const guessed: Pm = ((detected?.name as AgentName | undefined) ?? fallback ?? "npm") as Pm;
  const initialIdx = Math.max(0, SUPPORTED_PMS.indexOf(guessed));
  const r = await prompts(
    {
      type: "select",
      name: "value",
      message: "Package manager:",
      choices: SUPPORTED_PMS.map((p) => ({ title: p, value: p })),
      initial: initialIdx,
    },
    { onCancel: () => process.exit(1) },
  );
  if (!r.value) process.exit(1);
  return r.value as Pm;
}

async function runInstall(pm: Pm, cwd: string): Promise<void> {
  const cmd = resolveCommand(pm as Agent, "install", []);
  if (!cmd) return;
  const spinner = ora(`Installing dependencies with ${pm}...`).start();
  try {
    await run(`${cmd.command} ${cmd.args.join(" ")}`.trim(), { cwd });
    spinner.succeed("Installed dependencies");
  } catch (e) {
    spinner.fail(`${pm} install failed`);
    dumpError(e);
    process.exit(1);
  }
}

async function runZigFetch(cwd: string): Promise<void> {
  const spinner = ora("Fetching napi-zig (Zig dependency)...").start();
  try {
    await run(`zig fetch --save "${NAPI_ZIG_GIT}"`, { cwd });
    spinner.succeed("Fetched napi-zig");
  } catch (e) {
    spinner.fail("zig fetch failed (is Zig installed?)");
    dumpError(e);
    process.exit(1);
  }
}

async function runInitialBuild(cwd: string): Promise<void> {
  const original = process.cwd();
  process.chdir(cwd);
  try {
    await buildDev(undefined, { quiet: true });
  } catch {
    process.exit(1);
  } finally {
    process.chdir(original);
  }
}

function dumpError(e: unknown): void {
  const err = e as { stderr?: string; stdout?: string; message?: string };
  const out = (err.stderr ?? "") + (err.stdout ?? "");
  const trimmed = out.trim();
  if (trimmed) console.error(trimmed);
  else if (err.message) console.error(err.message);
}

function printNextSteps(name: string, pm: Pm): void {
  const test = runScript(pm, "test");
  const build = runScript(pm, "build");
  const release = runScript(pm, "release");
  const npmInit = execLocal(
    pm,
    "napi",
    "npm-init",
    "--repo",
    "<owner>/<repo>",
    "--workflow",
    "publish.yml",
  );
  const pad = Math.max(test.length, build.length, release.length, npmInit.length);
  const col = (s: string) => s.padEnd(pad);
  console.log();
  ora().succeed(`Project ${green(name)} ready in ${bold(`./${name}`)}`);
  console.log();
  console.log("Next steps:");
  console.log(`  cd ${name}`);
  console.log(`  ${col(test)}    # run the addon`);
  console.log(`  ${col(build)}    # rebuild after edits`);
  console.log(`  ${col(release)}    # cross-compile every platform`);
  console.log(`  ${col(npmInit)}    # first-time publish + OIDC`);
}

function runScript(pm: Pm, name: string): string {
  const cmd = resolveCommand(pm as Agent, "run", [name]);
  return cmd ? `${cmd.command} ${cmd.args.join(" ")}` : `${pm} run ${name}`;
}

function execLocal(pm: Pm, ...args: string[]): string {
  const cmd = resolveCommand(pm as Agent, "execute-local", args);
  return cmd ? `${cmd.command} ${cmd.args.join(" ")}` : args.join(" ");
}

function jsRunner(pm: Pm): string {
  return pm === "bun" ? "bun run" : "node";
}

function validateName(n: string): true | string {
  if (!n) return "Name is required";
  if (n.startsWith(".") || n.startsWith("_")) return "Name cannot start with . or _";
  if (n.length > 200) return "Name is too long";
  if (!/^[a-z0-9][a-z0-9._-]*$/.test(n)) {
    return "Name must be lowercase, may contain a-z 0-9 - _ .";
  }
  return true;
}

function parseUserAgent(ua: AgentName | null): Pm | undefined {
  if (!ua) return undefined;
  if ((SUPPORTED_PMS as readonly string[]).includes(ua)) return ua as Pm;
  return undefined;
}

function toZigIdentifier(s: string): string {
  let id = s.replace(/[^a-zA-Z0-9_]/g, "_");
  if (/^[0-9]/.test(id)) id = "_" + id;
  return id;
}

// Zig validates the fingerprint as `(crc32(name) << 32) | id`, where
// `id` is a random u32 in [1, 0xffffffff). Match its scheme so `zig fetch`
// accepts the file we write.
function generateFingerprint(name: string): string {
  const checksum = crc32(name);
  let id: number;
  do {
    id = randomBytes(4).readUInt32LE(0);
  } while (id === 0 || id === 0xffffffff);
  const fp = (BigInt(checksum) << 32n) | BigInt(id);
  return "0x" + fp.toString(16).padStart(16, "0");
}

const CRC32_TABLE: number[] = (() => {
  const t: number[] = Array.from({ length: 256 }, () => 0);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? (c >>> 1) ^ 0xedb88320 : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(s: string): number {
  let crc = 0xffffffff;
  const buf = Buffer.from(s);
  for (const byte of buf) crc = (crc >>> 8) ^ CRC32_TABLE[(crc ^ byte) & 0xff]!;
  return (crc ^ 0xffffffff) >>> 0;
}

function writeFiles(dir: string, name: string, pm: Pm): void {
  const zigName = toZigIdentifier(name);
  const fingerprint = generateFingerprint(zigName);

  writeFileSync(join(dir, "package.json"), packageJsonContent(name, pm));
  writeFileSync(join(dir, "build.zig"), buildZigContent(name));
  writeFileSync(join(dir, "build.zig.zon"), buildZigZonContent(zigName, fingerprint));

  mkdirSync(join(dir, "src"));
  writeFileSync(join(dir, "src", "lib.zig"), libZigContent());

  writeFileSync(join(dir, "test.mjs"), testMjsContent(name));
  writeFileSync(join(dir, ".gitignore"), gitignoreContent(name));
  writeFileSync(join(dir, "README.md"), readmeContent(name, pm));

  mkdirSync(join(dir, ".github", "workflows"), { recursive: true });
  writeFileSync(join(dir, ".github", "workflows", "publish.yml"), publishWorkflow(pm));
}

function packageJsonContent(name: string, pm: Pm): string {
  const runner = jsRunner(pm);
  const pkg = {
    name,
    version: "0.0.0",
    description: "",
    license: "MIT",
    scripts: {
      build: "napi build",
      release: "napi build --release",
      bump: "napi bump",
      test: `${runner} test.mjs`,
    },
    devDependencies: {
      "napi-zig": `^${CLI_VERSION}`,
    },
  };
  return JSON.stringify(pkg, null, 2) + "\n";
}

function buildZigContent(name: string): string {
  return `const std = @import("std");
const napi_zig = @import("napi_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    napi_zig.addLib(b, b.dependency("napi_zig", .{}), .{
        .name = "${name}",
        .root = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .npm = .{
            .scope = "@${name}",
            .repository = .{ .url = "https://github.com/your-username/${name}" },
            .dts = .auto,
        },
    });
}
`;
}

function buildZigZonContent(zigName: string, fingerprint: string): string {
  return `.{
    .name = .${zigName},
    .version = "0.0.0",
    .fingerprint = ${fingerprint},
    .minimum_zig_version = "0.17.0",
    .dependencies = .{},
    .paths = .{
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
`;
}

function libZigContent(): string {
  return `const std = @import("std");
const napi = @import("napi-zig");

comptime {
    napi.module(@This());
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn greet(env: napi.Env, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "Hello, {s}!", .{name});
}
`;
}

function testMjsContent(name: string): string {
  return `import addon from "./${name}.js";

console.log("add(2, 3) =", addon.add(2, 3));
console.log("greet('world') =", addon.greet("world"));
`;
}

function gitignoreContent(name: string): string {
  return `node_modules
zig-out
.zig-cache
.DS_Store
*.tgz

# regenerated by \`napi build\`
/${name}.js
/${name}.d.ts
`;
}

function readmeContent(name: string, pm: Pm): string {
  const build = runScript(pm, "build");
  const release = runScript(pm, "release");
  const bump = runScript(pm, "bump");
  const test = runScript(pm, "test");
  const npmInit = execLocal(
    pm,
    "napi",
    "npm-init",
    "--repo",
    "<owner>/<repo>",
    "--workflow",
    "publish.yml",
  );

  return `# ${name}

A Node.js native addon written in Zig with [napi-zig](https://github.com/yuku-toolchain/napi-zig).

## Develop

\`\`\`sh
${build}       # build for the current platform
${test}        # try it out
\`\`\`

Edit \`src/lib.zig\`, rerun \`${build}\`, run \`${test}\`.

## Publish

Update \`.npm.scope\` and \`.npm.repository.url\` in \`build.zig\` to your real npm scope and GitHub repository, then:

\`\`\`sh
${release}
${npmInit}
${bump}    # cut a release (CI publishes via .github/workflows/publish.yml)
\`\`\`
`;
}

function publishWorkflow(pm: Pm): string {
  const setup = workflowSetup(pm);
  const install = workflowInstall(pm);
  const exec = workflowExec(pm);
  return `name: Publish
on:
  push:
    tags: ["v*"]

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with: { version: master }
      - uses: actions/setup-node@v4
        with: { node-version: 24, registry-url: https://registry.npmjs.org }
${setup}      - run: ${install}
      - run: ${exec} napi-zig build --release
      - run: ${exec} napi-zig publish
`;
}

function workflowSetup(pm: Pm): string {
  switch (pm) {
    case "bun":
      return `      - uses: oven-sh/setup-bun@v2\n`;
    case "pnpm":
      return `      - uses: pnpm/action-setup@v4\n        with: { version: 10 }\n`;
    case "yarn":
      return `      - run: corepack enable\n`;
    case "npm":
      return "";
  }
}

function workflowInstall(pm: Pm): string {
  switch (pm) {
    case "bun":
      return "bun install";
    case "pnpm":
      return "pnpm install";
    case "yarn":
      return "yarn install";
    case "npm":
      return "npm install";
  }
}

function workflowExec(pm: Pm): string {
  switch (pm) {
    case "bun":
      return "bunx";
    case "pnpm":
      return "pnpm exec";
    case "yarn":
      return "yarn";
    case "npm":
      return "npx";
  }
}
