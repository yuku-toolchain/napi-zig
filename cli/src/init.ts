import ora from "ora";
import { discoverPackages } from "./npm";
import { packageExistsOnNpm, requireNpmVersion, run, runInherit, sleep } from "./utils";

export interface NpmInitOptions {
  repo: string;
  workflow: string;
}

export async function npmInit(options: NpmInitOptions): Promise<void> {
  const packages = discoverPackages();
  const bindings = packages.filter((p) => !p.main);
  const main = packages.find((p) => p.main);
  const ordered = [...bindings, ...(main ? [main] : [])];

  // check which packages are new
  const checkSpinner = ora("Checking which packages need publishing...").start();
  const existsResults = await Promise.all(ordered.map((pkg) => packageExistsOnNpm(pkg.name)));
  const newPackages = ordered.filter((_, i) => !existsResults[i]);
  const existingCount = ordered.length - newPackages.length;
  checkSpinner.succeed(
    newPackages.length === 0
      ? `All ${ordered.length} packages already exist on npm`
      : `${newPackages.length} new, ${existingCount} already on npm`,
  );

  // publish new packages, use stdio "inherit" so npm's
  // interactive auth (OTP / browser-based 2FA) works for the user
  if (newPackages.length > 0) {
    console.log();
    for (const pkg of newPackages) {
      ora().info(`Publishing ${pkg.name}@${pkg.version}...`);
      try {
        await runInherit("npm publish --access public", { cwd: pkg.dir });
      } catch {}
      console.log();
    }
  }

  // configure trusted publishing for new packages only
  if (newPackages.length > 0) {
    requireNpmVersion(11, 10, "trusted publishing");
    ora().info(`Configuring trusted publishing for ${newPackages.length} new packages`);

    for (let i = 0; i < newPackages.length; i++) {
      const pkg = newPackages[i]!;
      const spinner = ora(`[${i + 1}/${newPackages.length}] ${pkg.name}...`).start();

      try {
        await run(
          `npm trust github "${pkg.name}" --file "${options.workflow}" --repo "${options.repo}" --yes`,
        );
        spinner.succeed(`[${i + 1}/${newPackages.length}] ${pkg.name}`);
      } catch (error: unknown) {
        const stderr = String((error as { stderr?: string }).stderr ?? "");
        spinner.fail(`[${i + 1}/${newPackages.length}] ${pkg.name}: ${stderr.split("\n")[0]}`);
      }

      // rate-limit: 2s between calls to avoid npm throttling
      if (i < newPackages.length - 1) {
        await sleep(2000);
      }
    }
  }

  console.log();
  ora().succeed("Done.");
}
