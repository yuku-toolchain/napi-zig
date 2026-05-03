# Threadsafe functions

`ThreadsafeFn(T)` lets a background thread call back into JS. Node is single-threaded, so you cannot call N-API from a spawned thread directly. `ThreadsafeFn` queues calls back to the main thread and runs them there.

Use it for **multi-call** patterns: progress events, streaming results, pub/sub. For single-result background work, use [Workers](/async/workers) instead.

## The pattern

1. Create a `ThreadsafeFn` from a `napi.Callback` with `cb.threadsafe(env, name, T)`.
2. Hand the `ThreadsafeFn` to whatever spawned threads will call into JS.
3. Each thread calls `acquire()` to register itself, then calls `call(value, mode)` whenever it wants to invoke the JS callback.
4. Each thread calls `release()` when it is done.

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

```js
addon.startWorkers((id) => console.log("worker", id, "checked in"));
// worker 0 checked in
// worker 1 checked in
// worker 2 checked in
// worker 3 checked in
```

## Reference counting

`ThreadsafeFn` lives as long as it has at least one reference. The reference count starts at 1 (held by the main thread that created it). Every additional thread that wants to call must:

- `acquire()` before it starts, to register itself.
- `release()` when it stops, to drop its reference.

When the count drops to zero, the wrapper is destroyed and the JS callback is unrooted. Forgetting to `release` keeps the JS function alive forever; double-`release` is a use-after-free.

The standard recipe (as in the example above) is `defer ts.release()` immediately after a successful `acquire()`.

## The payload type

The third argument to `cb.threadsafe(env, name, T)` is the per-call payload. The bridge converts each `T` to a JS value before invoking the callback.

| `T` value | Meaning                                               |
| --------- | ----------------------------------------------------- |
| `void`    | No argument. Callback is invoked with no parameters.  |
| `u32`     | Each call sends a `u32`. JS sees one number argument. |
| Any type  | Any [convertible Zig type](/type-conversion).         |

For struct payloads, the field-by-field walk applies as usual:

```zig
const Progress = struct { stage: []const u8, percent: u8 };
const tsfn = try cb.threadsafe(env, "progress", Progress);

try tsfn.call(.{ .stage = "parsing", .percent = 25 }, .non_blocking);
```

::: tip
For payloads with allocated memory (slices, strings), the bridge takes ownership of a copy. The thread that called `call` does not need to keep the original alive.
:::

## Call modes

`call(value, mode)` takes a `napi.ThreadsafeFn(T).Mode`:

- `.blocking` waits if the queue is full. Safe but can deadlock if the main thread is blocked too.
- `.non_blocking` returns `error.QueueFull` immediately if the queue is full. Drop the event or retry, your choice.

For low-rate signaling, `.blocking` is fine. For high-rate streams, `.non_blocking` plus a backpressure strategy is safer.

## Keeping the event loop alive

A `ThreadsafeFn` keeps the Node.js event loop alive by default. The process will not exit while a `ThreadsafeFn` exists. Use `unref(env)` to detach:

```zig
try tsfn.unref(env);
```

This is the same semantic as `setInterval(..).unref()` in Node. Use it when the threadsafe function is a watchdog or telemetry channel that should not by itself prevent shutdown.

`ref(env)` reverses it.

## Method summary

| Method              | Purpose                                                     |
| ------------------- | ----------------------------------------------------------- |
| `call(value, mode)` | Queue a call from any thread (`.blocking`/`.non_blocking`). |
| `release()`         | Release this thread's reference.                            |
| `abort()`           | Release and reject pending calls.                           |
| `acquire()`         | Register an additional thread.                              |
| `ref(env)`          | Keep the event loop alive (default).                        |
| `unref(env)`        | Allow the event loop to exit.                               |

## Signal-only callbacks

Use `void` as the payload type when the JS callback takes no arguments:

```zig
const tick = try cb.threadsafe(env, "tick", void);
try tick.call({}, .non_blocking);
```

```js
addon.onTick(() => console.log("tick"));
```
