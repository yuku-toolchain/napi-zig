import { discoverPackages } from "./npm";
import {
  TaskList,
  banner,
  blank,
  bullet,
  c,
  done,
  fail as uiFail,
} from "./ui";
import { CLI_VERSION, run } from "./utils";

export interface PublishOptions {
  provenance?: boolean;
}

export async function publish(options: PublishOptions): Promise<void> {
  const packages = discoverPackages();
  const bindings = packages.filter((p) => !p.main);
  const mains = packages.filter((p) => p.main);

  const useProvenance = options.provenance ?? !!process.env["CI"];
  const reference = mains[0] ?? bindings[0];
  const tag = resolveTag(reference?.version);

  const flags = ["--access public", `--tag ${tag}`];
  if (useProvenance) flags.push("--provenance");
  const flagStr = flags.join(" ");

  banner("napi-zig", `${CLI_VERSION}  ·  publish  ·  ${tag}`);
  bullet(`Version       ${c.bold(reference?.version ?? "?")}`);
  bullet(`Tag           ${c.bold(tag)}`);
  bullet(`Provenance    ${useProvenance ? c.green("enabled") : c.gray("disabled")}`);
  bullet(`Packages      ${c.bold(String(packages.length))}  ${c.gray(`(${bindings.length} bindings + ${mains.length} main)`)}`);
  blank();

  const ordered = [...bindings, ...mains];

  const tasks = new TaskList(
    "Publishing to npm",
    ordered.map((p) => ({ id: p.name, label: p.name })),
    { columns: 1, hint: c.dim(`@${tag}`) },
  ).start();

  let firstError: { pkg: string; stderr: string } | undefined;

  for (const pkg of ordered) {
    tasks.setState(pkg.name, "active");
    try {
      await run(`npm publish ${flagStr}`, { cwd: pkg.dir });
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
        tasks.setState(pkg.name, "fail", c.red(stderr.split("\n")[0] ?? "publish failed"));
        firstError = firstError ?? { pkg: pkg.name, stderr };
      }
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

function resolveTag(version: string | undefined): string {
  if (!version) return "latest";
  const dash = version.indexOf("-");
  if (dash === -1) return "latest";
  const id = version.slice(dash + 1).split(/[.+]/)[0];
  return id && /^[a-z][a-z0-9-]*$/i.test(id) ? id.toLowerCase() : "next";
}
