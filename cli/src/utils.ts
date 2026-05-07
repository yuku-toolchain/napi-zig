import { exec, execFile, execFileSync, spawn } from "node:child_process";
import { promisify } from "node:util";
import pkg from "../package.json" with { type: "json" };
import { Spinner, c, fail as uiFail, info as uiInfo, plain } from "./ui";

const execAsync = promisify(exec);
const execFileAsync = promisify(execFile);

export const CLI_VERSION: string = pkg.version;

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

export async function ensureNpmScope(scope: string): Promise<void> {
  const scopeName = scope.replace(/^@/, "");

  let username: string;
  try {
    const r = await execAsync("npm whoami", { timeout: 15000 });
    username = r.stdout.trim();
  } catch {
    uiFail("Not logged in to npm. Run 'npm login' first.");
    process.exit(1);
  }

  // a user's own scope auto-exists; only org scopes need the npm org check.
  if (scopeName === username) return;

  const sp = new Spinner(`Verifying npm scope ${c.bold("@" + scopeName)}`).start();
  try {
    await execAsync(`npm org ls "${scopeName}" --json`, { timeout: 15000 });
    sp.succeed(`Scope ${c.bold("@" + scopeName)} verified`);
  } catch (e: unknown) {
    sp.fail(`Scope ${c.bold("@" + scopeName)} not found or not accessible to ${c.bold(username)}`);
    const stderr = String((e as { stderr?: string }).stderr ?? "").trim();
    if (stderr) console.error(stderr.split("\n").slice(0, 3).join("\n"));
    console.error();
    plain(
      `Per-platform bindings publish under the scope ${c.bold("@" + scopeName)}, so the scope must`,
    );
    plain(`exist on npm before publishing. Two options:`);
    console.error();
    plain(
      `  1. Create the org at ${c.cyan("https://www.npmjs.com/org/create?orgname=" + scopeName)}`,
    );
    plain(`     (it's fine and recommended to match the org name to the package name).`);
    plain(`  2. Change the scope in build.zig (the .scope field inside the .npm block)`);
    plain(`     to a scope you already own, then re-run 'napi build --release'.`);
    process.exit(1);
  }
}

export function requireNpmVersion(minMajor: number, minMinor: number, feature: string): void {
  try {
    const version = execFileSync("npm", ["--version"], { encoding: "utf-8" }).trim();
    const parts = version.split(".");
    const major = Number(parts[0]);
    const minor = Number(parts[1]);
    if (major < minMajor || (major === minMajor && minor < minMinor)) {
      uiFail(
        `npm ${c.bold(version)} found, but ${feature} requires npm >= ${c.bold(`${minMajor}.${minMinor}.0`)}`,
      );
      uiInfo(`Run: ${c.cyan("npm install -g npm@latest")}`);
      process.exit(1);
    }
  } catch {
    uiFail("Could not detect npm version. Is npm installed?");
    process.exit(1);
  }
}

export const bold = (s: string): string => c.bold(s);
export const green = (s: string): string => c.green(s);
