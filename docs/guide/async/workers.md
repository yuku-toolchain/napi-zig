# Workers

`env.runWorker` offloads CPU work to a background thread and returns a JS Promise. It is the right tool for **single-result** async work: parsing, hashing, image processing, anything that takes long enough to block the main thread.

For multi-call async patterns (progress events, streaming), use a [ThreadsafeFn](/guide/async/threadsafe) instead.

## The pattern

Define a struct with two methods:

- **`compute(*Self) void`** runs on the worker thread. No JS access here. Treat it like any other Zig function.
- **`resolve(*Self, Env) !T`** runs on the main thread. The return value (or error) becomes the promise result. `T` may be any convertible Zig type, `napi.Val`, or `void`.

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

The first argument to `runWorker` is a name shown in the Node async hooks API. The second is the context struct that will be copied to the heap and passed to `compute` and `resolve`.

## Errors

If `resolve` returns an error, the Promise rejects with a real JS `Error` whose `.message` is the Zig error name:

```zig
pub fn resolve(self: *FibWork, _: napi.Env) !i32 {
    if (self.n < 0) return error.InvalidInput;
    return self.result;
}
```

```js
asyncFib(-1).catch((e) => console.log(e.message)); // "InvalidInput"
```

`compute` itself does not return a value, so to surface a "computation failed" outcome, store state on `self` and check it from `resolve`:

```zig
const ParseWork = struct {
    source: []const u8,
    failed: bool = false,
    result: []const u8 = "",

    pub fn compute(self: *ParseWork) void {
        const r = doParse(self.source) catch {
            self.failed = true;
            return;
        };
        self.result = r;
    }

    pub fn resolve(self: *ParseWork, _: napi.Env) ![]const u8 {
        if (self.failed) return error.ParseFailed;
        return self.result;
    }
};
```

::: danger
A panic in `compute` (index out of bounds, unreachable, integer overflow) crashes the entire Node.js process. There is no way to recover from a panic on a worker thread. Use error returns for anything that can fail.
:::

## Memory across the thread boundary

The worker context is copied to the heap before `runWorker` returns. Anything you put in it must outlive the function that called `runWorker`. Arena memory (strings from JS, allocations from `env.allocator()`) will be **dangling** by the time `compute` runs.

Copy what you need first:

```zig
pub fn asyncParse(env: napi.Env, source: []const u8) !napi.Val {
    const owned = try std.heap.smp_allocator.dupe(u8, source);
    return env.runWorker("parse", ParseWork{ .source = owned });
}
```

The convention is for `compute` or `resolve` to free the long-lived allocation when it is done with it. The bridge frees the context wrapper itself.

## Returning JS values directly

If you want `resolve` to return a hand-built `napi.Val` instead of a typed Zig value (for Buffers, dynamic-key objects, anything outside the [conversion table](/guide/type-conversion)):

```zig
pub fn resolve(self: *Work, env: napi.Env) !napi.Val {
    const obj = try env.createObject();
    try obj.setNamedProperty(env, "data", try env.toJs(self.bytes));
    return obj;
}
```

`Val` is a recognized return type. The bridge passes it through unconverted.

## When not to use a worker

- **Synchronous work that completes in microseconds.** The thread hop has its own cost. Just compute on the main thread.
- **Multi-call patterns.** Progress events, streaming, anything where the worker pushes more than one value. Use [ThreadsafeFn](/guide/async/threadsafe).
- **I/O-bound work.** If the work spends its time waiting for the kernel, use Node's existing async I/O instead of pinning a thread.
