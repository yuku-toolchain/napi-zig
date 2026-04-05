import { execSync } from "node:child_process"
import { existsSync, readdirSync, statSync, mkdirSync, copyFileSync, writeFileSync } from "node:fs"
import { join } from "node:path"
import ora from "ora"

export function buildDev(optimize: string | undefined) {
  const optFlag = optimize ? ` --release=${optimize}` : ""

  const spinner = ora("Building for current platform...").start()
  run(`zig build${optFlag}`)
  spinner.succeed("Build complete")

  const libDir = join(process.cwd(), "zig-out", "lib")
  if (!existsSync(libDir)) return

  for (const file of readdirSync(libDir)) {
    if (!file.endsWith(".node")) continue

    const name = file.replace(".node", "")
    const loaderPath = join(process.cwd(), `${name}.js`)

    if (!existsSync(loaderPath)) {
      writeFileSync(loaderPath, `module.exports = require('./zig-out/lib/${file}');\n`)
      ora().info(`Created ${name}.js`)
    }

    const dtsSource = join(libDir, `${name}.d.ts`)
    if (existsSync(dtsSource)) {
      copyFileSync(dtsSource, join(process.cwd(), `${name}.d.ts`))
      ora().info(`Copied ${name}.d.ts`)
    }
  }
}

export function buildRelease(optimize: string) {
  const optFlag = ` --release=${optimize}`

  const spinner = ora("Cross-compiling for all platforms...").start()
  run(`zig build -Dnpm=true${optFlag}`)
  spinner.succeed("Cross-compilation complete")

  const srcBase = join(process.cwd(), "zig-out", "npm")
  const destBase = join(process.cwd(), "npm")

  if (!existsSync(srcBase)) {
    ora().fail("No npm output found in zig-out/npm/. Make sure your build.zig uses addLib with .npm config.")
    process.exit(1)
  }

  const syncSpinner = ora("Syncing npm packages...").start()

  for (const pkgName of readdirSync(srcBase)) {
    const srcPkg = join(srcBase, pkgName)
    const destPkg = join(destBase, pkgName)

    if (!statSync(srcPkg).isDirectory()) continue

    if (!existsSync(destPkg)) {
      copyDir(srcPkg, destPkg)
      syncSpinner.text = `Created npm/${pkgName}/`
    } else {
      syncBuildOutputs(srcPkg, destPkg)
      const srcBinding = join(srcPkg, "binding.js")
      const destBinding = join(destPkg, "binding.js")
      if (existsSync(srcBinding)) {
        copyFileSync(srcBinding, destBinding)
      }
      syncSpinner.text = `Updated .node binaries in npm/${pkgName}/`
    }
  }

  syncSpinner.succeed("npm packages synced")
}

function syncBuildOutputs(src: string, dest: string) {
  for (const entry of readdirSync(src, { withFileTypes: true })) {
    const srcPath = join(src, entry.name)
    const destPath = join(dest, entry.name)

    if (entry.isDirectory()) {
      if (!existsSync(destPath)) mkdirSync(destPath, { recursive: true })
      syncBuildOutputs(srcPath, destPath)
    } else if (entry.name.endsWith(".node") || entry.name.endsWith(".d.ts")) {
      copyFileSync(srcPath, destPath)
    }
  }
}

function copyDir(src: string, dest: string) {
  mkdirSync(dest, { recursive: true })
  for (const entry of readdirSync(src, { withFileTypes: true })) {
    const srcPath = join(src, entry.name)
    const destPath = join(dest, entry.name)
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath)
    } else {
      copyFileSync(srcPath, destPath)
    }
  }
}

function run(cmd: string) {
  try {
    execSync(cmd, { stdio: "inherit", cwd: process.cwd() })
  } catch {
    process.exit(1)
  }
}
