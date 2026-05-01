// verifies that a cross-compiled napi-zig package, dropped onto disk
// the way `npm install` would lay it out, actually loads under the host
// OS and runtime. Argv: path to the package root (the dir holding
// index.js + binding.js + <scope>/binding-<suffix>/<name>.node).

import { resolve, join } from "node:path";
import { pathToFileURL } from "node:url";
import assert from "node:assert/strict";

const pkgDir = resolve(process.argv[2] ?? ".");
const indexUrl = pathToFileURL(join(pkgDir, "index.js")).href;

const m = (await import(indexUrl)).default;

assert.equal(m.add(2, 3), 5);
assert.equal(m.add(-10, 7), -3);

const platform = `${process.platform}-${process.arch}`;
console.log(`installed smoke OK on ${platform} (loaded ${pkgDir})`);
