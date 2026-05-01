import { afterEach, describe, expect, test } from "bun:test";
import { join } from "node:path";
import { readFileSync } from "node:fs";
import { buildDev } from "../../cli/src/build";
import { stageCliFixture } from "../helpers/cli-fixture";
import { fileExists, rmTemp } from "../helpers/fs";
import { withCwd } from "../helpers/withCwd";

let cleanup: string[] = [];

afterEach(() => {
  for (const d of cleanup) rmTemp(d);
  cleanup = [];
});

describe("napi build (dev)", () => {
  test(
    "produces zig-out/lib/<name>.node",
    async () => {
      const dir = stageCliFixture();
      cleanup.push(dir);

      await withCwd(dir, () => buildDev(undefined));

      expect(fileExists(join(dir, "zig-out", "lib", "fcli.node"))).toBe(true);
    },
    30000,
  );

  test(
    "creates a <name>.js loader pointing at zig-out/lib/<name>.node",
    async () => {
      const dir = stageCliFixture();
      cleanup.push(dir);

      await withCwd(dir, () => buildDev(undefined));

      const loaderPath = join(dir, "fcli.js");
      expect(fileExists(loaderPath)).toBe(true);

      const contents = readFileSync(loaderPath, "utf-8");
      expect(contents).toContain("./zig-out/lib/fcli.node");
      expect(contents).toContain("require");
    },
    30000,
  );

  test(
    "does NOT overwrite an existing <name>.js loader",
    async () => {
      const dir = stageCliFixture();
      cleanup.push(dir);

      const loaderPath = join(dir, "fcli.js");
      const userContent = "// user-managed loader, must be preserved";
      await Bun.write(loaderPath, userContent);

      await withCwd(dir, () => buildDev(undefined));

      expect(readFileSync(loaderPath, "utf-8")).toBe(userContent);
    },
    30000,
  );

  test(
    "optimize flag is forwarded to zig",
    async () => {
      const dir = stageCliFixture();
      cleanup.push(dir);
      // pass --release=safe via the CLI option; test passes if the build
      // succeeds (we don't introspect optimization mode in produced binary).
      await withCwd(dir, () => buildDev("safe"));
      expect(fileExists(join(dir, "zig-out", "lib", "fcli.node"))).toBe(true);
    },
    60000,
  );
});
