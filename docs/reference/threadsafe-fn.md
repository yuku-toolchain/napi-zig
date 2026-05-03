# ThreadsafeFn

Thread-safe wrapper around a JS function. `T` is the per-call payload type. Built via [`Callback.threadsafe(env, name, T)`](/reference/callback#threadsafe-env-name-t).

```zig
const tsfn = try cb.threadsafe(env, "progress", u8);
```

For the conceptual model and lifecycle rules, see [Threadsafe functions](/async/threadsafe).

## `T` semantics

| `T` value       | Behavior                                                                                  |
| --------------- | ----------------------------------------------------------------------------------------- |
| `void`          | No payload. JS callback is invoked with no arguments.                                     |
| Any convertible | Each call sends a `T`. The bridge converts to JS via [type conversion](/type-conversion). |

## Methods

| Method              | Returns | Purpose                                                              |
| ------------------- | ------- | -------------------------------------------------------------------- |
| `call(value, mode)` | `!void` | Queue a call from any thread. `mode` is `.blocking`/`.non_blocking`. |
| `release()`         | `!void` | Release this thread's reference.                                     |
| `abort()`           | `!void` | Release and reject pending calls.                                    |
| `acquire()`         | `!void` | Register an additional thread.                                       |
| `ref(env)`          | `!void` | Keep the event loop alive while this exists (default).               |
| `unref(env)`        | `!void` | Allow the event loop to exit even if this exists.                    |

## `call(value, mode)`

```zig
try tsfn.call(42, .non_blocking);
```

`mode` is `napi.ThreadsafeFn(T).Mode`:

- `.blocking` waits if the queue is full.
- `.non_blocking` returns `error.QueueFull` if the queue is full.

For `T = void`, the call signature is `try tsfn.call({}, mode)`.

## Lifecycle pattern

```zig
const tsfn = try cb.threadsafe(env, "events", u32);

// each new thread:
try tsfn.acquire();
defer tsfn.release() catch {};

// when emitting:
try tsfn.call(value, .non_blocking);

// the original thread must release once at the end (it holds the
// initial refcount):
try tsfn.release();
```
