# Ref

A strong reference to a JS value, preventing garbage collection of the wrapped value.

```zig
const ref = try env.createReference(some_val);
defer ref.delete(env) catch {};

// later:
const v = try ref.value(env);
```

Use `Ref` to hold onto a JS value across calls. Without one, `napi.Val` is valid only within the call that produced it.

## Methods

| Method        | Returns     | Purpose                                                   |
| ------------- | ----------- | --------------------------------------------------------- |
| `value(env)`  | `!napi.Val` | Resolve back to a `Val` you can read or call.             |
| `delete(env)` | `!void`     | Release the strong reference. Must be called or you leak. |

## When to use it

- Stashing a callback to invoke from a later call (without going thread-safe).
- Holding object identity for a JS handle that is associated with a Zig instance.
- Implementing custom finalization where the JS-side handle controls the Zig-side lifetime.

For cross-thread invocation, use [`ThreadsafeFn`](/reference/threadsafe-fn) instead. `Ref` is single-thread only.
