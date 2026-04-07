import { exec, execFile, execFileSync, spawn } from "node:child_process";
import { promisify } from "node:util";
import ora from "ora";
import pkg from "../package.json" with { type: "json" };

const execAsync = promisify(exec);
const execFileAsync = promisify(execFile);

export const CLI_VERSION: string = pkg.version;

export const bold = (s: string): string => `\x1b[1m${s}\x1b[0m`;
export const green = (s: string): string => `\x1b[32m${s}\x1b[0m`;

export async function run(
  cmd: string,
  options?: { cwd?: string },
): Promise<{ stdout: string; stderr: string }> {
  return execAsync(cmd, { cwd: options?.cwd });
}

export async function runArgs(
  cmd: string,
  args: string[],
  options?: { cwd?: string },
): Promise<{ stdout: string; stderr: string }> {
  return execFileAsync(cmd, args, { cwd: options?.cwd });
}

export function runInherit(cmd: string, options?: { cwd?: string }): Promise<void> {
  return new Promise((resolve, reject) => {
    const child = spawn(cmd, { stdio: "inherit", shell: true, cwd: options?.cwd });
    child.on("close", (code) => {
      if (code === 0) resolve();
      else reject(new Error(`Command exited with code ${code}`));
    });
  });
}

export function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export async function packageExistsOnNpm(name: string): Promise<boolean> {
  try {
    await execAsync(`npm view "${name}" version`, { timeout: 15000 });
    return true;
  } catch {
    return false;
  }
}

export function requireNpmVersion(minMajor: number, minMinor: number, feature: string): void {
  try {
    const version = execFileSync("npm", ["--version"], { encoding: "utf-8" }).trim();
    const parts = version.split(".");
    const major = Number(parts[0]);
    const minor = Number(parts[1]);
    if (major < minMajor || (major === minMajor && minor < minMinor)) {
      ora().fail(`npm ${version} found, but ${feature} requires npm >= ${minMajor}.${minMinor}.0`);
      ora().info("Run: npm install -g npm@latest");
      process.exit(1);
    }
  } catch {
    ora().fail("Could not detect npm version. Is npm installed?");
    process.exit(1);
  }
}
