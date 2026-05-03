# Error

`napi.Error` is the napi-zig error set. It is mapped 1:1 from N-API's `napi_status` so every distinct N-API failure mode is a distinct named error you can match.

```zig
cb.call(env, .{x}) catch |e| switch (e) {
    error.QueueFull => return,        // drop silently
    error.Closing   => return,
    else            => return e,
};
```

Use it when you want to handle a specific failure mode rather than propagate everything. For the conceptual model, see [Errors](/guide/errors).

## Common members

A non-exhaustive list of values you will see most often:

| Error                    | When                                                                     |
| ------------------------ | ------------------------------------------------------------------------ |
| `error.PendingException` | A previous call left a JS exception pending; clear it before continuing. |
| `error.QueueFull`        | `ThreadsafeFn.call(.non_blocking)` could not enqueue.                    |
| `error.Closing`          | A `ThreadsafeFn` is closing and cannot accept calls.                     |
| `error.StringExpected`   | A conversion expected a JS string and got something else.                |
| `error.NumberExpected`   | A conversion expected a JS number.                                       |
| `error.BooleanExpected`  | A conversion expected a JS boolean.                                      |
| `error.ObjectExpected`   | A conversion expected a JS object.                                       |
| `error.FunctionExpected` | A conversion expected a JS function.                                     |
| `error.ArrayExpected`    | A conversion expected a JS array.                                        |
| `error.BigintExpected`   | A conversion expected a BigInt.                                          |
| `error.DateExpected`     | A conversion expected a Date.                                            |
| `error.GenericFailure`   | An N-API call failed without a more specific code.                       |
| `error.InvalidArg`       | A call argument was invalid.                                             |
| `error.NameExpected`     | A property name was expected.                                            |

The full set is whatever N-API's `napi_status` enum contains. New variants get added as Node adds them.

## When the bridge throws an error in JS

The bridge catches every error your function returns and converts it to a JS exception (`Error` with the Zig error name as `.message`). The same applies to errors raised by argument conversion (`error.StringExpected`, etc.), which become JS `TypeError`s before your function runs.

You only `catch` napi-zig errors when you want to handle them locally rather than let the bridge propagate them.
