import { mkdirSync, readFileSync, rmSync, writeFileSync, statSync } from "node:fs";
import { dirname, join } from "node:path";
import { tmpdir } from "node:os";
import { createHash, randomBytes } from "node:crypto";

export function tempDir(): string {
  const dir = join(tmpdir(), "napi-zig-test-" + randomBytes(8).toString("hex"));
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
