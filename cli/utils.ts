import { execSync } from "node:child_process"
import ora from "ora"

export function packageExistsOnNpm(name: string): boolean {
  try {
    execSync(`npm view "${name}" version`, { stdio: "pipe" })
    return true
  } catch {
    return false
  }
}

export function requireNpmVersion(minMajor: number, minMinor: number, feature: string): void {
  try {
    const version = execSync("npm --version", { encoding: "utf-8" }).trim()
    const parts = version.split(".")
    const major = Number(parts[0])
    const minor = Number(parts[1])
    if (major < minMajor || (major === minMajor && minor < minMinor)) {
      ora().fail(`npm ${version} found, but ${feature} requires npm >= ${minMajor}.${minMinor}.0`)
      ora().info("Run: npm install -g npm@latest")
      process.exit(1)
    }
  } catch {
    ora().fail("Could not detect npm version. Is npm installed?")
    process.exit(1)
  }
}
