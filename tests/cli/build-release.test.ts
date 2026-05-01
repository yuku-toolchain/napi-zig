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
      "@fixture/binding-linux-x64-gnu",
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

  test("subsequent runs only update .node files, everything else is byte-identical", async () => {
    const dir = stageCliFixture();
    cleanup.push(dir);

    await withCwd(dir, () => buildRelease("fast"));
    const npmRoot = join(dir, "npm");
    const initial = listAllFiles(npmRoot);
    const initialHashes: Record<string, string> = {};
    for (const f of initial) initialHashes[f] = sha256(join(npmRoot, f));

    const pkgPath = join(npmRoot, "fcli", "package.json");
    const initialMtime = statSync(pkgPath).mtimeMs;

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

    void initialMtime;
  }, 180_000);
});
