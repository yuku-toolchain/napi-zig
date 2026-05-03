# Callback

A validated JS function handle. Accepting `napi.Callback` as a parameter throws `TypeError` automatically when the JS caller passes a non-function.

```zig
pub fn forEach(env: napi.Env, items: []napi.Val, cb: napi.Callback) !void {
    for (items, 0..) |item, i| {
        _ = try cb.call(env, .{ item, @as(u32, @intCast(i)) });
    }
}
```

## Methods

| Method                      | Returns                 | Purpose                                               |
| --------------------------- | ----------------------- | ----------------------------------------------------- |
| `call(env, args_tuple)`     | `!napi.Val`             | Call with `undefined` as `this`. Args is a Zig tuple. |
| `callWith(env, this, args)` | `!napi.Val`             | Call with a specific `this` binding.                  |
| `threadsafe(env, name, T)`  | `!napi.ThreadsafeFn(T)` | Cross-thread wrapper.                                 |

## `call(env, args)`

`args` is one of:

- A Zig tuple. Each element is auto-converted to a JS value via [type conversion](/type-conversion).
- A `[]const napi.Val` slice when you have one already built.

```zig
_ = try cb.call(env, .{ 1, "hello", true });   // tuple
_ = try cb.call(env, argv);                    // []const Val
```

The return value is the JS function's return value, as a `napi.Val`. Convert with `.to(env, T)`.

## `callWith(env, this, args)`

```zig
const result = try cb.callWith(env, target, .{42});
```

`target` is the `this` binding for the call. The args parameter follows the same rules as `call`.

## `threadsafe(env, name, T)`

```zig
const tsfn = try cb.threadsafe(env, "events", u32);
```

Wraps the callback so it can be invoked from any thread. The third argument is the per-call payload type (use `void` for signal-only callbacks). See [ThreadsafeFn](/reference/threadsafe-fn) and [Threadsafe functions guide](/async/threadsafe).

## Notes

- `Callback` is a single-call-time handle. It is valid only for the duration of the call that received it. Wrap it in a `napi.Ref` (via `env.createReference`) if you want to call it later from the same thread, or in a `napi.ThreadsafeFn` if you want to call it from another thread.
- A non-function passed where `Callback` is expected raises `TypeError: expected function, got <actual type>` before your function runs.
