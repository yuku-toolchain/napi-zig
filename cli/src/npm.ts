import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { join } from "node:path";

export type NpmPackageKind = "main" | "binding" | "extra";

export interface NpmPackage {
  name: string;
  version: string;
  dir: string;
  kind: NpmPackageKind;
}

export function isExtraPackageDir(dir: string): boolean {
  const pkgJsonPath = join(dir, "package.json");
  if (!existsSync(pkgJsonPath)) return false;
  let pkg: { name?: unknown; optionalDependencies?: unknown };
  try {
    pkg = JSON.parse(readFileSync(pkgJsonPath, "utf-8")) as typeof pkg;
  } catch {
    return false;
  }
  if (typeof pkg.name !== "string" || pkg.name.length === 0) return false;
  return !pkg.optionalDependencies;
}

export function discoverPackages(): NpmPackage[] {
  const npmDir = join(process.cwd(), "npm");
  if (!existsSync(npmDir)) {
    throw new Error("npm/ directory not found. Run 'napi build --release' first.");
  }

  const packages: NpmPackage[] = [];

  for (const entry of readdirSync(npmDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const dir = join(npmDir, entry.name);
    const pkgJsonPath = join(dir, "package.json");
    if (!existsSync(pkgJsonPath)) continue;

    const pkg = JSON.parse(readFileSync(pkgJsonPath, "utf-8")) as {
      name?: string;
      version?: string;
      optionalDependencies?: Record<string, string>;
    };
    if (typeof pkg.name !== "string" || pkg.name.length === 0) continue;
    const version = pkg.version ?? "0.0.0";

    if (!pkg.optionalDependencies) {
      packages.push({ name: pkg.name, version, dir, kind: "extra" });
      continue;
    }

    // main package (has optionalDependencies)
    packages.push({ name: pkg.name, version, dir, kind: "main" });

    // binding packages from optionalDependencies
    for (const depName of Object.keys(pkg.optionalDependencies)) {
      const [scope, bindingName] = depName.split("/");
      if (!scope || !bindingName) continue;
      const bindingDir = join(dir, scope, bindingName);
      if (!existsSync(join(bindingDir, "package.json"))) continue;
      const bindingPkg = JSON.parse(readFileSync(join(bindingDir, "package.json"), "utf-8")) as {
        name: string;
        version: string;
      };
      packages.push({
        name: bindingPkg.name,
        version: bindingPkg.version,
        dir: bindingDir,
        kind: "binding",
      });
    }
  }

  if (packages.length === 0) {
    throw new Error("No npm packages found. Run 'napi build --release' first.");
  }

  return packages;
}

export function updateVersions(packages: NpmPackage[], version: string): void {
  for (const pkg of packages) {
    const jsonPath = join(pkg.dir, "package.json");
    const json = JSON.parse(readFileSync(jsonPath, "utf-8")) as Record<string, unknown>;
    json["version"] = version;
    if (
      pkg.kind === "main" &&
      typeof json["optionalDependencies"] === "object" &&
      json["optionalDependencies"] !== null
    ) {
      const deps = json["optionalDependencies"] as Record<string, string>;
      for (const key of Object.keys(deps)) {
        deps[key] = version;
      }
    }
    writeFileSync(jsonPath, JSON.stringify(json, null, 2) + "\n");
  }
}
