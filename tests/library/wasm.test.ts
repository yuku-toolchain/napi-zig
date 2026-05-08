import { spawnSync } from "bun";
import { describe, expect, test } from "bun:test";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fixtureDir = join(here, "..", "fixture-wasm");

describe("wasm fallback", () => {
  // The cold-cache `zig build -Dnpm=true` blows past bun's default 5s budget
  // on CI runners. Local runs after the first hit are well under a second.
  test("smoke.mjs passes under node", () => {
    const build = spawnSync({
      cmd: ["zig", "build", "-Dnpm=true"],
      cwd: fixtureDir,
      stdout: "pipe",
      stderr: "pipe",
    });
    if (build.exitCode !== 0) {
      throw new Error(`wasm fixture build failed:\n${new TextDecoder().decode(build.stderr)}`);
    }

    const run = spawnSync({
      cmd: ["node", "smoke.mjs"],
      cwd: fixtureDir,
      stdout: "pipe",
      stderr: "pipe",
    });

    const stdout = new TextDecoder().decode(run.stdout);
    const stderr = new TextDecoder().decode(run.stderr);

    // On non-zero exit, surface stderr in the thrown error so CI logs show
    // the underlying cause (node:wasi unavailable, missing emnapi dep, etc).
    if (run.exitCode !== 0) {
      throw new Error(
        `node smoke.mjs exited ${run.exitCode}\nstdout:\n${stdout}\nstderr:\n${stderr}`,
      );
    }

    expect(stdout).toContain("wasm fixture: ok");
  }, 120_000);
});
