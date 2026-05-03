# Val

A handle to a JS value, valid only within the current call.

```zig
pub fn show(env: napi.Env, value: napi.Val) !napi.Val {
    if (try value.isArray(env)) {
        const len = try value.getArrayLength(env);
        return env.toJs(len);
    }
    return env.toJs("not an array");
}
```

`Val` is `extern struct` so a `[]const Val` is castable to `[*]const napi_value` for direct N-API calls.

## Conversion

| Method                           | Returns | Purpose                                                |
| -------------------------------- | ------- | ------------------------------------------------------ |
| `to(env: Env, comptime T: type)` | `!T`    | Convert to any [supported Zig type](/type-conversion). |

## Type checks

| Method                                     | Returns                  | Purpose                                            |
| ------------------------------------------ | ------------------------ | -------------------------------------------------- |
| `typeOf(env)`                              | `!napi.c.napi_valuetype` | `.string`, `.number`, `.object`, `.function`, etc. |
| `strictEquals(env, other)`                 | `!bool`                  | JS `===`.                                          |
| `isArray(env)`                             | `!bool`                  |                                                    |
| `isArrayBuffer(env)`                       | `!bool`                  |                                                    |
| `isBuffer(env)`                            | `!bool`                  |                                                    |
| `isTypedArray(env)`                        | `!bool`                  |                                                    |
| `isDate(env)`                              | `!bool`                  |                                                    |
| `isPromise(env)`                           | `!bool`                  |                                                    |
| `hasNamedProperty(env, key: [:0]const u8)` | `!bool`                  | Property existence check.                          |

## Property access

| Method                                     | Returns     | Purpose                                     |
| ------------------------------------------ | ----------- | ------------------------------------------- |
| `getProperty(env, key: napi.Val)`          | `!napi.Val` | Dynamic-key get.                            |
| `setProperty(env, key, value)`             | `!void`     | Dynamic-key set.                            |
| `getNamedProperty(env, key: [:0]const u8)` | `!napi.Val` | Compile-time-key get (faster, common case). |
| `setNamedProperty(env, key, value)`        | `!void`     | Compile-time-key set.                       |

## Array access

| Method                               | Returns     | Purpose       |
| ------------------------------------ | ----------- | ------------- |
| `getElement(env, index: u32)`        | `!napi.Val` | Index get.    |
| `setElement(env, index: u32, value)` | `!void`     | Index set.    |
| `getArrayLength(env)`                | `!u32`      | Array length. |

## String access

| Method                 | Returns  | Purpose                                                          |
| ---------------------- | -------- | ---------------------------------------------------------------- |
| `getStringLength(env)` | `!usize` | UTF-8 byte length of a JS string. Does not allocate. Probe-only. |

## BigInt access

The auto-conversion path for `i54`..`i64` and `u54`..`u64` throws a `RangeError` when the source BigInt does not fit. To inspect the `lossless` flag yourself, take a `napi.Val` and use these methods:

| Method              | Returns           | Purpose                                                                            |
| ------------------- | ----------------- | ---------------------------------------------------------------------------------- |
| `getBigIntI64(env)` | `!BigIntFit(i64)` | `{ value: i64, lossless: bool }`. `lossless = false` on overflow or sign mismatch. |
| `getBigIntU64(env)` | `!BigIntFit(u64)` | `{ value: u64, lossless: bool }`. `lossless = false` if negative or `> u64::max`.  |

```zig
pub fn clamp(env: napi.Env, v: napi.Val) !i64 {
    const r = try v.getBigIntI64(env);
    if (r.lossless) return r.value;
    return if (r.value > 0) std.math.maxInt(i64) else std.math.minInt(i64);
}
```

## Buffer access

| Method                    | Returns | Purpose                                     |
| ------------------------- | ------- | ------------------------------------------- |
| `getArrayBufferData(env)` | `![]u8` | Slice into ArrayBuffer's backing memory.    |
| `getBufferData(env)`      | `![]u8` | Slice into Node.js Buffer's backing memory. |

## External and Date

| Method                 | Returns        | Purpose                     |
| ---------------------- | -------------- | --------------------------- |
| `getExternalData(env)` | `!?*anyopaque` | Unwrap an external pointer. |
| `getDateValue(env)`    | `!f64`         | Date as epoch milliseconds. |
