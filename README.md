# napi-zig

Zig bindings for [Node-API](https://nodejs.org/api/n-api.html). Write native Node.js addons in Zig with automatic type conversion, per-call arena allocation, and zero-overhead function bridging.

## Quick start

**1. Add the dependency**

```sh
zig fetch --save https://github.com/yuku-toolchain/napi-zig.git/#HEAD
```

**2. Configure the build**

```zig
// build.zig
const napi_zig = @import("napi_zig");

pub fn build(b: *std.Build) void {
    const napi_dep = b.dependency("napi_zig", .{});
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const lib = napi_zig.addLib(b, napi_dep, .{
        .name = "my-addon",
        .root = b.path("src/napi_entry.zig"),
        .target = target,
        .optimize = optimize,
    });

    const step = b.step("napi", "Build .node for current platform");
    step.dependOn(lib.step);
}
```

**3. Write the module**

```zig
// src/napi_entry.zig
const napi = @import("napi-zig");

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub const version = "1.0.0";

comptime { napi.module(@This()); }
```

**4. Build and use**

```sh
zig build napi
```

```js
const addon = require('./zig-out/lib/my-addon.node');
addon.add(1, 2)  // 3
addon.version     // "1.0.0"
```

`napi.module(@This())` exports every `pub fn` as a JS function and every `pub const` as a JS value. Snake_case names are converted to camelCase automatically.

## Calling conventions

### Standard mode

Write plain Zig functions. Arguments are converted from JS automatically, return values converted back. Errors become JS exceptions.

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn double(x: f64) f64 {
    return x * 2;
}
```

Add `Env` as the first parameter when you need the environment (arena allocator, manual JS value creation, callbacks). It is injected automatically and does not consume a JS argument.

```zig
pub fn process(env: napi.Env, data: []const u8) !napi.Val {
    const alloc = env.arena.allocator();
    const upper = try alloc.alloc(u8, data.len);
    for (upper, data) |*dst, src| dst.* = std.ascii.toUpper(src);
    return env.toJs(upper);
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

| Zig type | JS result |
|---|---|
| `bool` | Boolean |
| `i8`..`i32`, `u8`..`u32` | Number |
| `i33`..`i53`, `u33`..`u53` | Number (f64) |
| `i54`..`i64` | BigInt |
| `u54`..`u64` | BigInt |
| `f16`, `f32`, `f64` | Number |
| `?T` | T or `null` |
| `enum` | String (tag name) |
| `[]const u8` | String |
| `[]T` | Array |
| `struct` | Object (snake_case to camelCase) |
| `void` | `undefined` |

### JS to Zig (`val.to(env, T)`)

| JS type | Zig type |
|---|---|
| Boolean | `bool` |
| Number | `i8`..`i64`, `u8`..`u32`, `f16`..`f64` |
| BigInt | `u33`..`u64` |
| String | `[]const u8` (arena-allocated) |
| String | `enum` (camelCase or snake_case) |
| Array | `[]T` (arena-allocated) |
| Object | `struct` (camelCase field matching) |
| Function | `JsFn` (validated) |
| any | `Val` (passthrough) |
| null/undefined | `?T` returns `null` |

Type mismatches throw a descriptive `TypeError`:

```
TypeError: expected string, got number
```

## Core types

### `Val`

A JS value handle. Convert to Zig types with `to`, access properties with `get*`/`set*`, inspect with `typeOf`/`is*`.

```zig
const name = try val.to(env, []const u8);
const age = try val.to(env, ?i32);
const items = try val.to(env, []f64);

const obj_val = try env.createObject();
try obj_val.setNamedProperty(env, "key", try env.toJs("value"));
const prop = try obj_val.getNamedProperty(env, "key");

const vtype = try val.typeOf(env); // .string, .number, .object, ...
```

### `Env`

The Node-API environment. Create JS values with `create*`, convert Zig values with `toJs`, throw exceptions, and access the per-call arena allocator.

```zig
const js_str = try env.toJs("hello");        // inferred
const js_num = try env.createInt32(42);       // explicit
const obj = try env.createObject();

const alloc = env.arena.allocator();          // freed on return
const buf = try alloc.alloc(u8, 1024);

env.throwTypeError("something went wrong");
```

### `JsFn`

A handle to a JS function. Validated on conversion (throws `TypeError` if the value is not a function).

```zig
pub fn forEach(env: napi.Env, arr: []napi.Val, callback: napi.JsFn) !void {
    for (arr) |item| _ = try callback.call(env, &.{item});
}

// callWith for a specific `this` binding
const result = try callback.callWith(env, this_obj, &.{arg1, arg2});
```

### `Deferred`

A handle for resolving or rejecting a JS Promise. Created via `env.createPromise()`, which returns both the Promise value (to return to JS) and the Deferred handle (to settle it later).

```zig
const p = try env.createPromise();
try p.deferred.resolve(env, try env.toJs(42)); // or p.deferred.reject(env, err_val)
return p.promise;
```

### `ThreadsafeFn`

A thread-safe wrapper for calling a JS function from any thread. Node.js is single-threaded, so you cannot call N-API from a spawned `std.Thread` directly. `ThreadsafeFn` queues calls back to the main thread safely.

Created from a `JsFn` via `.threadsafe(env, name)`. Must be released when no longer needed.

```zig
pub fn startWork(env: napi.Env, on_done: napi.JsFn) !void {
    const tsfn = try on_done.threadsafe(env, "worker");

    const thread = try std.Thread.spawn(.{}, struct {
        fn run(ts: napi.ThreadsafeFn) void {
            defer ts.release() catch {};

            // do expensive work on this thread...

            // queue the JS callback on the main thread
            // null = no data (for custom call_js, see napi.c)
            ts.call(null, .non_blocking) catch {};
        }
    }.run, .{tsfn});

    thread.detach();
}
```

```js
startWork(() => console.log("done!"))
```

### `Ref`

A strong reference to a JS value, preventing garbage collection. Created via `env.createReference()`.

```zig
const ref = try env.createReference(some_val);
defer ref.delete(env) catch {};
const val = try ref.value(env);
```

## Memory model

Every function call gets a per-call `ArenaAllocator` on `env.arena`. All string and slice conversions (`[]const u8`, `[]T`) allocate from this arena. It is freed automatically when the function returns. No manual cleanup needed.

```zig
pub fn process(env: napi.Env, input: []const u8) ![]const u8 {
    // `input` was converted from a JS string, lives on the arena
    const alloc = env.arena.allocator();
    return try std.fmt.allocPrint(alloc, "processed: {s}", .{input});
    // everything freed when this function returns
}
```

Arena data is only valid for the duration of the call. Do not store arena pointers in worker contexts or pass them to background threads. Copy to a long-lived allocator first if needed.

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
divide(1, 0) // Error: DivisionByZero
divide("x", 1) // TypeError: expected number, got string
```

## Async patterns

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
const result = await asyncFib(10) // 55
```

If `resolve` returns an error, the promise is rejected with the error name.

### Promises

For cases where you need a Promise without a background thread, use `env.createPromise()` directly:

```zig
pub fn delayed(env: napi.Env, callback: napi.JsFn) !napi.Val {
    const p = try env.createPromise();
    // pass deferred to a callback, timer, or event handler
    // that will call p.deferred.resolve(env, val) later
    try p.deferred.resolve(env, try env.toJs("done"));
    return p.promise;
}
```

## Struct mapping

Zig structs map to JS objects with camelCase field names. Default field values are respected for missing properties.

```zig
const Options = struct {
    file_path: []const u8,
    line_count: i32,
    verbose: bool = false,
};

pub fn compile(opts: Options) ![]const u8 {
    // opts.file_path, opts.line_count, opts.verbose
}
```

```js
compile({ filePath: "main.zig", lineCount: 100 })
// verbose defaults to false
```

## Enum mapping

Zig enums map to JS strings. Both camelCase and snake_case are accepted on input.

```zig
const Level = enum { debug, info, warning, error_level };

pub fn log(level: Level, msg: []const u8) void {
    // ...
}
```

```js
log("warning", "disk almost full")
log("errorLevel", "out of memory")  // camelCase also works
```

## Build options

### Single platform (development)

```zig
const lib = napi_zig.addLib(b, napi_dep, .{
    .name = "my-addon",
    .root = b.path("src/main.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{
        .{ .name = "my_lib", .module = my_module },
    },
});
```

The `.imports` field lets you pass additional Zig modules to the napi build, so your napi entry point can `@import("my_lib")`.

### Cross-platform (production)

```zig
napi_zig.addPack(b, napi_dep, .{
    .output = "npm",
    .entries = &.{
        .{
            .name = "my-addon",
            .scope = "@my-scope",
            .version = "1.0.0",
            .root = b.path("src/main.zig"),
        },
    },
});
```

Builds for all supported platforms (macOS arm64/x64, Linux x64 gnu/musl, Windows x64) and generates npm packages with a runtime loader that selects the correct binary.

## License

MIT
