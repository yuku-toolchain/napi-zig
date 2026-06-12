import { discoverPackages } from "./npm";
import { Spinner, banner, blank, bullet, c, done, fail, info, note, plain } from "./ui";
import {
  CLI_VERSION,
  ensureNpmScope,
  packageExistsOnNpm,
  packageTrustStatus,
  requireNpmVersion,
  runInherit,
  sleep,
} from "./utils";

export interface NpmInitOptions {
  repo: string;
  workflow: string;
}

export async function npmInit(options: NpmInitOptions): Promise<void> {
  const packages = discoverPackages();
  const bindings = packages.filter((p) => p.kind === "binding");
  const mains = packages.filter((p) => p.kind === "main");
  const extras = packages.filter((p) => p.kind === "extra");
  const ordered = [...bindings, ...mains, ...extras];

  banner("napi-zig", `${CLI_VERSION}  ·  npm-init`);
  bullet(`Repo        ${c.bold(options.repo)}`);
  bullet(`Workflow    ${c.bold(options.workflow)}`);
  bullet(`Packages    ${c.bold(String(ordered.length))}`);
  blank();

  const scopes = new Set<string>();
  for (const p of ordered) {
    if (p.name.startsWith("@")) {
      const scope = p.name.split("/")[0];
      if (scope) scopes.add(scope);
    }
  }
  for (const s of scopes) await ensureNpmScope(s);

  // check which packages are new
  const checkSpinner = new Spinner(`Checking ${ordered.length} packages on npm`).start();
  const existsResults = await Promise.all(ordered.map((pkg) => packageExistsOnNpm(pkg.name)));
  const newPackages = ordered.filter((_, i) => !existsResults[i]);
  const existingCount = ordered.length - newPackages.length;
  checkSpinner.succeed(
    newPackages.length === 0
      ? `All ${ordered.length} packages already exist on npm`
      : `${c.bold(String(newPackages.length))} new, ${c.gray(existingCount + " already on npm")}`,
  );

  // publish new packages, use stdio "inherit" so npm's
  // interactive auth (OTP / browser-based 2FA) works for the user
  if (newPackages.length > 0) {
    blank();
    plain(
      c.dim(`Publishing initial versions  ${c.gray("(npm prompts pass through for OTP/2FA)")}`),
    );
    blank();
    for (let i = 0; i < newPackages.length; i++) {
      const pkg = newPackages[i]!;
      info(
        `[${i + 1}/${newPackages.length}]  Publishing ${c.bold(pkg.name)}@${c.cyan(pkg.version)}`,
      );
      try {
        await runInherit("npm publish --access public", { cwd: pkg.dir });
      } catch {}
      blank();
    }
  }

  const existingPackages = ordered.filter((_, i) => existsResults[i]);
  let retryExisting: typeof existingPackages = [];
  let unverified = 0;
  if (existingPackages.length > 0) {
    const trustCheck = new Spinner(
      `Checking trusted publishing on ${existingPackages.length} existing packages`,
    ).start();
    const statuses = await Promise.all(existingPackages.map((p) => packageTrustStatus(p.name)));
    retryExisting = existingPackages.filter((_, i) => statuses[i] !== "trusted");
    unverified = statuses.filter((s) => s === "unknown").length;
    if (retryExisting.length === 0) {
      trustCheck.succeed(`All existing packages already have trusted publishing`);
    } else {
      const missing = retryExisting.length - unverified;
      const parts: string[] = [];
      if (missing > 0) parts.push(`${missing} missing`);
      if (unverified > 0) parts.push(`${unverified} unverifiable with 2FA`);
      trustCheck.warn(
        `${c.bold(String(retryExisting.length))} existing ${
          retryExisting.length === 1 ? "package" : "packages"
        } to re-apply  ${c.dim(parts.join(", "))}`,
      );
    }
  }

  const trustNames = new Set([...newPackages, ...retryExisting].map((p) => p.name));
  const trustTargets = ordered.filter((p) => trustNames.has(p.name));

  if (trustTargets.length > 0) {
    requireNpmVersion(11, 16, "trusted publishing");

    blank();
    plain(
      c.dim(`Configuring trusted publishing  ${c.gray("(npm prompts pass through for OTP/2FA)")}`),
    );
    note(`${options.repo} · ${options.workflow}`);
    blank();

    let failures = 0;
    for (let i = 0; i < trustTargets.length; i++) {
      const pkg = trustTargets[i]!;
      info(`[${i + 1}/${trustTargets.length}]  Trusting ${c.bold(pkg.name)}`);
      try {
        await runInherit(
          `npm trust github "${pkg.name}" --file "${options.workflow}" --repo "${options.repo}" --allow-publish --yes`,
        );
      } catch {
        failures++;
        fail(`Trusted publishing failed for ${c.bold(pkg.name)}`);
      }
      blank();

      // rate-limit: 2s between calls to avoid npm throttling
      if (i < trustTargets.length - 1) {
        await sleep(2000);
      }
    }

    if (failures > 0) {
      fail(
        `Trusted publishing failed for ${c.bold(String(failures))} of ${trustTargets.length} ${
          trustTargets.length === 1 ? "package" : "packages"
        }. Re-run init to retry.`,
      );
    } else {
      done(`Trusted publishing configured for ${c.bold(String(trustTargets.length))} packages`);
    }
  }

  blank();
  done(`Done. ${c.dim("CI is now wired to publish on tag pushes.")}`);
}
