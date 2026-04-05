#!/usr/bin/env node

const { execSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const args = process.argv.slice(2);
const command = args[0];

if (!command || command === "help" || command === "--help") {
  console.log(`napi-zig: build native Node.js addons with Zig

commands:
  build             build .node for current platform (dev)
  build --release   cross-compile all platforms and sync npm folder

options:
  --optimize <mode> optimization level: debug, safe, fast, small
                    (default: debug for build, fast for --release)
`);
  process.exit(0);
}

if (command === "build") {
  const isRelease = args.includes("--release");
  const optIdx = args.indexOf("--optimize");
  const optimize = optIdx !== -1 ? args[optIdx + 1] : null;

  if (isRelease) {
    buildRelease(optimize);
  } else {
    buildDev(optimize);
  }
} else {
  console.error(`unknown command: ${command}`);
  process.exit(1);
}

function buildDev(optimize) {
  const optFlag = optimize ? ` --release=${optimize}` : "";
  console.log("building for current platform...");
  run(`zig build${optFlag}`);

  // find .node files in zig-out/lib/ and create [name].js loaders
  const libDir = path.join(process.cwd(), "zig-out", "lib");
  if (fs.existsSync(libDir)) {
    for (const file of fs.readdirSync(libDir)) {
      if (file.endsWith(".node")) {
        const name = file.replace(".node", "");
        const loaderPath = path.join(process.cwd(), `${name}.js`);
        if (!fs.existsSync(loaderPath)) {
          fs.writeFileSync(
            loaderPath,
            `module.exports = require('./zig-out/lib/${file}');\n`
          );
          console.log(`created ${name}.js`);
        }
        // copy .d.ts if available
        const dtsSource = path.join(libDir, `${name}.d.ts`);
        if (fs.existsSync(dtsSource)) {
          const dtsDest = path.join(process.cwd(), `${name}.d.ts`);
          fs.copyFileSync(dtsSource, dtsDest);
          console.log(`copied ${name}.d.ts`);
        }
      }
    }
  }

  console.log("done.");
}

function buildRelease(optimize) {
  const optFlag = optimize ? ` --release=${optimize}` : "";
  console.log("cross-compiling for all platforms...");
  run(`zig build -Dnpm=true${optFlag}`);

  // sync from zig-out/npm/ to project npm/
  const srcBase = path.join(process.cwd(), "zig-out", "npm");
  const destBase = path.join(process.cwd(), "npm");

  if (!fs.existsSync(srcBase)) {
    console.error("no npm output found in zig-out/npm/. make sure your build.zig uses addLib with .npm config.");
    process.exit(1);
  }

  for (const pkgName of fs.readdirSync(srcBase)) {
    const srcPkg = path.join(srcBase, pkgName);
    const destPkg = path.join(destBase, pkgName);

    if (!fs.statSync(srcPkg).isDirectory()) continue;

    const firstRun = !fs.existsSync(destPkg);

    if (firstRun) {
      // first run: copy entire scaffold
      copyDir(srcPkg, destPkg);
      console.log(`created npm/${pkgName}/`);
    } else {
      // subsequent runs: only update .node files and binding.js
      syncBuildOutputs(srcPkg, destPkg);
      // always update binding.js (platforms might change)
      const srcBinding = path.join(srcPkg, "binding.js");
      const destBinding = path.join(destPkg, "binding.js");
      if (fs.existsSync(srcBinding)) {
        fs.copyFileSync(srcBinding, destBinding);
      }
      console.log(`updated .node binaries in npm/${pkgName}/`);
    }
  }

  console.log("done.");
}

function syncBuildOutputs(src, dest) {
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);

    if (entry.isDirectory()) {
      if (!fs.existsSync(destPath)) fs.mkdirSync(destPath, { recursive: true });
      syncBuildOutputs(srcPath, destPath);
    } else if (entry.name.endsWith(".node") || entry.name.endsWith(".d.ts")) {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function copyDir(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDir(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function run(cmd) {
  try {
    execSync(cmd, { stdio: "inherit", cwd: process.cwd() });
  } catch {
    process.exit(1);
  }
}
