# napi-zig

Write [Node.js native addons](https://nodejs.org/api/n-api.html) in Zig. Cross-compile for all platforms and publish to npm.

## Table of contents

- [Getting started](#getting-started)
- [Project setup](#project-setup)
- [Release build](#release-build)
- [Publishing to npm](#publishing-to-npm)
- [CLI reference](#cli-reference)
- [Calling conventions](#calling-conventions)
- [Type conversion](#type-conversion)
- [TypeScript declarations](#typescript-declarations)
- [Memory model](#memory-model)
- [Error handling](#error-handling)
- [Callbacks](#callbacks)
- [Async](#async)
- [API reference](#api-reference)

## Getting started

### 1. Add napi-zig to your Zig project

```sh
zig fetch --save git+https://github.com/yuku-toolchain/napi-zig.git/#HEAD
```

### 2. Install the CLI

```sh
npm install -D napi-zig
```

### 3. Write your addon

```zig
// src/lib.zig
const std = @import("std");
const napi = @import("napi-zig");

comptime {
    napi.module(@This());
}

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn greet(env: napi.Env, name: []const u8) ![]const u8 {
    const alloc = env.arena.allocator();
    return try std.fmt.allocPrint(alloc, "Hello, {s}!", .{name});
}
```

`napi.module(@This())` exports every `pub fn` as a JS function and every `pub const` with a JS-compatible value as a JS property. Snake_case names are converted to camelCase automatically.

### 4. Configure build.zig

```zig
const std = @import("std");
const napi_zig = @import("napi_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const napi_dep = b.dependency("napi_zig", .{});

    napi_zig.addLib(b, napi_dep, .{
        .name = "my-addon",
        .root = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .npm = .{
            .scope = "@myscope",
            .repository = .{ .url = "https://github.com/myorg/myrepo" },
            .description = "My native addon",
        },
    });
}
```

### 5. Build and test

```sh
napi build
```

This compiles for your current platform and creates a `my-addon.js` loader so you can import the addon directly:

```js
import addon from "./my-addon.js";
console.log(addon.add(2, 3)); // 5
console.log(addon.greet("world")); // Hello, world!
```

That's it. You have a working native addon.

## Project setup

### `addLib` options

| Option      | Required | Description                                                        |
| ----------- | -------- | ------------------------------------------------------------------ |
| `.name`     | Yes      | Package name (used for the `.node` binary and npm package)         |
| `.root`     | Yes      | Path to the root Zig source file                                   |
| `.target`   | Yes      | Build target (from `standardTargetOptions`)                        |
| `.optimize` | Yes      | Optimization mode (from `standardOptimizeOption`)                  |
| `.imports`  | No       | Additional Zig module imports (see below)                          |
| `.npm`      | No       | npm package config (required for cross-compilation and publishing) |

#### Importing other modules

Use `.imports` to make other Zig modules available to your addon:

```zig
const parser_module = b.addModule("parser", .{
    .root_source_file = b.path("src/parser/root.zig"),
    .target = target,
    .optimize = optimize,
});

napi_zig.addLib(b, napi_dep, .{
    .name = "my-addon",
    .root = b.path("src/napi/root.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "parser", .module = parser_module },
    },
    .npm = .{ ... },
});
```

Then in your addon code: `const parser = @import("parser");`

#### `.npm` options

| Option         | Required | Default             | Description                                                                  |
| -------------- | -------- | ------------------- | ---------------------------------------------------------------------------- |
| `.scope`       | Yes      |                     | npm scope (e.g. `"@myscope"`)                                                |
| `.repository`  | Yes      |                     | Repository for npm provenance (`.url` required, `.type` defaults to `"git"`) |
| `.description` | No       | `""`                | Package description                                                          |
| `.license`     | No       | `"MIT"`             | License identifier                                                           |
| `.dts`         | No       | `null`              | Path to a TypeScript declaration file                                        |
| `.platforms`   | No       | `Platform.defaults` | Target platforms for cross-compilation                                       |

Default platforms: Linux (x64, arm64, arm with glibc and musl), macOS (x64, arm64), Windows (x64, arm64), FreeBSD (x64).

## Release build

Before publishing, cross-compile for all platforms:

```sh
napi build --release
```

This generates the npm package structure in `npm/my-addon/`:

```
npm/my-addon/
  package.json              # main package with optionalDependencies
  index.js                  # re-exports the native binding
  binding.js                # platform detection and loading
  @myscope/
    binding-linux-x64-gnu/
      package.json
      my-addon.node
    binding-darwin-arm64/
      package.json
      my-addon.node
    binding-win32-x64/
      ...
```

The main `index.js` re-exports the native binding. You can replace it with a custom wrapper in `npm/my-addon/`. The build system preserves existing files and only updates `.node` binaries on subsequent builds.

## Publishing to npm

### Prerequisites

1. Create an npm organization at [npmjs.com/org/create](https://www.npmjs.com/org/create) matching your scope (e.g. `myscope` for `@myscope`)
2. Log in: `npm login`
3. Requires npm >= 11.10.0 (`npm install -g npm@latest`)

### First-time setup

After your first `napi build --release`, publish all packages and configure [npm trusted publishing](https://docs.npmjs.com/trusted-publishers/) (OIDC) so GitHub Actions can publish future releases without tokens:

```sh
napi npm-init --repo myorg/myrepo --workflow publish.yml
```

This publishes the main package and all binding packages, then configures trusted publishing for each one. You only need to run this once (or again when adding new addons).

### Release workflow

**Bump, tag, and push:**

```sh
napi bump
```

Shows an interactive version picker (patch, minor, major, pre-release, custom). Updates every `package.json` (main + all bindings), creates an annotated git tag, and pushes. You can also pass the version directly:

```sh
napi bump patch
napi bump 1.2.3
napi bump --commit "release v%s" --preid alpha
```

**GitHub Actions picks up the tag and publishes:**

Create `.github/workflows/publish.yml`:

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
        with:
          version: master

      - uses: actions/setup-node@v4
        with:
          node-version: 24
          registry-url: https://registry.npmjs.org

      - run: npm install
      - run: npx napi-zig build --release
      - run: npx napi-zig publish
```

No `NPM_TOKEN` needed. The `id-token: write` permission enables OIDC authentication with npm, which was configured during `napi npm-init`.

## CLI reference

| Command                                               | Description                                        |
| ----------------------------------------------------- | -------------------------------------------------- |
| `napi build`                                          | Build for current platform                         |
| `napi build --release`                                | Cross-compile all platforms, generate npm packages |
| `napi bump [version]`                                 | Bump version, commit, tag, push                    |
| `napi publish`                                        | Publish all packages to npm (for CI)               |
| `napi npm-init --repo <owner/repo> --workflow <file>` | First-time publish + configure trusted publishing  |

**`napi bump` options:**

| Option           | Default     | Description                                                 |
| ---------------- | ----------- | ----------------------------------------------------------- |
| `[version]`      | interactive | `patch`, `minor`, `major`, or an exact version like `1.2.3` |
| `--preid <id>`   | `beta`      | Pre-release identifier                                      |
| `--commit <msg>` | `%s`        | Commit message (`%s` is replaced with the version)          |
| `--no-tag`       |             | Skip git tag                                                |
| `--no-push`      |             | Skip git push                                               |

**`napi publish` options:**

| Option            | Default    | Description                     |
| ----------------- | ---------- | ------------------------------- |
| `--provenance`    | auto in CI | Generate provenance attestation |
| `--no-provenance` |            | Skip provenance                 |

## Calling conventions

### Standard mode

Write plain Zig functions. Arguments are converted from JS, return values converted back. Errors become JS exceptions.

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn double(x: f64) f64 {
    return x * 2;
}
```

Add `Env` as the first parameter when you need the environment. It is injected automatically and does not consume a JS argument.

```zig
pub fn process(env: napi.Env, data: []const u8) !napi.Val {
    const alloc = env.arena.allocator();
    const upper = try alloc.alloc(u8, data.len);
    for (upper, data) |*dst, src| dst.* = std.ascii.toUpper(src);
    return env.toJs(upper);
}
```

For types that need manual construction (buffers, objects with dynamic keys), return `!napi.Val` and build the value yourself:

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

### Raw mode

For full manual control, take `(Env, CallInfo)` as the first two parameters. You extract arguments yourself and return a `Val` directly.

```zig
pub fn variadic(env: napi.Env, info: napi.CallInfo) !napi.Val {
    const argc = try info.getArgCount(env);
    var sum: f64 = 0;
    const args = try info.getArgs(env, 16);
    for (0..argc) |i| sum += try args[i].to(env, f64);
    return env.toJs(sum);
}
```

## Type conversion

### Zig to JS (`env.toJs`)

**Constants:**

| Zig type | JS result             |
| -------- | --------------------- |
| `bool`   | Boolean               |
| `void`   | `undefined`           |
| `?T`     | inner value or `null` |

**Numbers:**

| Zig type                   | JS result | Notes                              |
| -------------------------- | --------- | ---------------------------------- |
| `comptime_int`             | Number    | Compiler-checked to fit f64        |
| `comptime_float`           | Number    |                                    |
| `i1`..`i32`                | Number    |                                    |
| `u1`..`u32`                | Number    |                                    |
| `i33`..`i53`, `u33`..`u53` | Number    | Via f64, within safe integer range |
| `i54`..`i64`               | BigInt    |                                    |
| `u54`..`u64`               | BigInt    |                                    |
| `f16`, `f32`, `f64`        | Number    | Cast to f64                        |

**Strings:**

| Zig type                     | JS result                |
| ---------------------------- | ------------------------ |
| `[]const u8`, `[:0]const u8` | String                   |
| `*const [N:0]u8`             | String (string literals) |

**Arrays:**

| Zig type           | JS result          |
| ------------------ | ------------------ |
| `[N]T`             | Array (fixed-size) |
| `[]T`, `[]const T` | Array (slice)      |
| `struct { S, T }`  | Array (tuple)      |

**Objects:**

| Zig type                    | JS result                                    |
| --------------------------- | -------------------------------------------- |
| `enum`                      | String (tag name)                            |
| `struct { foo: S, bar: T }` | Object (field names snake_case to camelCase) |

**Special:**

| Zig type                 | JS result                                            |
| ------------------------ | ---------------------------------------------------- |
| `Val`                    | Passthrough                                          |
| Types with `pub fn toJs` | Custom (see [Custom conversion](#custom-conversion)) |

### JS to Zig (`val.to(env, T)`)

**Constants:**

| JS type         | Zig type            |
| --------------- | ------------------- |
| Boolean         | `bool`              |
| null, undefined | `?T` returns `null` |

**Numbers:**

| JS type | Zig type                   | Notes              |
| ------- | -------------------------- | ------------------ |
| Number  | `i1`..`i32`, `u1`..`u32`   | Validated by N-API |
| Number  | `i33`..`i53`, `u33`..`u53` | Via i64/f64        |
| Number  | `f16`, `f32`, `f64`        | Cast from f64      |
| BigInt  | `i54`..`i64`, `u54`..`u64` |                    |

**Strings:**

| JS type | Zig type     | Notes                                                           |
| ------- | ------------ | --------------------------------------------------------------- |
| String  | `[]const u8` | Arena-allocated                                                 |
| String  | `enum`       | Accepts camelCase or snake_case, invalid values throw TypeError |

**Arrays:**

| JS type | Zig type          | Notes                                   |
| ------- | ----------------- | --------------------------------------- |
| Array   | `[N]T`            | Fixed-size, elements converted by index |
| Array   | `[]T`             | Arena-allocated                         |
| Array   | `struct { S, T }` | Tuple, elements converted by index      |

**Objects:**

| JS type  | Zig type   | Notes                                         |
| -------- | ---------- | --------------------------------------------- |
| Object   | `struct`   | camelCase field matching, defaults respected  |
| Function | `Callback` | Validated, throws TypeError if not a function |

**Special:**

| JS type | Zig type                                       |
| ------- | ---------------------------------------------- |
| any     | `Val` (passthrough)                            |
| any     | Types with `pub fn fromJs` (custom, see below) |

Type mismatches throw a descriptive `TypeError`:

```
TypeError: expected string, got number
TypeError: invalid enum value: 'foo'
```

### Struct and enum mapping

Struct fields are matched by camelCase name. Default values are respected for missing properties:

```zig
const Options = struct {
    file_path: []const u8,
    line_count: i32,
    verbose: bool = false,
};

pub fn compile(opts: Options) ![]const u8 { ... }
```

```js
compile({ filePath: "main.zig", lineCount: 100 });
// verbose defaults to false
```

Enums map to/from strings. Both camelCase and snake_case accepted on input:

```js
log("warning", "disk almost full");
log("errorLevel", "out of memory"); // camelCase also works
log("invalid", "..."); // TypeError: invalid enum value: 'invalid'
```

### Custom conversion

For types with no built-in conversion (like unions), add `toJs` and/or `fromJs` methods:

```zig
const Color = union(enum) {
    rgb: struct { r: u8, g: u8, b: u8 },
    hex: []const u8,

    pub fn toJs(self: Color, env: napi.Env) !napi.Val {
        return switch (self) {
            .rgb => |rgb| {
                const obj = try env.createObject();
                try obj.setNamedProperty(env, "r", try env.toJs(rgb.r));
                try obj.setNamedProperty(env, "g", try env.toJs(rgb.g));
                try obj.setNamedProperty(env, "b", try env.toJs(rgb.b));
                return obj;
            },
            .hex => |h| env.toJs(h),
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

If a struct has a `toJs` or `fromJs` method, it takes priority over the default field-by-field conversion.

## TypeScript declarations

Create a `.d.ts` file and pass it via the `.dts` option:

```ts
// src/index.d.ts
export function add(a: number, b: number): number;
export function greet(name: string): string;
```

```zig
// in build.zig
.npm = .{
    .scope = "@myscope",
    .repository = .{ .url = "https://github.com/myorg/myrepo" },
    .dts = b.path("src/index.d.ts"),
},
```

The file is copied into the npm package as `index.d.ts`. Users get type checking and editor autocompletion out of the box.

## Memory model

Each function call receives an `Env` with a per-call `ArenaAllocator`, similar to how [Zig's juicy main](https://github.com/ziglang/zig/issues/24510) receives an arena from the runtime. Use `env.arena.allocator()` for any temporary allocations. All JS-to-Zig conversions that produce slices (`[]const u8`, `[]T`) also allocate on this arena. Everything is freed automatically when the function returns.

```zig
pub fn process(env: napi.Env, input: []const u8) ![]const u8 {
    const alloc = env.arena.allocator();
    return try std.fmt.allocPrint(alloc, "processed: {s}", .{input});
}
```

> [!IMPORTANT]
> Arena data is only valid for the duration of the call. If you need allocations that outlive the function (e.g., data passed to a background thread), use a long-lived allocator and manage the lifetime yourself. See [Workers](#workers) for an example.

## Error handling

Zig errors become JS exceptions. If a function returns `!T` and an error occurs:

1. If a specific exception was thrown (e.g., `TypeError` from type mismatch), it is preserved.
2. Otherwise, the Zig error name is thrown as a generic `Error`.

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

## Callbacks

Accept a JS function as a parameter by using `napi.Callback`. It is validated on conversion. If the JS value is not a function, a `TypeError` is thrown.

```zig
pub fn forEach(env: napi.Env, arr: []napi.Val, callback: napi.Callback) !void {
    for (arr) |item| {
        _ = try callback.call(env, &.{item});
    }
}
```

```js
forEach([1, 2, 3], (item) => console.log(item));
// 1
// 2
// 3
```

Use `callWith` when you need a specific `this` binding:

```zig
const result = try callback.callWith(env, this_obj, &.{arg1, arg2});
```

To call a callback from a background thread, convert it to a `ThreadsafeFn` first (see [ThreadsafeFn](#threadsafefn)).

| Method                      | Purpose                                           |
| --------------------------- | ------------------------------------------------- |
| `call(env, args)`           | Call with `undefined` as `this`                   |
| `callWith(env, this, args)` | Call with specific `this` binding                 |
| `threadsafe(env, name, T)`  | Create a `ThreadsafeFn(T)` for cross-thread calls |

## Async

### Workers

`env.runWorker` offloads CPU work to a background thread and returns a Promise. Define a struct with two methods:

- `compute(*Self) void` runs on a worker thread (no env, no JS calls)
- `resolve(*Self, Env) !T` runs on the main thread, return value becomes the promise result

```zig
const FibWork = struct {
    n: i32,
    result: i32 = 0,

    pub fn compute(self: *FibWork) void {
        self.result = fib(self.n);
    }

    pub fn resolve(self: *FibWork, env: napi.Env) !napi.Val {
        return env.toJs(self.result);
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

If `resolve` returns an error, the promise is rejected with the error name.

**Error handling in `compute`:** `compute` returns `void`, not an error. If your computation can fail, store the error state in the context and check it in `resolve`:

```zig
const ParseWork = struct {
    source: []const u8,
    result: []const u8 = &.{},
    failed: bool = false,

    pub fn compute(self: *ParseWork) void {
        if (self.source.len == 0) {
            self.failed = true;
            return;
        }
        // ... do work ...
    }

    pub fn resolve(self: *ParseWork, env: napi.Env) !napi.Val {
        defer std.heap.smp_allocator.free(self.source);
        if (self.failed) return error.ParseFailed;
        return env.toJs(self.result);
    }
};
```

> [!WARNING]
> A panic in `compute` (e.g., index out of bounds, unreachable) crashes the entire Node.js process.

**Memory in workers:** the worker context is copied to the heap before the function returns, so arena-allocated data (like `[]const u8` from JS strings) will be dangling by the time `compute` runs. Copy what you need first:

```zig
pub fn asyncParse(env: napi.Env, source: []const u8) !napi.Val {
    const owned = try std.heap.smp_allocator.dupe(u8, source);
    return env.runWorker("parse", ParseWork{ .source = owned });
}
```

### ThreadsafeFn

`ThreadsafeFn(T)` calls a JS function from any thread, passing a typed value. Node.js is single-threaded, so you cannot call N-API from a spawned thread directly. ThreadsafeFn queues calls back to the main thread safely.

```zig
pub fn startWorkers(env: napi.Env, callback: napi.Callback) !void {
    const tsfn = try callback.threadsafe(env, "workers", u32);

    for (0..4) |i| {
        try tsfn.acquire();
        const thread = try std.Thread.spawn(.{}, struct {
            fn run(ts: napi.ThreadsafeFn(u32), id: u32) void {
                defer ts.release() catch {};
                ts.call(id, .blocking) catch {};
            }
        }.run, .{ tsfn, @as(u32, @intCast(i)) });
        thread.detach();
    }
    try tsfn.release();
}
```

```js
startWorkers((id) => console.log("worker", id, "done"));
// worker 0 done
// worker 2 done
// worker 1 done
// worker 3 done  (order varies)
```

Use `void` for signal-only callbacks with no data: `callback.threadsafe(env, "signal", void)`.

| Method                    | Purpose                                                       |
| ------------------------- | ------------------------------------------------------------- |
| `call(value, mode)`       | Queue a call from any thread (`.blocking` or `.non_blocking`) |
| `release()`               | Release this thread's reference                               |
| `abort()`                 | Release and reject pending calls                              |
| `acquire()`               | Register an additional thread                                 |
| `ref(env)` / `unref(env)` | Control whether the event loop stays alive                    |

> [!TIP]
> Use `ThreadsafeFn` when you need to call into JS **multiple times** from a background thread (progress, events, streaming). For one-shot background work that returns a single result, use `env.runWorker` instead.

### Promises

For cases where you need a Promise without a background thread, use `env.createPromise()` directly:

```zig
pub fn delayed(env: napi.Env) !napi.Val {
    const p = try env.createPromise();
    try p.deferred.resolve(env, try env.toJs(42));
    return p.promise;
}
```

`Deferred` has two methods: `resolve(env, val)` and `reject(env, val)`. Both consume the handle.

## API reference

### `Val`

A JS value handle.

| Method                                                                     | Purpose                                                    |
| -------------------------------------------------------------------------- | ---------------------------------------------------------- |
| `to(env, T)`                                                               | Convert to any supported Zig type                          |
| `typeOf(env)`                                                              | Returns `.string`, `.number`, `.object`, `.function`, etc. |
| `isArray(env)`, `isBuffer(env)`, `isArrayBuffer(env)`, `isTypedArray(env)` | Type checks                                                |
| `getProperty(env, key)`, `setProperty(env, key, val)`                      | Dynamic key access                                         |
| `getNamedProperty(env, key)`, `setNamedProperty(env, key, val)`            | Compile-time string key access                             |
| `hasNamedProperty(env, key)`                                               | Property existence check                                   |
| `getElement(env, i)`, `setElement(env, i, val)`                            | Array index access                                         |
| `getArrayLength(env)`                                                      | Array length                                               |
| `getArrayBufferData(env)`                                                  | `[]u8` into an ArrayBuffer's backing memory                |
| `getBufferData(env)`                                                       | `[]u8` into a Node.js Buffer's backing memory              |

### `Env`

The Node-API environment. Provides value creation, the per-call arena, and exception handling.

| Method                                                                         | Purpose                                                       |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------- |
| `toJs(value)`                                                                  | Convert any Zig type to JS (inferred)                         |
| `createBoolean`, `createInt32`, `createUint32`, `createInt64`, `createFloat64` | Primitives                                                    |
| `createBigintInt64`, `createBigintUint64`                                      | BigInt                                                        |
| `createString([]const u8)`, `createStringZ([*:0]const u8)`                     | Strings                                                       |
| `createNull`, `createUndefined`, `getGlobal`                                   | Singletons                                                    |
| `createObject`, `createArray`, `createArrayWithLength`                         | Containers                                                    |
| `createArrayBuffer(len)`                                                       | Returns `{ .val, .data }` (JS value + writable `[]u8`)        |
| `createBuffer(len)`                                                            | Node.js Buffer, returns `{ .val, .data }`                     |
| `createTypedArray(type, len, arraybuffer, offset)`                             | TypedArray view                                               |
| `createExternalArrayBuffer(ptr, len, finalize_cb, hint)`                       | Externally-owned memory                                       |
| `createFunction(name, callback)`                                               | Native-backed JS function                                     |
| `createReference(val)`                                                         | Strong GC reference, returns `Ref`                            |
| `createPromise()`                                                              | Returns `{ .promise, .deferred }`                             |
| `runWorker(name, context)`                                                     | Background work, returns Promise                              |
| `throwError`, `throwTypeError`, `throwRangeError`                              | Throw exceptions                                              |
| `throwValue(val)`                                                              | Throw an existing JS value                                    |
| `isExceptionPending()`                                                         | Check for pending exception                                   |
| `getVersion()`                                                                 | Node-API version                                              |
| `arena`                                                                        | Per-call `*ArenaAllocator`, see [Memory model](#memory-model) |

### `Ref`

A strong reference preventing garbage collection.

```zig
const ref = try env.createReference(some_val);
defer ref.delete(env) catch {};
const val = try ref.value(env);
```

## License

MIT
