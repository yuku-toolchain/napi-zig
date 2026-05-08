// Smoke test for the wasm fixture. Builds via `napi-zig.addLib`, then loads
// the generated index.js (which falls back to wasm because no native binding
// matches the host suffix in zig-out/npm).
import { strict as assert } from "node:assert";

const mod = (await import("./zig-out/npm/wasmtest/index.js")).default;

// synchronous primitives
assert.equal(mod.add(2, 3), 5);
assert.equal(mod.greet("zig"), "hello, zig");
assert.equal(mod.sumSlice([1, 2, 3, 4]), 10);
assert.equal(mod.version, "wasm-fixture-1");

// promises: resolve synchronously through napi_create_promise
assert.equal(await mod.promiseAdd(7, 8), 15);

// async work: emnapi runs `compute` on its work pool, then `resolve` on the
// js side. proves napi_create_async_work + napi_queue_async_work both work.
assert.equal(await mod.asyncFib(10), 55);

// threadsafe fn from the same thread. cross-thread calls would need
// std.Thread, which wasm32-wasi (single-threaded) does not provide.
let ticked = 0;
mod.signalOnce(() => {
  ticked += 1;
});
// emnapi defers the tsfn dispatch to a macrotask, so yield twice
await new Promise((r) => setImmediate(r));
await new Promise((r) => setImmediate(r));
assert.equal(ticked, 1);

console.log("wasm fixture: ok");
