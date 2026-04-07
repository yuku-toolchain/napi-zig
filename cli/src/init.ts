import { execSync } from "node:child_process"
import ora from "ora"
import { discoverPackages } from "./npm.js"
import { requireNpmVersion } from "./utils.js"

export interface NpmInitOptions {
  repo: string
  workflow: string
}

export function npmInit(options: NpmInitOptions): void {
  const packages = discoverPackages()
  const bindings = packages.filter(p => !p.main)
  const main = packages.find(p => p.main)

  ora().info(`Found ${packages.length} packages to publish\n`)

  // publish bindings first, then main, use stdio "inherit" so npm's
  // interactive auth (OTP / browser-based 2FA) works for the user
  for (const pkg of [...bindings, ...(main ? [main] : [])]) {
    const spinner = ora(`Publishing ${pkg.name}@${pkg.version}...`).start()

    try {
      execSync("npm publish --access public", { cwd: pkg.dir, stdio: "inherit" })
    } catch (error: unknown) {
      const stderr = String((error as { stderr?: Buffer }).stderr ?? "")
      if (
        stderr.includes("previously published") ||
        stderr.includes("cannot publish over") ||
        stderr.includes("EPUBLISHCONFLICT")
      ) {
        spinner.info(`${pkg.name}@${pkg.version} already exists, skipping`)
      } else {
        spinner.fail(`Failed to publish ${pkg.name}`)
        console.error(stderr)
        process.exit(1)
      }
    }
    console.log()
  }

  // configure trusted publishing
  requireNpmVersion(11, 10, "trusted publishing")
  ora().info(`Configuring trusted publishing for ${options.repo} / ${options.workflow}`)

  for (let i = 0; i < packages.length; i++) {
    const pkg = packages[i]!
    const spinner = ora(`[${i + 1}/${packages.length}] ${pkg.name}...`).start()

    try {
      execSync(
        `npm trust github "${pkg.name}" --file "${options.workflow}" --repo "${options.repo}" --yes`,
        { stdio: "pipe" },
      )
      spinner.succeed(`[${i + 1}/${packages.length}] ${pkg.name}`)
    } catch (error: unknown) {
      const stderr = String((error as { stderr?: Buffer }).stderr ?? "")
      spinner.fail(`[${i + 1}/${packages.length}] ${pkg.name}: ${stderr.split("\n")[0]}`)
    }

    // rate-limit: 2s between calls to avoid npm throttling
    if (i < packages.length - 1) {
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2000)
    }
  }

  console.log()
  ora().succeed("All packages published and trusted publishing configured.")
}
