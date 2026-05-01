import { copyFileSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { tempDir } from "./fs";

const here = dirname(fileURLToPath(import.meta.url));
const napiRoot = resolve(here, "..", "..");
const cliFixtureRoot = resolve(here, "..", "fixture-cli");

export function stageCliFixture(): string {
  const dir = tempDir();
  mkdirSync(join(dir, "src"), { recursive: true });
  copyFileSync(join(cliFixtureRoot, "build.zig"), join(dir, "build.zig"));
  copyFileSync(join(cliFixtureRoot, "src", "lib.zig"), join(dir, "src", "lib.zig"));

  const realDir = realpathSync(dir);
  const relPath = relative(realDir, napiRoot);
  const zon = readFileSync(join(cliFixtureRoot, "build.zig.zon"), "utf-8");
  const rewritten = zon.replace(/\.path = "[^"]*"/, `.path = "${relPath}"`);
  writeFileSync(join(dir, "build.zig.zon"), rewritten);

  return dir;
}
