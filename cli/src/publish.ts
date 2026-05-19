import { existsSync, readdirSync, unlinkSync } from "node:fs";
import { join } from "node:path";
import { discoverPackages } from "./npm";
import { SUPPORTED_PMS, detectPm, isPm, type Pm } from "./pm";
import { TaskList, banner, blank, bullet, c, done, fail as uiFail } from "./ui";
import { CLI_VERSION, run } from "./utils";

export interface PublishOptions {
  pm?: string;
  provenance?: boolean;
}

export async function publish(options: PublishOptions): Promise<void> {
  const packages = discoverPackages();
  const bindings = packages.filter((p) => !p.main);
  const mains = packages.filter((p) => p.main);

  if (options.pm && !isPm(options.pm)) {
    throw new Error(`Unsupported --pm '${options.pm}'. Use one of: ${SUPPORTED_PMS.join(", ")}`);
  }
  const pm = await detectPm(options.pm);
  const useProvenance = options.provenance ?? !!process.env["CI"];
  const reference = mains[0] ?? bindings[0];
  const tag = resolveTag(reference?.version);

  const flags = ["--access public", `--tag ${tag}`];
  if (useProvenance) flags.push("--provenance");
  const flagStr = flags.join(" ");

  banner("napi-zig", `${CLI_VERSION}  ·  publish  ·  ${tag}`);
  bullet(`Version       ${c.bold(reference?.version ?? "?")}`);
  bullet(`Tag           ${c.bold(tag)}`);
  bullet(`Pack with     ${c.bold(pm)}`);
  bullet(`Provenance    ${useProvenance ? c.green("enabled") : c.gray("disabled")}`);
  bullet(
    `Packages      ${c.bold(String(packages.length))}  ${c.gray(`(${bindings.length} bindings + ${mains.length} main)`)}`,
  );
  blank();

  const ordered = [...bindings, ...mains];

  const tasks = new TaskList(
    "Publishing to npm",
    ordered.map((p) => ({ id: p.name, label: p.name })),
    { columns: 1, hint: c.dim(`@${tag}`) },
  ).start();

  let firstError: { pkg: string; stderr: string } | undefined;
  const packCmd = packCommand(pm);

  for (const pkg of ordered) {
    tasks.setState(pkg.name, "active");
    cleanTarballs(pkg.dir);
    try {
      await run(packCmd, { cwd: pkg.dir });
      const tarball = findTarball(pkg.dir);
      if (!tarball) {
        throw new Error(`'${packCmd}' did not produce a .tgz in ${pkg.dir}`);
      }
      await run(`npm publish ${tarball} ${flagStr}`, { cwd: pkg.dir });
      tasks.setState(pkg.name, "ok", c.green(`v${pkg.version}`));
    } catch (error: unknown) {
      const stderr = String((error as { stderr?: string }).stderr ?? "");
      if (
        stderr.includes("previously published") ||
        stderr.includes("cannot publish over") ||
        stderr.includes("EPUBLISHCONFLICT")
      ) {
        tasks.setState(pkg.name, "skip", c.gray("already published"));
      } else {
        const message = stderr.split("\n")[0] ?? (error as Error).message ?? "publish failed";
        tasks.setState(pkg.name, "fail", c.red(message));
        firstError = firstError ?? {
          pkg: pkg.name,
          stderr: stderr || (error as Error).message || "",
        };
      }
    } finally {
      cleanTarballs(pkg.dir);
    }
  }

  if (firstError) {
    tasks.finish(false, `Publish failed at ${c.bold(firstError.pkg)}`);
    blank();
    uiFail(`Publishing ${firstError.pkg} failed`);
    if (firstError.stderr) console.error(firstError.stderr);
    process.exit(1);
  }

  tasks.finish(true, `Published ${c.bold(String(ordered.length))} packages`);
  blank();
  done(`Publish complete`);
}

function packCommand(pm: Pm): string {
  switch (pm) {
    case "bun":
      return "bun pm pack";
    case "pnpm":
      return "pnpm pack";
    case "yarn":
      return "yarn pack";
    case "npm":
      return "npm pack";
  }
}

function cleanTarballs(dir: string): void {
  if (!existsSync(dir)) return;
  for (const entry of readdirSync(dir)) {
    if (!entry.endsWith(".tgz")) continue;
    try {
      unlinkSync(join(dir, entry));
    } catch {
      // ignore
    }
  }
}

function findTarball(dir: string): string | undefined {
  if (!existsSync(dir)) return undefined;
  return readdirSync(dir).find((f) => f.endsWith(".tgz"));
}

function resolveTag(version: string | undefined): string {
  if (!version) return "latest";
  const dash = version.indexOf("-");
  if (dash === -1) return "latest";
  const id = version.slice(dash + 1).split(/[.+]/)[0];
  return id && /^[a-z][a-z0-9-]*$/i.test(id) ? id.toLowerCase() : "next";
}
