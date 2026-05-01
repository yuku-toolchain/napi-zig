// verifies that a cross-compiled package, laid out the way npm install
// would lay it out, loads correctly on the host. argv[2]: package root.

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
