# Promises

For Promises that do not need a background thread, build them directly. Useful for adapting an existing async source (a Zig event loop, a callback-based API, a synchronous result you want to defer) into a JS Promise.

```zig
pub fn delayed(env: napi.Env) !napi.Val {
    const p = try env.createPromise();
    try p.deferred.resolve(env, try env.toJs(42));
    return p.promise;
}
```

```js
await addon.delayed(); // 42
```

`createPromise` returns a `Promise` struct with two fields:

- **`promise`** is the `napi.Val` you return from your function.
- **`deferred`** is the handle you use to settle the promise.

```zig
pub const Promise = struct {
    promise: Val,
    deferred: Deferred,
};
```

## Resolving and rejecting

`Deferred` has two methods, both single-use:

| Method              | Purpose                                   |
| ------------------- | ----------------------------------------- |
| `resolve(env, val)` | Settle the promise with a JS value.       |
| `reject(env, val)`  | Settle the promise with a JS error value. |

After either is called, the deferred handle is consumed. Calling either method again is undefined behavior.

To reject with a JS `Error` value:

```zig
const err = try env.createError("operation failed");
try p.deferred.reject(env, err);
```

`env.createError` builds a JS Error without throwing it.

## Using a callback to settle later

The deferred handle can be stashed somewhere and resolved later, for example from a callback or a different function call:

```zig
var pending: ?napi.Deferred = null;

pub fn start(env: napi.Env) !napi.Val {
    const p = try env.createPromise();
    pending = p.deferred;
    return p.promise;
}

pub fn finish(env: napi.Env, value: i32) !void {
    const d = pending orelse return error.NotStarted;
    pending = null;
    try d.resolve(env, try env.toJs(value));
}
```

```js
const p = addon.start();
addon.finish(42);
await p; // 42
```

::: warning
A `Deferred` is just a handle. It does not by itself keep the JS event loop alive. If your only references to the promise are inside Zig and JS has dropped the original, the resolved value will be visible to no one. Make sure JS is still holding the promise (or you are using a callback chain that does).
:::

## When to use this vs `runWorker`

- **`runWorker`**: there is real work to do on a background thread. The result of that work resolves the promise.
- **`createPromise`**: there is no extra thread needed. You just want to return a promise that will be settled later, possibly from another N-API call.
