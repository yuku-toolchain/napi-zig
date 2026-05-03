# Deferred

A single-use handle for resolving or rejecting a JS Promise. Obtained from `env.createPromise()` or held by a worker until its `resolve` runs.

```zig
const p = try env.createPromise();
try p.deferred.resolve(env, try env.toJs(42));
return p.promise;
```

## Methods

| Method                          | Returns | Purpose                                 |
| ------------------------------- | ------- | --------------------------------------- |
| `resolve(env, value: napi.Val)` | `!void` | Settle the promise with a value.        |
| `reject(env, value: napi.Val)`  | `!void` | Settle the promise with an error value. |

::: warning
Each `Deferred` handle is single-use. Calling `resolve` or `reject` more than once on the same handle is undefined behavior.
:::

To reject with a JS `Error`:

```zig
const err = try env.createError("operation failed");
try p.deferred.reject(env, err);
```

See [Promises](/async/promises) for the full pattern.
