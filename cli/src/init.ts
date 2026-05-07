import { discoverPackages } from "./npm";
import {
  Spinner,
  TaskList,
  banner,
  blank,
  bullet,
  c,
  done,
  info,
  plain,
} from "./ui";
import {
  CLI_VERSION,
  ensureNpmScope,
  packageExistsOnNpm,
  requireNpmVersion,
  run,
  runInherit,
  sleep,
} from "./utils";

export interface NpmInitOptions {
  repo: string;
  workflow: string;
}

export async function npmInit(options: NpmInitOptions): Promise<void> {
  const packages = discoverPackages();
  const bindings = packages.filter((p) => !p.main);
  const mains = packages.filter((p) => p.main);
  const ordered = [...bindings, ...mains];

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
    plain(c.dim(`Publishing initial versions  ${c.gray("(npm prompts pass through for OTP/2FA)")}`));
    blank();
    for (let i = 0; i < newPackages.length; i++) {
      const pkg = newPackages[i]!;
      info(`[${i + 1}/${newPackages.length}]  Publishing ${c.bold(pkg.name)}@${c.cyan(pkg.version)}`);
      try {
        await runInherit("npm publish --access public", { cwd: pkg.dir });
      } catch {}
      blank();
    }
  }

  // configure trusted publishing for new packages only
  if (newPackages.length > 0) {
    requireNpmVersion(11, 10, "trusted publishing");

    const trustList = new TaskList(
      `Configuring trusted publishing`,
      newPackages.map((p) => ({ id: p.name, label: p.name })),
      { columns: 1, hint: c.dim(`${options.repo} · ${options.workflow}`) },
    ).start();

    let firstError: string | undefined;

    for (let i = 0; i < newPackages.length; i++) {
      const pkg = newPackages[i]!;
      trustList.setState(pkg.name, "active");

      try {
        await run(
          `npm trust github "${pkg.name}" --file "${options.workflow}" --repo "${options.repo}" --yes`,
        );
        trustList.setState(pkg.name, "ok");
      } catch (error: unknown) {
        const stderr = String((error as { stderr?: string }).stderr ?? "");
        const firstLine = stderr.split("\n")[0] ?? "trust failed";
        trustList.setState(pkg.name, "fail", c.red(firstLine));
        firstError = firstError ?? firstLine;
      }

      // rate-limit: 2s between calls to avoid npm throttling
      if (i < newPackages.length - 1) {
        await sleep(2000);
      }
    }

    trustList.finish(
      !firstError,
      firstError
        ? `Trusted publishing failed`
        : `Trusted publishing configured for ${c.bold(String(newPackages.length))} packages`,
    );
  }

  blank();
  done(`Done. ${c.dim("CI is now wired to publish on tag pushes.")}`);
}
