# Callbacks

Accept a JS function as a parameter using `napi.Callback`. The argument is validated on conversion: passing a non-function throws `TypeError` before your code runs.

```zig
pub fn forEach(env: napi.Env, items: []napi.Val, cb: napi.Callback) !void {
    for (items, 0..) |item, i| {
        _ = try cb.call(env, .{ item, @as(u32, @intCast(i)) });
    }
}
```

```js
addon.forEach([10, 20, 30], (item, i) => console.log(i, item));
// 0 10
// 1 20
// 2 30
```

## `call(env, args_tuple)`

`call`'s second argument is a Zig **tuple**. Each element is auto-converted to JS. The call uses `undefined` as `this`.

```zig
_ = try cb.call(env, .{ 1, "hello", true });
```

You can also pass a `[]const Val` slice when you have one already built:

```zig
const argv: []const napi.Val = ...;
_ = try cb.call(env, argv);
```

The return value of `call` is a `napi.Val`. Convert it to a Zig type with `.to(env, T)`:

```zig
const result = try cb.call(env, .{42});
const n = try result.to(env, i32);
```

## `callWith(env, this, args)`

For a specific `this` binding:

```zig
pub fn invokeOn(env: napi.Env, target: napi.Val, cb: napi.Callback) !napi.Val {
    return cb.callWith(env, target, .{});
}
```

```js
addon.invokeOn(obj, function () {
  return this.x;
});
```

## Cross-thread: `threadsafe(env, name, T)`

Calling `cb.call` from a non-main thread crashes Node. To call back into JS from a worker thread, wrap the callback as a [ThreadsafeFn](/async/threadsafe):

```zig
const tsfn = try cb.threadsafe(env, "events", u32);
```

The third argument is the per-call payload type. Use `void` for signal-only callbacks. See [Threadsafe functions](/async/threadsafe) for the full pattern.

## Method summary

| Method                      | Purpose                                                      |
| --------------------------- | ------------------------------------------------------------ |
| `call(env, args_tuple)`     | Call with `undefined` as `this`. Args is a tuple.            |
| `callWith(env, this, args)` | Call with a specific `this` binding.                         |
| `threadsafe(env, name, T)`  | Cross-thread wrapper. See [ThreadsafeFn](/async/threadsafe). |
