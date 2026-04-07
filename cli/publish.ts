import { execSync } from "node:child_process";
import ora from "ora";
import { discoverPackages } from "./npm.js";

export interface PublishOptions {
  provenance?: boolean;
}

export function publish(options: PublishOptions): void {
  const packages = discoverPackages();
  const bindings = packages.filter((p) => !p.main);
  const main = packages.find((p) => p.main);

  const useProvenance = options.provenance ?? !!process.env["CI"];
  const flags = ["--access public"];
  if (useProvenance) flags.push("--provenance");
  const flagStr = flags.join(" ");

  // publish bindings first
  for (const pkg of bindings) {
    publishPackage(pkg.name, pkg.dir, flagStr);
  }

  // publish main package last
  if (main) {
    publishPackage(main.name, main.dir, flagStr);
  }
}

function publishPackage(name: string, dir: string, flags: string): void {
  const spinner = ora(`Publishing ${name}...`).start();
  try {
    execSync(`npm publish ${flags}`, { cwd: dir, stdio: "pipe" });
    spinner.succeed(`Published ${name}`);
  } catch (error: unknown) {
    const stderr = String((error as { stderr?: Buffer }).stderr ?? "");
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
