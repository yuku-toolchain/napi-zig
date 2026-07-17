import { mkdirSync, readFileSync, rmSync, writeFileSync, statSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { createHash, randomBytes } from "node:crypto";

// under the repo instead of os.tmpdir(): staged fixtures reference the repo
// by a relative path in build.zig.zon, and on windows CI the system temp dir
// sits on a different drive (C:) than the checkout (D:), where no relative
// path exists.
const tempRoot = resolve(
  dirname(fileURLToPath(import.meta.url)),
  "..",
  "..",
  ".zig-cache",
  "test-tmp",
);

export function tempDir(): string {
  const dir = join(tempRoot, "napi-zig-test-" + randomBytes(8).toString("hex"));
  mkdirSync(dir, { recursive: true });
  return dir;
}

export function rmTemp(dir: string): void {
  try {
    rmSync(dir, { recursive: true, force: true });
  } catch {}
}

export function writeJsonTree(root: string, files: Record<string, unknown>): void {
  for (const [path, content] of Object.entries(files)) {
    const full = join(root, path);
    mkdirSync(dirname(full), { recursive: true });
    writeFileSync(full, JSON.stringify(content, null, 2));
  }
}

export function readJson(path: string): any {
  return JSON.parse(readFileSync(path, "utf-8"));
}

export function fileExists(path: string): boolean {
  try {
    statSync(path);
    return true;
  } catch {
    return false;
  }
}

export function sha256(path: string): string {
  return createHash("sha256").update(readFileSync(path)).digest("hex");
}
