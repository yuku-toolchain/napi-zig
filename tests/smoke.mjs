import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { createRequire } from "node:module";
import assert from "node:assert/strict";

const here = dirname(fileURLToPath(import.meta.url));
const fixtureDir = join(here, "fixture-lib");

const built = spawnSync("zig", ["build"], {
  cwd: fixtureDir,
  stdio: "inherit",
});
if (built.status !== 0) {
  console.error("zig build failed");
  process.exit(built.status ?? 1);
}

const require = createRequire(import.meta.url);
const m = require(join(fixtureDir, "zig-out", "lib", "fixture.node"));

// primitives
assert.equal(m.roundtripBool(true), true);
assert.equal(m.roundtripBool(false), false);
assert.equal(m.roundtripI32(-42), -42);
assert.equal(m.roundtripU32(2 ** 32 - 1), 2 ** 32 - 1);
assert.equal(m.roundtripF64(Math.PI), Math.PI);
assert.equal(m.roundtripI64(123n), 123n);
assert.equal(m.roundtripU64(0n), 0n);

// strings
assert.equal(m.roundtripString("hello world"), "hello world");
assert.equal(m.roundtripString("世界 🦀"), "世界 🦀");
assert.equal(m.stringByteLength("世界"), 6);

// optional / null
assert.equal(m.returnsNull(), null);
assert.equal(m.roundtripOptionalI32(null), null);
assert.equal(m.roundtripOptionalI32(7), 7);

// struct
assert.equal(m.formatOptions({ filePath: "x", lineCount: 5 }), "x:5:false");
assert.equal(m.formatOptions({ filePath: "x", lineCount: 5, verbose: true }), "x:5:true");

// enum (camelCase round-trip)
assert.equal(m.roundtripLevel("errorLevel"), "errorLevel");

// errors
assert.throws(() => m.divideF64(1, 0), /DivisionByZero/);
assert.throws(() => m.roundtripI8(200), RangeError);
assert.throws(() => m.roundtripBool("not a bool"), TypeError);

// classes
const c = new m.Counter(0);
c.increment();
c.addN(5);
assert.equal(c.get(), 6);
c.reset();
assert.equal(c.get(), 0);

// callbacks
const seen = [];
m.forEach([10, 20, 30], (v, i) => seen.push([i, v]));
assert.deepEqual(seen, [
  [0, 10],
  [1, 20],
  [2, 30],
]);

// buffers
const buf = m.createFilledBuffer(4, 0xab);
assert.equal(Buffer.isBuffer(buf), true);
assert.deepEqual([...buf], [0xab, 0xab, 0xab, 0xab]);

// async / promises
assert.equal(await m.asyncFib(10), 55);
assert.equal(await m.asyncVoid(), undefined);
assert.equal(await m.asyncString(), "from worker");
await assert.rejects(m.asyncError(), /WorkerFailed/);

// sync promise
assert.equal(await m.resolveImmediately(7), 7);
await assert.rejects(m.rejectImmediately("boom"), /boom/);

const runtime =
  typeof globalThis.Deno !== "undefined"
    ? `deno ${globalThis.Deno.version.deno}`
    : `node ${process.version}`;
console.log(`smoke OK on ${runtime}`);
