import { execSync } from "node:child_process"
import ora from "ora"
import { discoverPackages } from "./npm.js"
import { packageExistsOnNpm, requireNpmVersion } from "./utils.js"

export interface NpmInitOptions {
  repo: string
  workflow: string
}

export function npmInit(options: NpmInitOptions): void {
  const packages = discoverPackages()
  const bindings = packages.filter(p => !p.main)
  const main = packages.find(p => p.main)
  const ordered = [...bindings, ...(main ? [main] : [])]

  // check which packages are new
  const checkSpinner = ora("Checking which packages need publishing...").start()
  const newPackages = ordered.filter(pkg => !packageExistsOnNpm(pkg.name))
  const existingCount = ordered.length - newPackages.length
  checkSpinner.succeed(
    newPackages.length === 0
      ? `All ${ordered.length} packages already exist on npm`
      : `${newPackages.length} new, ${existingCount} already on npm`,
  )

  // publish new packages, use stdio "inherit" so npm's
  // interactive auth (OTP / browser-based 2FA) works for the user
  if (newPackages.length > 0) {
    console.log()
    for (const pkg of newPackages) {
      ora().info(`Publishing ${pkg.name}@${pkg.version}...`)
      try {
        execSync("npm publish --access public", { cwd: pkg.dir, stdio: "inherit" })
      } catch {}
      console.log()
    }
  }

  // configure trusted publishing for new packages only
  if (newPackages.length > 0) {
    requireNpmVersion(11, 10, "trusted publishing")
    ora().info(`Configuring trusted publishing for ${newPackages.length} new packages`)

    for (let i = 0; i < newPackages.length; i++) {
      const pkg = newPackages[i]!
      const spinner = ora(`[${i + 1}/${newPackages.length}] ${pkg.name}...`).start()

      try {
        execSync(
          `npm trust github "${pkg.name}" --file "${options.workflow}" --repo "${options.repo}" --yes`,
          { stdio: "pipe" },
        )
        spinner.succeed(`[${i + 1}/${newPackages.length}] ${pkg.name}`)
      } catch (error: unknown) {
        const stderr = String((error as { stderr?: Buffer }).stderr ?? "")
        spinner.fail(`[${i + 1}/${newPackages.length}] ${pkg.name}: ${stderr.split("\n")[0]}`)
      }

      // rate-limit: 2s between calls to avoid npm throttling
      if (i < newPackages.length - 1) {
        Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 2000)
      }
    }
  }

  console.log()
  ora().succeed("Done.")
}
