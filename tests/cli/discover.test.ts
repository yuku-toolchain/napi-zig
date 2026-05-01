import { afterEach, describe, expect, test } from "bun:test";
import { discoverPackages, updateVersions } from "../../cli/src/npm";
import { rmTemp, tempDir, writeJsonTree, readJson } from "../helpers/fs";
import { withCwd } from "../helpers/withCwd";

let cleanup: string[] = [];

afterEach(() => {
  for (const d of cleanup) rmTemp(d);
  cleanup = [];
});

function setup(files: Record<string, unknown>): string {
  const root = tempDir();
  cleanup.push(root);
  writeJsonTree(root, files);
  return root;
}

describe("discoverPackages", () => {
  test("finds main package + bindings from optionalDependencies", async () => {
    const root = setup({
      "npm/myaddon/package.json": {
        name: "myaddon",
        version: "1.0.0",
        optionalDependencies: {
          "@scope/binding-darwin-arm64": "1.0.0",
          "@scope/binding-linux-x64-gnu": "1.0.0",
        },
      },
      "npm/myaddon/@scope/binding-darwin-arm64/package.json": {
        name: "@scope/binding-darwin-arm64",
        version: "1.0.0",
      },
      "npm/myaddon/@scope/binding-linux-x64-gnu/package.json": {
        name: "@scope/binding-linux-x64-gnu",
        version: "1.0.0",
      },
    });

    await withCwd(root, () => {
      const pkgs = discoverPackages();
      expect(pkgs).toHaveLength(3);

      const main = pkgs.find((p) => p.main);
      expect(main?.name).toBe("myaddon");
      expect(main?.version).toBe("1.0.0");

      const bindings = pkgs.filter((p) => !p.main).map((p) => p.name);
      expect(bindings.sort()).toEqual([
        "@scope/binding-darwin-arm64",
        "@scope/binding-linux-x64-gnu",
      ]);
    });
  });

  test("throws when npm/ directory is missing", async () => {
    const root = setup({});
    await withCwd(root, () => {
      expect(() => discoverPackages()).toThrow("npm/ directory not found");
    });
  });

  test("throws when no packages have optionalDependencies", async () => {
    const root = setup({
      "npm/somewhere/package.json": { name: "somewhere", version: "1.0.0" },
    });
    await withCwd(root, () => {
      expect(() => discoverPackages()).toThrow("No npm packages found");
    });
  });

  test("ignores binding entries listed in optionalDependencies but missing on disk", async () => {
    const root = setup({
      "npm/x/package.json": {
        name: "x",
        version: "1.0.0",
        optionalDependencies: {
          "@scope/binding-foo": "1.0.0",
          "@scope/binding-bar": "1.0.0",
        },
      },
      "npm/x/@scope/binding-foo/package.json": {
        name: "@scope/binding-foo",
        version: "1.0.0",
      },
    });
    await withCwd(root, () => {
      const pkgs = discoverPackages();
      expect(pkgs.map((p) => p.name).sort()).toEqual(["@scope/binding-foo", "x"]);
    });
  });

  test("ignores non-directory entries in npm/", async () => {
    const root = setup({
      "npm/x/package.json": {
        name: "x",
        version: "1.0.0",
        optionalDependencies: { "@s/binding-a": "1.0.0" },
      },
      "npm/x/@s/binding-a/package.json": { name: "@s/binding-a", version: "1.0.0" },
    });
    writeJsonTree(root, { "npm/.junk": "x" });
    await withCwd(root, () => {
      const pkgs = discoverPackages();
      expect(pkgs).toHaveLength(2);
    });
  });
});

describe("updateVersions", () => {
  test("rewrites version on every package + main's optionalDependencies", async () => {
    const root = setup({
      "npm/x/package.json": {
        name: "x",
        version: "1.0.0",
        optionalDependencies: {
          "@s/binding-a": "1.0.0",
          "@s/binding-b": "1.0.0",
        },
      },
      "npm/x/@s/binding-a/package.json": { name: "@s/binding-a", version: "1.0.0" },
      "npm/x/@s/binding-b/package.json": { name: "@s/binding-b", version: "1.0.0" },
    });

    await withCwd(root, () => {
      const pkgs = discoverPackages();
      updateVersions(pkgs, "2.5.0");

      const main = readJson(`${root}/npm/x/package.json`);
      expect(main.version).toBe("2.5.0");
      expect(main.optionalDependencies["@s/binding-a"]).toBe("2.5.0");
      expect(main.optionalDependencies["@s/binding-b"]).toBe("2.5.0");

      const a = readJson(`${root}/npm/x/@s/binding-a/package.json`);
      expect(a.version).toBe("2.5.0");

      const b = readJson(`${root}/npm/x/@s/binding-b/package.json`);
      expect(b.version).toBe("2.5.0");
    });
  });

  test("preserves unrelated fields untouched", async () => {
    const root = setup({
      "npm/x/package.json": {
        name: "x",
        version: "1.0.0",
        description: "should stay",
        license: "MIT",
        optionalDependencies: { "@s/binding-a": "1.0.0" },
      },
      "npm/x/@s/binding-a/package.json": {
        name: "@s/binding-a",
        version: "1.0.0",
        os: ["darwin"],
      },
    });

    await withCwd(root, () => {
      const pkgs = discoverPackages();
      updateVersions(pkgs, "1.2.3");

      const main = readJson(`${root}/npm/x/package.json`);
      expect(main.description).toBe("should stay");
      expect(main.license).toBe("MIT");

      const a = readJson(`${root}/npm/x/@s/binding-a/package.json`);
      expect(a.os).toEqual(["darwin"]);
    });
  });
});
