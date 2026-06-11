import { execFileSync } from "node:child_process";
import prompts from "prompts";
import { inc, valid, clean, parse } from "semver";
import { discoverPackages, updateVersions } from "./npm";
import { Spinner, banner, blank, bullet, c, done, fail as uiFail, info as uiInfo } from "./ui";
import { CLI_VERSION, runArgs } from "./utils";

type ReleaseType =
  | "major"
  | "premajor"
  | "minor"
  | "preminor"
  | "patch"
  | "prepatch"
  | "prerelease";

const RELEASE_TYPES: readonly string[] = [
  "major",
  "minor",
  "patch",
  "premajor",
  "preminor",
  "prepatch",
  "prerelease",
];

function nextVersion(current: string, release: ReleaseType, preid: string): string {
  const result = inc(current, release, preid);
  if (!result) throw new Error(`Cannot bump ${current} with ${release}`);

  // start pre-release numbering from 1, not 0
  const parsed = parse(result);
  if (
    parsed &&
    parsed.prerelease.length === 2 &&
    parsed.prerelease[0] === preid &&
    String(parsed.prerelease[1]) === "0"
  ) {
    return result.replace(`-${preid}.0`, `-${preid}.1`);
  }

  return result;
}

interface NextVersions {
  major: string;
  minor: string;
  patch: string;
  premajor: string;
  preminor: string;
  prepatch: string;
  prerelease: string;
  next: string;
  conventional: string;
}

function allNextVersions(current: string, preid: string, commits: string[]): NextVersions {
  const parsed = parse(current);
  const isPre = parsed ? parsed.prerelease.length > 0 : false;
  const convType = conventionalBump(commits);

  return {
    major: nextVersion(current, "major", preid),
    minor: nextVersion(current, "minor", preid),
    patch: nextVersion(current, "patch", preid),
    premajor: nextVersion(current, "premajor", preid),
    preminor: nextVersion(current, "preminor", preid),
    prepatch: nextVersion(current, "prepatch", preid),
    prerelease: nextVersion(current, "prerelease", preid),
    next: isPre ? nextVersion(current, "prerelease", preid) : nextVersion(current, "patch", preid),
    conventional: isPre
      ? nextVersion(current, "prerelease", preid)
      : nextVersion(current, convType, preid),
  };
}

function getRecentCommits(): string[] {
  try {
    const lastTag = execFileSync("git", ["describe", "--tags", "--abbrev=0"], {
      encoding: "utf-8",
      stdio: ["pipe", "pipe", "pipe"],
    }).trim();
    return execFileSync("git", ["log", `${lastTag}..HEAD`, "--pretty=%s"], {
      encoding: "utf-8",
    })
      .trim()
      .split("\n")
      .filter(Boolean);
  } catch {
    try {
      return execFileSync("git", ["log", "--pretty=%s", "-20"], { encoding: "utf-8" })
        .trim()
        .split("\n")
        .filter(Boolean);
    } catch {
      return [];
    }
  }
}

function conventionalBump(commits: string[]): ReleaseType {
  let hasMajor = false;
  let hasMinor = false;
  for (const msg of commits) {
    if (msg.includes("!:") || msg.includes("BREAKING CHANGE")) hasMajor = true;
    else if (msg.startsWith("feat")) hasMinor = true;
  }
  return hasMajor ? "major" : hasMinor ? "minor" : "patch";
}

function resolveVersion(
  release: string,
  versions: NextVersions,
  current: string,
  preid: string,
): string {
  switch (release) {
    case "major":
      return versions.major;
    case "minor":
      return versions.minor;
    case "patch":
      return versions.patch;
    case "premajor":
      return versions.premajor;
    case "preminor":
      return versions.preminor;
    case "prepatch":
      return versions.prepatch;
    case "prerelease":
      return versions.prerelease;
    case "next":
      return versions.next;
    case "conventional":
      return versions.conventional;
    case "none":
      return current;
    default:
      return nextVersion(current, release as ReleaseType, preid);
  }
}

export interface BumpOptions {
  release?: string;
  preid?: string;
  commit?: string;
  tag?: boolean;
  push?: boolean;
}

export async function bump(options: BumpOptions): Promise<void> {
  const packages = discoverPackages();
  const reference = packages.find((p) => p.kind === "main") ?? packages[0];
  if (!reference) throw new Error("No npm packages found");

  const currentVersion = reference.version;
  const preid = options.preid ?? "beta";
  let newVersion: string;

  banner("napi-zig", `${CLI_VERSION}  ·  bump`);
  bullet(`Current     ${c.bold(currentVersion)}`);
  bullet(`Packages    ${c.bold(String(packages.length))}`);
  blank();

  if (options.release && valid(options.release)) {
    // explicit version, napi-zig bump 1.2.3
    newVersion = clean(options.release)!;
  } else if (options.release && RELEASE_TYPES.includes(options.release)) {
    // release type, napi-zig bump patch
    newVersion = nextVersion(currentVersion, options.release as ReleaseType, preid);
  } else if (options.release === "next") {
    const parsed = parse(currentVersion);
    const type: ReleaseType = parsed?.prerelease.length ? "prerelease" : "patch";
    newVersion = nextVersion(currentVersion, type, preid);
  } else {
    // interactive picker
    const commits = getRecentCommits();
    const next = allNextVersions(currentVersion, preid, commits);
    const PADDING = 13;
    const bold = (s: string): string => c.bold(s);
    const green = (s: string): string => c.green(s);

    const result = await prompts(
      {
        type: "autocomplete",
        name: "release",
        message: `Current version ${green(currentVersion)}`,
        initial: "next",
        choices: [
          { value: "major", title: `${"major".padStart(PADDING)} ${bold(next.major)}` },
          { value: "minor", title: `${"minor".padStart(PADDING)} ${bold(next.minor)}` },
          { value: "patch", title: `${"patch".padStart(PADDING)} ${bold(next.patch)}` },
          { value: "next", title: `${"next".padStart(PADDING)} ${bold(next.next)}` },
          {
            value: "conventional",
            title: `${"conventional".padStart(PADDING)} ${bold(next.conventional)}`,
          },
          { value: "prepatch", title: `${"pre-patch".padStart(PADDING)} ${bold(next.prepatch)}` },
          { value: "preminor", title: `${"pre-minor".padStart(PADDING)} ${bold(next.preminor)}` },
          { value: "premajor", title: `${"pre-major".padStart(PADDING)} ${bold(next.premajor)}` },
          { value: "none", title: `${"as-is".padStart(PADDING)} ${bold(currentVersion)}` },
          { value: "custom", title: "custom ...".padStart(PADDING + 4) },
        ],
      },
      { onCancel: () => process.exit(1) },
    );

    if (!result.release) process.exit(1);

    if (result.release === "custom") {
      const customResult = await prompts(
        {
          type: "text",
          name: "version",
          message: "Enter the new version number:",
          initial: currentVersion,
          validate: (v: string) => (valid(v) ? true : "That's not a valid version number"),
        },
        { onCancel: () => process.exit(1) },
      );
      if (!customResult.version) process.exit(1);
      newVersion = clean(customResult.version as string)!;
    } else {
      newVersion = resolveVersion(result.release as string, next, currentVersion, preid);
    }
  }

  if (newVersion === currentVersion) {
    blank();
    uiInfo("Version unchanged");
    return;
  }

  blank();
  bullet(`Bumping ${c.bold(currentVersion)} ${c.gray("→")} ${c.green(c.bold(newVersion))}`);
  blank();

  // update all package.json files
  const writeSpinner = new Spinner(`Updating ${packages.length} package.json files`).start();
  updateVersions(packages, newVersion);
  writeSpinner.succeed(
    `Updated ${c.bold(String(packages.length))} packages to ${c.green(c.bold(newVersion))}`,
  );

  const commitMsg = (options.commit ?? "%s").replace(/%s/g, newVersion);
  const doTag = options.tag !== false;
  const doPush = options.push !== false;

  try {
    const commitSpinner = new Spinner("Committing").start();
    execFileSync("git", ["add", "npm/"], { stdio: "pipe" });
    execFileSync("git", ["commit", "-m", commitMsg], { stdio: "pipe" });
    commitSpinner.succeed(`Committed: ${c.dim(commitMsg)}`);

    if (doTag) {
      const tagName = `v${newVersion}`;
      const tagSpinner = new Spinner(`Tagging ${tagName}`).start();
      execFileSync("git", ["tag", "--annotate", "--message", commitMsg, tagName], {
        stdio: "pipe",
      });
      tagSpinner.succeed(`Tagged ${c.bold(tagName)}`);
    }

    if (doPush) {
      const pushSpinner = new Spinner("Pushing to remote").start();
      // --follow-tags pushes the branch and any annotated tags reachable
      // from it in a single round-trip, if no tag was created, it's a
      // no-op for the tag set.
      await runArgs("git", ["push", "--follow-tags"]);
      pushSpinner.succeed("Pushed to remote");
    }
  } catch (e) {
    uiFail(`Git operation failed: ${(e as Error).message}`);
    process.exit(1);
  }

  blank();
  done(`Bumped to ${c.green(c.bold(newVersion))}`);
}
