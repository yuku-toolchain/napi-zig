# napi-zig

Write [Node.js native addons](https://nodejs.org/api/n-api.html) in Zig. Cross-compile for all platforms and publish to npm.

## Quick start

**1. Add the dependency**

```sh
zig fetch --save git+https://github.com/yuku-toolchain/napi-zig.git/#HEAD
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

| Zig type | JS result |
|---|---|
| `bool` | Boolean |
| `void` | `undefined` |
| `?T` | inner value or `null` |

**Numbers:**

| Zig type | JS result | Notes |
|---|---|---|
| `comptime_int` | Number | Compiler-checked to fit f64 |
| `comptime_float` | Number | |
| `i1`..`i32` | Number | |
| `u1`..`u32` | Number | |
| `i33`..`i53`, `u33`..`u53` | Number | Via f64, within safe integer range |
| `i54`..`i64` | BigInt | |
| `u54`..`u64` | BigInt | |
| `f16`, `f32`, `f64` | Number | Cast to f64 |

**Strings:**

| Zig type | JS result |
|---|---|
| `[]const u8`, `[:0]const u8` | String |
| `*const [N:0]u8` | String (string literals) |

**Arrays:**

| Zig type | JS result |
|---|---|
| `[N]T` | Array (fixed-size) |
| `[]T`, `[]const T` | Array (slice) |
| `struct { S, T }` | Array (tuple) |

**Objects:**

| Zig type | JS result |
|---|---|
| `enum` | String (tag name) |
| `struct { foo: S, bar: T }` | Object (field names snake_case to camelCase) |

**Special:**

| Zig type | JS result |
|---|---|
| `Val` | Passthrough |
| Types with `pub fn toJs` | Custom (see [Custom conversion](#custom-conversion)) |

### JS to Zig (`val.to(env, T)`)

**Constants:**

| JS type | Zig type |
|---|---|
| Boolean | `bool` |
| null, undefined | `?T` returns `null` |

**Numbers:**

| JS type | Zig type | Notes |
|---|---|---|
| Number | `i1`..`i32`, `u1`..`u32` | Validated by N-API |
| Number | `i33`..`i53`, `u33`..`u53` | Via i64/f64 |
| Number | `f16`, `f32`, `f64` | Cast from f64 |
| BigInt | `i54`..`i64`, `u54`..`u64` | |

**Strings:**

| JS type | Zig type | Notes |
|---|---|---|
| String | `[]const u8` | Arena-allocated |
| String | `enum` | Accepts camelCase or snake_case, invalid values throw TypeError |

**Arrays:**

| JS type | Zig type | Notes |
|---|---|---|
| Array | `[N]T` | Fixed-size, elements converted by index |
| Array | `[]T` | Arena-allocated |
| Array | `struct { S, T }` | Tuple, elements converted by index |

**Objects:**

| JS type | Zig type | Notes |
|---|---|---|
| Object | `struct` | camelCase field matching, defaults respected |
| Function | `Callback` | Validated, throws TypeError if not a function |

**Special:**

| JS type | Zig type |
|---|---|
| any | `Val` (passthrough) |
| any | Types with `pub fn fromJs` (custom, see below) |

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
compile({ filePath: "main.zig", lineCount: 100 })
// verbose defaults to false
```

Enums map to/from strings. Both camelCase and snake_case accepted on input:

```js
log("warning", "disk almost full")
log("errorLevel", "out of memory")  // camelCase also works
log("invalid", "...")               // TypeError: invalid enum value: 'invalid'
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

Works for structs too. If a struct has a `toJs` or `fromJs` method, it takes priority over the default field-by-field conversion.

## API reference

### `Val`

A JS value handle. One method per concern:

| Method | Purpose |
|---|---|
| `to(env, T)` | Convert to any supported Zig type |
| `typeOf(env)` | Returns `.string`, `.number`, `.object`, `.function`, etc. |
| `isArray(env)`, `isBuffer(env)`, `isArrayBuffer(env)`, `isTypedArray(env)` | Type checks |
| `getProperty(env, key)`, `setProperty(env, key, val)` | Dynamic key access |
| `getNamedProperty(env, key)`, `setNamedProperty(env, key, val)` | Compile-time string key access |
| `hasNamedProperty(env, key)` | Property existence check |
| `getElement(env, i)`, `setElement(env, i, val)` | Array index access |
| `getArrayLength(env)` | Array length |
| `getArrayBufferData(env)` | `[]u8` into an ArrayBuffer's backing memory |
| `getBufferData(env)` | `[]u8` into a Node.js Buffer's backing memory |

### `Env`

The Node-API environment. Provides value creation, the per-call arena, and exception handling.

| Method | Purpose |
|---|---|
| `toJs(value)` | Convert any Zig type to JS (inferred) |
| `createBoolean`, `createInt32`, `createUint32`, `createInt64`, `createFloat64` | Primitives |
| `createBigintInt64`, `createBigintUint64` | BigInt |
| `createString([]const u8)`, `createStringZ([*:0]const u8)` | Strings |
| `createNull`, `createUndefined`, `getGlobal` | Singletons |
| `createObject`, `createArray`, `createArrayWithLength` | Containers |
| `createArrayBuffer(len)` | Returns `{ .val, .data }` (JS value + writable `[]u8`) |
| `createBuffer(len)` | Node.js Buffer, returns `{ .val, .data }` |
| `createTypedArray(type, len, arraybuffer, offset)` | TypedArray view |
| `createExternalArrayBuffer(ptr, len, finalize_cb, hint)` | Externally-owned memory |
| `createFunction(name, callback)` | Native-backed JS function |
| `createReference(val)` | Strong GC reference, returns `Ref` |
| `createPromise()` | Returns `{ .promise, .deferred }` |
| `runWorker(name, context)` | Background work, returns Promise |
| `throwError`, `throwTypeError`, `throwRangeError` | Throw exceptions |
| `throwValue(val)` | Throw an existing JS value |
| `isExceptionPending()` | Check for pending exception |
| `getVersion()` | Node-API version |
| `arena` | Per-call `*ArenaAllocator`, see [Memory model](#memory-model) |

### `Ref`

A strong reference preventing garbage collection.

```zig
const ref = try env.createReference(some_val);
defer ref.delete(env) catch {};
const val = try ref.value(env);
```

## Callbacks

Accept a JS function as a parameter by using `napi.Callback`. It is validated on conversion, if the JS value is not a function, a `TypeError` is thrown.

```zig
pub fn forEach(env: napi.Env, arr: []napi.Val, callback: napi.Callback) !void {
    for (arr) |item| {
        _ = try callback.call(env, &.{item});
    }
}
```

```js
forEach([1, 2, 3], (item) => console.log(item))
// 1
// 2
// 3
```

Use `callWith` when you need a specific `this` binding:

```zig
const result = try callback.callWith(env, this_obj, &.{arg1, arg2});
```

To call a callback from a background thread, convert it to a `ThreadsafeFn` first (see [ThreadsafeFn](#threadsafefn)).

| Method | Purpose |
|---|---|
| `call(env, args)` | Call with `undefined` as `this` |
| `callWith(env, this, args)` | Call with specific `this` binding |
| `threadsafe(env, name, T)` | Create a `ThreadsafeFn(T)` for cross-thread calls |

## Memory model

Each function call receives an `Env` with a per-call `ArenaAllocator`, similar to how [Zig's juicy main](https://github.com/ziglang/zig/issues/24510) receives an arena from the runtime. Use `env.arena.allocator()` for any temporary allocations. All JS-to-Zig conversions that produce slices (`[]const u8`, `[]T`) also allocate on this arena. Everything is freed automatically when the function returns.

```zig
pub fn process(env: napi.Env, input: []const u8) ![]const u8 {
    const alloc = env.arena.allocator();
    return try std.fmt.allocPrint(alloc, "processed: {s}", .{input});
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
const result = await asyncFib(10) // 55
```

If `resolve` returns an error, the promise is rejected with the error name.

**Memory in workers:** the worker context is copied to the heap before the function returns, so arena-allocated data (like `[]const u8` from JS strings) will be dangling by the time `compute` runs. Copy what you need first:

```zig
pub fn asyncParse(env: napi.Env, source: []const u8) !napi.Val {
    const owned = try std.heap.c_allocator.dupe(u8, source);
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
startWorkers((id) => console.log("worker", id, "done"))
// worker 0 done
// worker 2 done
// worker 1 done
// worker 3 done  (order varies)
```

Use `void` for signal-only callbacks with no data: `callback.threadsafe(env, "signal", void)`.

| Method | Purpose |
|---|---|
| `call(value, mode)` | Queue a call from any thread (`.blocking` or `.non_blocking`) |
| `release()` | Release this thread's reference |
| `abort()` | Release and reject pending calls |
| `acquire()` | Register an additional thread |
| `ref(env)` / `unref(env)` | Control whether the event loop stays alive |

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

## License

MIT
