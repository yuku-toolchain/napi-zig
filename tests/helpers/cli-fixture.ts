import { copyFileSync, mkdirSync, readFileSync, realpathSync, writeFileSync } from "node:fs";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { tempDir } from "./fs";

const here = dirname(fileURLToPath(import.meta.url));
const napiRoot = resolve(here, "..", "..");
const cliFixtureRoot = resolve(here, "..", "fixture-cli");

export interface StageCliFixtureOptions {
  // Platform enum literals (e.g. ".macos_arm64") replacing the fixture's
  // `.platforms` list. A short list keeps a test's cross-compile fast.
  platforms?: string[];
}

export function stageCliFixture(options?: StageCliFixtureOptions): string {
  const dir = tempDir();
  mkdirSync(join(dir, "src"), { recursive: true });

  let buildZig = readFileSync(join(cliFixtureRoot, "build.zig"), "utf-8");
  if (options?.platforms) {
    buildZig = buildZig.replace(
      /\.platforms = &\.\{[^}]*\}/,
      `.platforms = &.{ ${options.platforms.join(", ")} }`,
    );
  }
  writeFileSync(join(dir, "build.zig"), buildZig);
  copyFileSync(join(cliFixtureRoot, "src", "lib.zig"), join(dir, "src", "lib.zig"));

  const realDir = realpathSync(dir);
  const relPath = relative(realDir, napiRoot).replaceAll("\\", "/");
  const zon = readFileSync(join(cliFixtureRoot, "build.zig.zon"), "utf-8");
  const rewritten = zon.replace(/\.path = "[^"]*"/, `.path = "${relPath}"`);
  writeFileSync(join(dir, "build.zig.zon"), rewritten);

  return dir;
}
