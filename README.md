# napi-zig

Write [Node.js native addons](https://nodejs.org/api/n-api.html) in idiomatic Zig. Cross-compile for every platform from one machine. Publish to npm with one command.

```zig
const napi = @import("napi-zig");

comptime { napi.module(@This()); }

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```js
import addon from "./my-addon.js";
addon.add(2, 3); // 5
```

## Table of contents

- [Getting started](#getting-started)
- [Project setup](#project-setup)
- [Writing functions](#writing-functions)
- [Classes](#classes)
- [Type conversion](#type-conversion)
- [TypeScript declarations](#typescript-declarations)
- [Memory model](#memory-model)
- [Errors](#errors)
- [Callbacks](#callbacks)
- [Async](#async)
- [Release & publishing](#release--publishing)
- [API reference](#api-reference)

## Getting started

### Quickstart, scaffold a new project

```sh
npx napi-zig@latest new my-addon
```

Prompts for the package manager (detected by default), wires up `build.zig`, `build.zig.zon`, `package.json`, a starter `src/lib.zig`, a `.github/workflows/publish.yml`, runs the install, fetches the Zig dependency, and produces an initial build:

```sh
cd my-addon
node test.mjs    # add(2, 3) = 5
                 # greet('world') = Hello, world!
```

From here, edit `src/lib.zig` and rerun `napi build`. When you're ready to ship, see [Release & publishing](#release--publishing).

### 1. Add napi-zig

If you'd rather wire it up by hand:

```sh
zig fetch --save git+https://github.com/yuku-toolchain/napi-zig.git/#HEAD
npm install -D napi-zig
```

### 2. Write your addon

```zig
// src/lib.zig
const std = @import("std");
const napi = @import("napi-zig");

comptime { napi.module(@This()); }

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn greet(env: napi.Env, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "Hello, {s}!", .{name});
}
```

`napi.module(@This())` walks every public declaration of your module:

- `pub fn` becomes a JS function
- `pub const` (with a JS-mappable value) becomes a JS property
- `pub const x = struct { pub fn ... }` becomes a nested JS namespace

snake_case names are translated to camelCase automatically.

### 3. Configure `build.zig`

```zig
const std = @import("std");
const napi_zig = @import("napi_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    napi_zig.addLib(b, b.dependency("napi_zig", .{}), .{
        .name = "my-addon",
        .root = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .npm = .{
            .scope = "@myscope",
            .repository = .{ .url = "https://github.com/myorg/myrepo" },
        },
    });
}
```

### 4. Build and use

```sh
napi build
```

```js
import addon from "./my-addon.js";
console.log(addon.add(2, 3)); // 5
console.log(addon.greet("world")); // Hello, world!
```

That's the whole loop.

## Project setup

### `addLib` options

| Option      | Required | Description                                                           |
| ----------- | -------- | --------------------------------------------------------------------- |
| `.name`     | Yes      | Package name (used for the `.node` binary and npm package)            |
| `.root`     | Yes      | Path to the root Zig source file                                      |
| `.target`   | Yes      | Build target                                                          |
| `.optimize` | Yes      | Optimization mode                                                     |
| `.imports`  | No       | Additional Zig module imports                                         |
| `.npm`      | No       | npm package config (required for cross-compile + publish)             |
| `.host_exe` | No       | Windows host binary (default `"node.exe"`, use `"electron.exe"` etc.) |

### Importing other Zig modules

```zig
const parser = b.addModule("parser", .{
    .root_source_file = b.path("src/parser/root.zig"),
    .target = target,
    .optimize = optimize,
});

napi_zig.addLib(b, napi_dep, .{
    .name = "my-addon",
    .root = b.path("src/lib.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{ .{ .name = "parser", .module = parser } },
    .npm = .{ ... },
});
```

Then in your addon: `const parser = @import("parser");`

### `.npm` options

| Option         | Default             | Description                                                                           |
| -------------- | ------------------- | ------------------------------------------------------------------------------------- |
| `.scope`       | required            | npm scope (e.g. `"@myscope"`)                                                         |
| `.repository`  | required            | `.url` required, `.type` defaults to `"git"`                                          |
| `.description` | `""`                | Package description                                                                   |
| `.license`     | `"MIT"`             | License identifier                                                                    |
| `.dts`         | `.none`             | `.{ .file = path }`, `.auto`, or `.none` (see [TypeScript](#typescript-declarations)) |
| `.platforms`   | `Platform.defaults` | Cross-compilation targets                                                             |

Default platforms: Linux (x64, arm64, arm; glibc and musl), macOS (x64, arm64), Windows (x64, arm64), FreeBSD (x64).

## Writing functions

There is **one rule** for what makes a JS-visible function:

```
pub fn name([env: napi.Env,] [info: napi.CallInfo,] ...js_args) Return
```

`Env` and `CallInfo` are recognized by type and injected automatically, they don't consume JS arguments. Everything else is converted from the JS arguments at the call site, and the return value is converted back. The progression:

```zig
// no env needed
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

// env needed (allocate, build values, throw, call back into JS)
pub fn greet(env: napi.Env, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "Hello, {s}!", .{name});
}

// raw call info, for variadic or dynamic-arity functions
pub fn sum(env: napi.Env, info: napi.CallInfo) !napi.Val {
    const args = try info.args(env, 16);
    const argc = try info.argCount(env);
    var total: f64 = 0;
    for (0..argc) |i| total += try args[i].to(env, f64);
    return env.toJs(total);
}
```

For values the converter can't auto-build (Buffers, dynamic-key objects), return `!napi.Val` and construct it yourself:

```zig
pub fn makeBuffer(env: napi.Env, size: u32) !napi.Val {
    const buf = try env.createBuffer(size);
    @memset(buf.data, 0xff);
    return buf.val;
}

pub fn getInfo(env: napi.Env) !napi.Val {
    const obj = try env.createObject();
    try obj.setNamedProperty(env, "name", try env.toJs("napi-zig"));
    try obj.setNamedProperty(env, "version", try env.toJs(1));
    return obj;
}
```

### Nested namespaces

Group related exports under a struct:

```zig
pub const crypto = struct {
    pub fn hash(data: []const u8) [32]u8 { ... }
    pub fn verify(sig: []const u8, data: []const u8) bool { ... }
};
```

```js
addon.crypto.hash(buf);
addon.crypto.verify(sig, buf);
```

Namespaces nest arbitrarily.

## Classes

Wrap a Zig struct as a JS class with `napi.class`:

```zig
pub const Counter = napi.class("Counter", struct {
    value: i32,

    pub fn init(start: i32) @This() {
        return .{ .value = start };
    }

    pub fn increment(self: *@This()) i32 {
        self.value += 1;
        return self.value;
    }

    pub fn get(self: *const @This()) i32 {
        return self.value;
    }

    pub fn deinit(self: *@This()) void {
        // optional, runs when the JS instance is garbage-collected
        _ = self;
    }
});
```

```js
const c = new Counter(10);
c.increment(); // 11
c.increment(); // 12
c.get(); // 12
```

Rules:

- **`init`** is the constructor. It returns `T` or `!T`. May take `Env` as its first parameter (injected, doesn't consume a JS arg).
- Every other `pub fn` whose first parameter is `*Self` or `*const Self` becomes a method. May also take `Env` as its second parameter.
- **`deinit`** (optional, signature `fn(self: *Self) void`) runs when the JS instance is GC'd. The Zig allocation is freed automatically either way.

The instance is heap-allocated once and reused across every method call, no per-call boxing.

## Type conversion

### Zig → JS (`env.toJs`)

| Zig type                         | JS result                              |
| -------------------------------- | -------------------------------------- |
| `void`                           | `undefined`                            |
| `bool`                           | Boolean                                |
| `?T`                             | inner value or `null`                  |
| `comptime_int`, `comptime_float` | Number                                 |
| `i1`..`i32`, `u1`..`u32`         | Number                                 |
| `i33`..`i53`, `u33`..`u53`       | Number (via f64, safe-integer range)   |
| `i54`..`i64`, `u54`..`u64`       | BigInt                                 |
| `f16`, `f32`, `f64`              | Number                                 |
| `[]const u8`, `*const [N:0]u8`   | String                                 |
| `[N]T`, `[]T`                    | Array                                  |
| `struct { S, T }` (tuple)        | Array                                  |
| `enum`                           | String (tag name, snake → camel)       |
| `struct { foo, bar }`            | Object (snake_case fields → camelCase) |
| `Val`                            | passthrough                            |
| Type with `pub fn toJs`          | custom (see below)                     |

### JS → Zig (`val.to(env, T)`)

| JS type          | Zig type                   | Notes                                        |
| ---------------- | -------------------------- | -------------------------------------------- |
| Boolean          | `bool`                     |                                              |
| Number           | `i1`..`i32`, `u1`..`u32`   |                                              |
| Number           | `i33`..`i53`, `u33`..`u53` | via i64/f64                                  |
| Number           | `f16`, `f32`, `f64`        |                                              |
| BigInt           | `i54`..`i64`, `u54`..`u64` |                                              |
| null / undefined | `?T` returns `null`        |                                              |
| String           | `[]const u8`               | allocated on `env.allocator()`               |
| String           | `enum`                     | accepts camelCase or snake_case              |
| Array            | `[N]T`, `[]T`              | by-index conversion                          |
| Array            | `struct { S, T }` (tuple)  | by-index conversion                          |
| Object           | `struct`                   | camelCase field matching, defaults respected |
| Function         | `Callback`                 | validated, throws TypeError if not callable  |
| any              | `Val`                      | passthrough                                  |
| any              | Type with `pub fn fromJs`  | custom (see below)                           |

Type mismatches throw `TypeError` with the actual JS type:

```
TypeError: expected number, got string
TypeError: invalid enum value for Level: 'foo'
```

### Structs and enums

Struct fields are matched by camelCase name. Default values are used for missing properties:

```zig
const Options = struct {
    file_path: []const u8,
    line_count: i32,
    verbose: bool = false,
};

pub fn compile(opts: Options) !void { ... }
```

```js
compile({ filePath: "main.zig", lineCount: 100 });
// verbose defaults to false
```

Enums map to/from strings:

```js
log("warning", "disk almost full");
log("errorLevel", "out of memory"); // camelCase also works
log("invalid", "..."); // TypeError: invalid enum value
```

### Custom conversion (e.g. unions)

Add `toJs` and/or `fromJs` methods. They take priority over the default field-by-field walk.

```zig
const Color = union(enum) {
    rgb: struct { r: u8, g: u8, b: u8 },
    hex: []const u8,

    pub fn toJs(self: Color, env: napi.Env) !napi.Val {
        return switch (self) {
            .rgb => |c| env.toJs(c),
            .hex => |s| env.toJs(s),
        };
    }

    pub fn fromJs(env: napi.Env, val: napi.Val) !Color {
        if ((try val.typeOf(env)) == .string) {
            return .{ .hex = try val.to(env, []const u8) };
        }
        return .{ .rgb = try val.to(env, struct { r: u8, g: u8, b: u8 }) };
    }
};
```

## TypeScript declarations

```zig
.npm = .{
    .scope = "@myscope",
    .repository = .{ .url = "https://github.com/myorg/myrepo" },
    .dts = .{ .file = b.path("src/index.d.ts") },
},
```

Three modes:

- **`.{ .file = path }`**, copy a hand-written `.d.ts` into the package. **Recommended for libraries published to npm.** Gives you the full TypeScript surface, overloads, conditional types, branded types, JSDoc, and lets you keep your public API stable independent of internal Zig refactors.
- **`.auto`**, generate a `.d.ts` automatically by walking your module at comptime. Useful for prototypes, internal addons, or as a _starting point_ you then check into `src/index.d.ts` and edit. Expect `unknown` wherever you used `napi.Val` or `napi.Callback`, these are intentional escape hatches with no inferable JS type. Tighten the Zig signatures (`[]f64` instead of `[]napi.Val`) and the dts gets specific automatically.
- **`.none`** (default), no declarations emitted.

**Rule of thumb:** if your addon will be installed by other people, hand-write your `.d.ts`. If it's internal, `.auto` is fine.

## Memory model

Every JS-to-Zig call hands you an `Env` carrying an arena allocator. Use `env.allocator()` for any temporary memory, strings, slices, scratch space. Everything is freed automatically when your function returns.

```zig
pub fn process(env: napi.Env, input: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "processed: {s}", .{input});
}
```

A fresh arena is constructed for each call and freed when your function returns. Its backing pages come from `std.heap.smp_allocator`, a thread-cached allocator: pages freed on return stay on the thread's freelist for the next call to reuse, so the hot path doesn't hit the kernel. Calls that don't allocate pay nothing, `add(i32, i32)` never goes near the allocator.

> [!IMPORTANT]
> Arena memory is valid only for the duration of the call. For data that outlives the function (workers, threads), copy to a long-lived allocator yourself. See [Workers](#workers).

## Errors

Zig errors become JS exceptions automatically.

```zig
pub fn divide(a: f64, b: f64) !f64 {
    if (b == 0) return error.DivisionByZero;
    return a / b;
}
```

```js
divide(1, 0); // Error: DivisionByZero
divide("x", 1); // TypeError: expected number, got string
```

If you want to throw a specific JS exception type, do it explicitly and return the error:

```zig
pub fn parse(env: napi.Env, input: []const u8) ![]const u8 {
    if (input.len == 0) {
        env.throwRangeError("input must not be empty");
        return error.InvalidArg;
    }
    ...
}
```

`napi.Error` (the napi-zig error set) covers every distinct N-API failure mode, `error.QueueFull`, `error.PendingException`, `error.StringExpected`, etc. You can `catch` them individually when you need to.

## Callbacks

Accept a JS function as a parameter using `napi.Callback`. It is validated on conversion, non-functions throw `TypeError`.

```zig
pub fn forEach(env: napi.Env, items: []napi.Val, cb: napi.Callback) !void {
    for (items, 0..) |item, i| {
        _ = try cb.call(env, .{ item, @as(u32, @intCast(i)) });
    }
}
```

```js
forEach([10, 20, 30], (item, i) => console.log(i, item));
```

`call`'s args is a Zig **tuple**, values are auto-converted to JS. Use `callWith(env, this, args)` for a specific `this` binding. Pass a `[]const Val` slice when you have one already built.

| Method                      | Purpose                                                 |
| --------------------------- | ------------------------------------------------------- |
| `call(env, args_tuple)`     | Call with `undefined` as `this`                         |
| `callWith(env, this, args)` | Call with a specific `this`                             |
| `threadsafe(env, name, T)`  | Cross-thread wrapper, see [ThreadsafeFn](#threadsafefn) |

## Async

### Workers

`env.runWorker` offloads CPU work to a background thread and returns a JS Promise. Define a struct with two methods:

- `compute(*Self) void` runs on the worker thread (no JS access).
- `resolve(*Self, Env) !T` runs on the main thread; the return value (or error) becomes the promise result. `T` may be any convertible Zig type, `napi.Val`, or `void`.

```zig
const FibWork = struct {
    n: i32,
    result: i32 = 0,

    pub fn compute(self: *FibWork) void {
        self.result = fib(self.n);
    }

    pub fn resolve(self: *FibWork, _: napi.Env) !i32 {
        return self.result;
    }

    fn fib(n: i32) i32 {
        if (n <= 1) return n;
        return fib(n - 1) + fib(n - 2);
    }
};

pub fn asyncFib(env: napi.Env, n: i32) !napi.Val {
    return env.runWorker("fib", FibWork{ .n = n });
}
```

```js
const result = await asyncFib(10); // 55
```

If `resolve` returns an error, the Promise rejects with a real JS `Error` whose `.message` is the Zig error name:

```js
asyncFib(-1).catch((e) => console.log(e.message)); // e.g. "InvalidInput"
```

> [!WARNING]
> A panic in `compute` (index out of bounds, unreachable) crashes the entire Node.js process. Handle errors by storing state and checking it in `resolve`.

**Memory in workers:** the worker context is copied to the heap before the function returns, so arena-allocated data (strings from JS) will be dangling when `compute` runs. Copy what you need first:

```zig
pub fn asyncParse(env: napi.Env, source: []const u8) !napi.Val {
    const owned = try std.heap.smp_allocator.dupe(u8, source);
    return env.runWorker("parse", ParseWork{ .source = owned });
}
```

### ThreadsafeFn

`ThreadsafeFn(T)` lets a background thread call back into JS. Node is single-threaded, so you can't call N-API from a spawned thread directly, `ThreadsafeFn` queues calls back to the main thread.

```zig
pub fn startWorkers(env: napi.Env, cb: napi.Callback) !void {
    const tsfn = try cb.threadsafe(env, "workers", u32);

    for (0..4) |i| {
        try tsfn.acquire();
        const t = try std.Thread.spawn(.{}, struct {
            fn run(ts: napi.ThreadsafeFn(u32), id: u32) void {
                defer ts.release() catch {};
                ts.call(id, .blocking) catch {};
            }
        }.run, .{ tsfn, @as(u32, @intCast(i)) });
        t.detach();
    }
    try tsfn.release();
}
```

Use `void` for signal-only callbacks: `cb.threadsafe(env, "tick", void)`.

| Method                    | Purpose                                                    |
| ------------------------- | ---------------------------------------------------------- |
| `call(value, mode)`       | Queue a call from any thread (`.blocking`/`.non_blocking`) |
| `release()`               | Release this thread's reference                            |
| `abort()`                 | Release and reject pending calls                           |
| `acquire()`               | Register an additional thread                              |
| `ref(env)` / `unref(env)` | Control whether the event loop stays alive                 |

> [!TIP]
> `ThreadsafeFn` is for **multi-call** patterns (progress, events, streaming). For single-result background work, use `runWorker`, it's simpler and returns a Promise.

### Promises

For Promises without a background thread, build them directly:

```zig
pub fn delayed(env: napi.Env) !napi.Val {
    const p = try env.createPromise();
    try p.deferred.resolve(env, try env.toJs(42));
    return p.promise;
}
```

`Deferred` has `resolve(env, val)` and `reject(env, val)`. Each handle is single-use.

## Release & publishing

### Cross-compile every platform

```sh
napi build --release
```

Generates the npm package structure:

```
npm/my-addon/
  package.json              # main package with optionalDependencies
  index.js                  # re-exports the binding
  binding.js                # platform detection + loading
  index.d.ts                # auto-generated (or your hand-written file)
  @myscope/
    binding-linux-x64-gnu/
      package.json
      my-addon.node
    binding-darwin-arm64/
      ...
```

### First-time setup (npm trusted publishing / OIDC)

```sh
npm login
napi npm-init --repo myorg/myrepo --workflow publish.yml
```

This publishes initial versions of every package and configures OIDC so future releases from CI need no `NPM_TOKEN`.

### Bump and tag

```sh
napi bump          # interactive picker
napi bump patch    # explicit
napi bump 1.2.3
```

Updates every `package.json` (main + every binding), creates an annotated tag, and pushes, branch + tag in one round-trip.

### CI publish workflow

`.github/workflows/publish.yml`:

```yaml
name: Publish
on:
  push:
    tags: ["v*"]

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with: { version: master }
      - uses: actions/setup-node@v4
        with: { node-version: 24, registry-url: https://registry.npmjs.org }
      - run: npm install
      - run: npx napi-zig build --release
      - run: npx napi-zig publish
```

### CLI reference

| Command                                         | Description                                    |
| ----------------------------------------------- | ---------------------------------------------- |
| `napi new [name]`                               | Scaffold a new project (prompts for missing)   |
| `napi build`                                    | Build for current platform                     |
| `napi build --release`                          | Cross-compile every platform                   |
| `napi bump [version]`                           | Bump version, commit, tag, push                |
| `napi publish`                                  | Publish all packages to npm (CI)               |
| `napi npm-init --repo <repo> --workflow <file>` | Initial publish + configure trusted publishing |

`napi new` options:

| Option        | Default              | Description                            |
| ------------- | -------------------- | -------------------------------------- |
| `[name]`      | interactive          | Project name (also the addon name)     |
| `--pm <pm>`   | detected             | `npm`, `yarn`, `pnpm`, or `bun`        |

`napi bump` options:

| Option           | Default     | Description                                        |
| ---------------- | ----------- | -------------------------------------------------- |
| `[version]`      | interactive | `patch`, `minor`, `major`, or an exact version     |
| `--preid <id>`   | `beta`      | Pre-release identifier                             |
| `--commit <msg>` | `%s`        | Commit message (`%s` is replaced with the version) |
| `--no-tag`       |             | Skip git tag                                       |
| `--no-push`      |             | Skip git push                                      |

`napi publish` options:

| Option            | Default    | Description                     |
| ----------------- | ---------- | ------------------------------- |
| `--provenance`    | auto in CI | Generate provenance attestation |
| `--no-provenance` |            | Skip provenance                 |

## API reference

### `napi.Env`

The Node-API environment, plus the per-call allocator.

| Method                                                                         | Purpose                                                |
| ------------------------------------------------------------------------------ | ------------------------------------------------------ |
| `allocator()`                                                                  | Per-call `std.mem.Allocator` (arena, freed on return)  |
| `toJs(value)`                                                                  | Convert any Zig type to JS (inferred)                  |
| `createBoolean`, `createInt32`, `createUint32`, `createInt64`, `createFloat64` | Primitives                                             |
| `createBigintInt64`, `createBigintUint64`                                      | BigInt                                                 |
| `createString([]const u8)`, `createStringZ([*:0]const u8)`                     | Strings                                                |
| `createNull`, `createUndefined`, `getGlobal`                                   | Singletons                                             |
| `createObject`, `createArray`, `createArrayWithLength`                         | Containers                                             |
| `createSymbol(?description)`                                                   | Symbol                                                 |
| `createDate(time_ms)`                                                          | Date                                                   |
| `createExternal(ptr, finalize, hint)`                                          | Wrap an opaque Zig pointer                             |
| `createArrayBuffer(len)`                                                       | Returns `{ .val, .data }` (JS value + writable `[]u8`) |
| `createBuffer(len)`                                                            | Node.js Buffer, returns `{ .val, .data }`              |
| `createTypedArray(type, len, ab, offset)`                                      | TypedArray view                                        |
| `createExternalArrayBuffer(ptr, len, finalize, hint)`                          | Externally-owned memory                                |
| `createFunction(name, callback)`                                               | Native-backed JS function                              |
| `createReference(val)`                                                         | Strong GC reference, returns `Ref`                     |
| `createPromise()`                                                              | Returns `{ .promise, .deferred }`                      |
| `runWorker(name, context)`                                                     | Background work, returns Promise                       |
| `throwError`, `throwTypeError`, `throwRangeError`                              | Throw exceptions                                       |
| `throwValue(val)`                                                              | Throw an existing JS value                             |
| `createError(message)`                                                         | Construct a JS `Error` without throwing it             |
| `isExceptionPending()`                                                         | Check for pending exception                            |
| `getVersion()`, `getNodeVersion()`                                             | N-API / Node version info                              |

### `napi.Val`

A handle to a JS value.

| Method                                                                        | Purpose                                                    |
| ----------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `to(env, T)`                                                                  | Convert to any supported Zig type                          |
| `typeOf(env)`                                                                 | Returns `.string`, `.number`, `.object`, `.function`, etc. |
| `strictEquals(env, other)`                                                    | JS `===`                                                   |
| `isArray`, `isBuffer`, `isArrayBuffer`, `isTypedArray`, `isDate`, `isPromise` | Type checks                                                |
| `getProperty`, `setProperty`                                                  | Dynamic key access                                         |
| `getNamedProperty`, `setNamedProperty`, `hasNamedProperty`                    | Compile-time key access                                    |
| `getElement`, `setElement`, `getArrayLength`                                  | Array access                                               |
| `getArrayBufferData`, `getBufferData`                                         | `[]u8` into backing memory                                 |
| `getExternalData`                                                             | Unwrap an external pointer                                 |
| `getDateValue`                                                                | Date → epoch ms                                            |

### `napi.Callback`

A validated JS function handle.

| Method                      | Purpose                                               |
| --------------------------- | ----------------------------------------------------- |
| `call(env, args_tuple)`     | Call with `undefined` as `this`. Args is a Zig tuple. |
| `callWith(env, this, args)` | Call with a specific `this` binding                   |
| `threadsafe(env, name, T)`  | Create a `ThreadsafeFn(T)` for cross-thread calls     |

### `napi.Ref`

```zig
const ref = try env.createReference(some_val);
defer ref.delete(env) catch {};
const v = try ref.value(env);
```

### `napi.Error`

The full N-API error set. Mapped 1:1 from `napi_status`. Use it when you want to handle a specific failure mode:

```zig
cb.call(env, .{x}) catch |e| switch (e) {
    error.QueueFull => return,
    error.Closing => return,
    else => return e,
};
```

### `napi.class(name, T)`

Wrap a Zig struct as a JS class. See [Classes](#classes) for the full description.

```zig
pub const MyClass = napi.class("MyClass", struct { ... });
```

### `napi.dts.generate(Module)`

Returns the comptime-generated TypeScript declaration string for `Module`. Used by the `.dts = .auto` build option; you don't normally call it directly.

## License

MIT
