import { spawnSync } from "bun";
import { createRequire } from "node:module";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fixtureDir = join(here, "..", "fixture-lib");
const nodePath = join(fixtureDir, "zig-out", "lib", "fixture.node");
const require = createRequire(import.meta.url);

let cached: unknown | undefined;

export function loadFixture(): any {
  if (cached) return cached;

  const result = spawnSync({
    cmd: ["zig", "build"],
    cwd: fixtureDir,
    stdout: "pipe",
    stderr: "pipe",
  });

  if (result.exitCode !== 0) {
    const out = new TextDecoder().decode(result.stdout);
    const err = new TextDecoder().decode(result.stderr);
    throw new Error(
      `fixture-lib build failed (exit ${result.exitCode})\n` + `stdout:\n${out}\nstderr:\n${err}`,
    );
  }

  cached = require(nodePath);
  return cached;
}
