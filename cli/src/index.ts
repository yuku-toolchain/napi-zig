#!/usr/bin/env node

import cac from "cac";
import { buildDev, buildRelease } from "./build";
import { bump } from "./bump";
import { publish } from "./publish";
import { npmInit } from "./init";
import { CLI_VERSION } from "./utils";

const cli = cac("napi-zig");

cli
  .command("build", "Build for current platform")
  .option("--release", "Cross-compile all platforms and sync npm folder")
  .option("--optimize <mode>", "Optimization: safe, fast, small (default: fast with --release)")
  .action((options: { release?: boolean; optimize?: string }) => {
    if (options.release) {
      return buildRelease(options.optimize ?? "fast");
    } else {
      return buildDev(options.optimize);
    }
  });

cli
  .command("bump [version]", "Bump version across all npm packages")
  .option("--preid <id>", "Pre-release identifier (default: beta)")
  .option("--commit <message>", "Commit message, use %s for version (default: %s)")
  .option("--no-tag", "Skip creating a git tag")
  .option("--no-push", "Skip pushing to remote")
  .action(
    (
      release: string | undefined,
      options: { preid?: string; commit?: string; tag?: boolean; push?: boolean },
    ) => {
      return bump({ release, ...options });
    },
  );

cli
  .command("publish", "Publish all packages to npm")
  .option("--provenance", "Generate provenance (default: auto in CI)")
  .option("--no-provenance", "Skip provenance generation")
  .action((options: { provenance?: boolean }) => {
    return publish(options);
  });

cli
  .command("npm-init", "Publish initial versions and configure trusted publishing")
  .option("--repo <repo>", "GitHub repository (owner/repo)")
  .option("--workflow <file>", "GitHub Actions workflow filename")
  .action((options: { repo?: string; workflow?: string }) => {
    if (!options.repo || !options.workflow) {
      console.error("Error: --repo and --workflow are required");
      console.error("Example: napi npm-init --repo myorg/myrepo --workflow publish.yml");
      process.exit(1);
    }
    return npmInit({ repo: options.repo, workflow: options.workflow });
  });

cli.help();
cli.version(CLI_VERSION);
cli.usage("Build native Node.js addons with Zig");

cli.parse();
