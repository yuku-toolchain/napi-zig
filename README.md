# napi-zig

Write [Node.js native addons](https://nodejs.org/api/n-api.html) in Zig. Cross-compile for all platforms and publish to npm.

## Quick start

**1. Add the dependency**

```sh
zig fetch --save https://github.com/aspect-build/napi-zig/archive/<commit>.tar.gz
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

`napi.module(@This())` exports every `pub fn` as a JS function and every `pub const` with a JS-compatible value as a JS property. Snake_case names are converted to camelCase automatically.

> [!NOTE]
> Only *values* are exported, not types. `pub const config = .{ .debug = true }` becomes a JS object. `pub const Config = struct { ... }` is a type and is skipped.

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

## Core types

### `Val`

A JS value handle. Convert to Zig types with `to`, access properties with `get*`/`set*`, inspect with `typeOf`/`is*`.

```zig
const name = try val.to(env, []const u8);
const age = try val.to(env, ?i32);
const items = try val.to(env, []f64);

const obj = try env.createObject();
try obj.setNamedProperty(env, "key", try env.toJs("value"));
const prop = try obj.getNamedProperty(env, "key");

const vtype = try val.typeOf(env); // .string, .number, .object, ...
```

### `Env`

The Node-API environment handle. Create JS values with `create*`, convert Zig values with `toJs`, and throw exceptions.

```zig
const js_str = try env.toJs("hello");
const js_num = try env.createInt32(42);
const obj = try env.createObject();

env.throwTypeError("something went wrong");
```

See [Memory model](#memory-model) for the per-call arena allocator.

### `JsFn`

A JS function handle. Validated on conversion, throws `TypeError` if the value is not a function.

```zig
pub fn map(env: napi.Env, arr: []napi.Val, callback: napi.JsFn) !napi.Val {
    const result = try env.createArray();
    for (arr, 0..) |item, i| {
        try result.setElement(env, @intCast(i), try callback.call(env, &.{item}));
    }
    return result;
}
```

Use `callWith` for a specific `this` binding:

```zig
const result = try callback.callWith(env, this_obj, &.{arg});
```

### `ThreadsafeFn`

A thread-safe wrapper for calling a JS function from any thread. Node.js is single-threaded, so you cannot call N-API from a spawned thread directly. `ThreadsafeFn` queues calls back to the main thread safely.

Created from a `JsFn` via `.threadsafe(env, name)`. Must be released when done.

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

A strong reference to a JS value, preventing garbage collection.

```zig
const ref = try env.createReference(some_val);
defer ref.delete(env) catch {};
const val = try ref.value(env);
```

## Memory model

Each function call receives an `Env` with a per-call `ArenaAllocator`, similar to how [Zig's juicy main](https://github.com/ziglang/zig/issues/24510) receives an arena from the runtime. Use `env.arena.allocator()` for any temporary allocations. All JS-to-Zig conversions that produce slices (`[]const u8`, `[]T`) also allocate on this arena. Everything is freed automatically when the function returns.

```zig
pub fn process(env: napi.Env, input: []const u8) ![]const u8 {
    // `input` lives on env.arena (converted from JS string)
    // use the same arena for your own allocations
    const alloc = env.arena.allocator();
    return try std.fmt.allocPrint(alloc, "processed: {s}", .{input});
    // arena freed on return, no manual cleanup
}
```

> [!IMPORTANT]
> Arena data is only valid for the duration of the call. If you need allocations that outlive the function (e.g., data passed to a background thread), use `std.heap.c_allocator` and manage the lifetime yourself. See [Workers](#workers) for an example.

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
divide(1, 0)    // Error: DivisionByZero
divide("x", 1)  // TypeError: expected number, got string
```

## Async patterns

### Workers

`env.runWorker` offloads CPU work to a background thread and returns a Promise. Define a struct with two methods:

- `compute(*Self) void` runs on a worker thread (no env, no JS calls)
- `resolve(*Self, Env) !T` runs on the main thread, return value becomes the promise result

The struct is heap-allocated and lives across both phases. You can allocate data in `compute` and clean it up in `resolve`.

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

**Memory in workers:** the worker context is copied to the heap before the function returns, so arena-allocated data (like `[]const u8` from JS strings) will be dangling by the time `compute` runs. Copy what you need to `std.heap.c_allocator` first:

```zig
const ParseWork = struct {
    source: []const u8,        // owned copy, not arena
    result: []const u8 = &.{},

    pub fn compute(self: *ParseWork) void {
        // safe to read self.source here
    }

    pub fn resolve(self: *ParseWork, env: napi.Env) !napi.Val {
        defer std.heap.c_allocator.free(self.source);
        return env.toJs(self.result);
    }
};

pub fn asyncParse(env: napi.Env, source: []const u8) !napi.Val {
    // copy arena string to long-lived allocator
    const owned = try std.heap.c_allocator.dupe(u8, source);
    return env.runWorker("parse", ParseWork{ .source = owned });
}
```

### Promises

For cases where you need a Promise without a background thread, use `env.createPromise()` directly:

```zig
pub fn delayed(env: napi.Env) !napi.Val {
    const p = try env.createPromise();
    // resolve immediately (in practice, resolve later from a callback or timer)
    try p.deferred.resolve(env, try env.toJs(42));
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

Zig enums map to JS strings. Both camelCase and snake_case are accepted on input. Invalid values throw a `TypeError`.

```zig
const Level = enum { debug, info, warning, error_level };

pub fn log(level: Level, msg: []const u8) void {
    // ...
}
```

```js
log("warning", "disk almost full")
log("errorLevel", "out of memory")  // camelCase also works
log("invalid", "...")               // TypeError: invalid enum value: 'invalid'
```

## License

MIT
