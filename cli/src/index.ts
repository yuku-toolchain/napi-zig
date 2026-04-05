#!/usr/bin/env node

import cac from "cac"
import { buildDev, buildRelease } from "./build.js"
import { version } from "../package.json"

const cli = cac("napi-zig")

cli
  .command("build", "Build for current platform")
  .option("--release", "Cross-compile all platforms and sync npm folder")
  .option("--optimize <mode>", "Optimization: debug, safe, fast, small (default: debug, fast with --release)")
  .action((options: { release?: boolean; optimize?: string }) => {
    if (options.release) {
      buildRelease(options.optimize ?? "fast")
    } else {
      buildDev(options.optimize ?? "debug")
    }
  })

cli.help()
cli.version(version)
cli.usage("Build native Node.js addons with Zig")

cli.parse()
