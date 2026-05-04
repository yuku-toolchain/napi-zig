import ora from "ora";
import { discoverPackages } from "./npm";
import { run } from "./utils";

export interface PublishOptions {
  provenance?: boolean;
}

export async function publish(options: PublishOptions): Promise<void> {
  const packages = discoverPackages();
  const bindings = packages.filter((p) => !p.main);
  const main = packages.find((p) => p.main);

  const useProvenance = options.provenance ?? !!process.env["CI"];
  const reference = main ?? bindings[0];
  const tag = resolveTag(reference?.version);

  const flags = ["--access public", `--tag ${tag}`];
  if (useProvenance) flags.push("--provenance");
  const flagStr = flags.join(" ");

  // publish bindings first
  for (const pkg of bindings) {
    await publishPackage(pkg.name, pkg.dir, flagStr);
  }

  // publish main package last
  if (main) {
    await publishPackage(main.name, main.dir, flagStr);
  }
}

function resolveTag(version: string | undefined): string {
  if (!version) return "latest";
  const dash = version.indexOf("-");
  if (dash === -1) return "latest";
  const id = version.slice(dash + 1).split(/[.+]/)[0];
  return id && /^[a-z][a-z0-9-]*$/i.test(id) ? id.toLowerCase() : "next";
}

async function publishPackage(name: string, dir: string, flags: string): Promise<void> {
  const spinner = ora(`Publishing ${name}...`).start();
  try {
    await run(`npm publish ${flags}`, { cwd: dir });
    spinner.succeed(`Published ${name}`);
  } catch (error: unknown) {
    const stderr = String((error as { stderr?: string }).stderr ?? "");
    if (
      stderr.includes("previously published") ||
      stderr.includes("cannot publish over") ||
      stderr.includes("EPUBLISHCONFLICT")
    ) {
      spinner.info(`${name} already published, skipping`);
    } else {
      spinner.fail(`Failed to publish ${name}`);
      console.error(stderr);
      process.exit(1);
    }
  }
}
