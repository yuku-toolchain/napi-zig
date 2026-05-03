# Errors

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

That covers most of what you need. The rest of this page is the precise model.

## What the bridge does

When your function returns an error, the bridge:

1. Reads the error name (`@errorName(e)`).
2. Constructs a JS `Error` with that name as `.message`.
3. Throws it as the result of the JS call.

There is no automatic mapping from Zig errors to JS error subtypes (`TypeError`, `RangeError`, etc). Every error becomes a base `Error`. Type mismatches that are detected during argument conversion are an exception: those are thrown as `TypeError` by the bridge before your function ever runs.

## Throwing a specific JS error type

To throw a `TypeError` or `RangeError` from your own code, do it explicitly with `env.throw*`, then return any error to abort the call:

```zig
pub fn parse(env: napi.Env, input: []const u8) ![]const u8 {
    if (input.len == 0) {
        env.throwRangeError("input must not be empty");
        return error.InvalidArg;
    }
    // ...
}
```

The `throw*` family marks an exception as pending on the environment. Returning an error then short-circuits the bridge, which sees the pending exception and lets it propagate without overwriting it. The Zig error you return is just a way to bail out; the actual JS error is the `RangeError` you constructed.

The same applies to `env.throwError(msg)`, `env.throwTypeError(msg)`, and `env.throwValue(val)` for throwing an existing JS value.

## Catching specific N-API failures

`napi.Error` is the napi-zig error set. It covers every distinct N-API failure mode:

- `error.QueueFull`
- `error.Closing`
- `error.PendingException`
- `error.StringExpected`
- `error.NumberExpected`
- ...and so on

Use it when you want to handle a specific failure mode rather than propagate everything:

```zig
cb.call(env, .{x}) catch |e| switch (e) {
    error.QueueFull => return,        // drop the call silently
    error.Closing   => return,
    else            => return e,
};
```

The full set is documented in the [Error reference](/reference/error).

## Errors from workers and async

A worker's `resolve` function rejects the JS promise when it returns an error:

```zig
pub fn resolve(self: *FibWork, _: napi.Env) !i32 {
    if (self.n < 0) return error.InvalidInput;
    return self.result;
}
```

```js
asyncFib(-1).catch((e) => console.log(e.message)); // "InvalidInput"
```

See [Workers](/guide/async/workers) for the rest.

## What you cannot catch in JS

Zig **panics** (index out of bounds, unreachable, integer overflow in debug builds) are not Zig errors. They abort the process.

::: danger
A panic in Zig code, especially on a worker thread, crashes the entire Node.js process. Errors are values; panics are bugs. Use `if`, `try`, and explicit error returns for anything that can fail at runtime.
:::

In production builds (`ReleaseFast`, `ReleaseSmall`), undefined behavior in Zig will not panic; it will silently misbehave. Test in `Debug` and `ReleaseSafe` to catch these.
