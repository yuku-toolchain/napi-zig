import { spawnSync } from "bun";
import { describe, expect, test } from "bun:test";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const fixtureDir = join(here, "..", "fixture-wasm");

describe("wasm fallback", () => {
  test("smoke.mjs passes under node", () => {
    const build = spawnSync({
      cmd: ["zig", "build", "-Dnpm=true"],
      cwd: fixtureDir,
      stdout: "pipe",
      stderr: "pipe",
    });
    if (build.exitCode !== 0) {
      throw new Error(
        `wasm fixture build failed:\n${new TextDecoder().decode(build.stderr)}`,
      );
    }

    const run = spawnSync({
      cmd: ["node", "smoke.mjs"],
      cwd: fixtureDir,
      stdout: "pipe",
      stderr: "pipe",
    });

    const stdout = new TextDecoder().decode(run.stdout);
    const stderr = new TextDecoder().decode(run.stderr);
    expect({ exitCode: run.exitCode, stderr, stdout }).toEqual({
      exitCode: 0,
      stderr: stderr,
      stdout: expect.stringContaining("wasm fixture: ok"),
    });
  });
});
