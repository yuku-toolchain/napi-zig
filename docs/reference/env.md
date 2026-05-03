# Env

The N-API environment plus the per-call arena allocator.

```zig
const napi = @import("napi-zig");

pub fn handler(env: napi.Env) !napi.Val {
    const obj = try env.createObject();
    try obj.setNamedProperty(env, "ok", try env.toJs(true));
    return obj;
}
```

`Env` is recognized by type. As the first parameter of a top-level function, the second parameter of an `init`, or the second parameter of a class method, it does not consume a JS argument.

## Allocation

| Method        | Returns             | Purpose                                                    |
| ------------- | ------------------- | ---------------------------------------------------------- |
| `allocator()` | `std.mem.Allocator` | Per-call arena allocator. Freed when the function returns. |

See [Memory model](/memory).

## Conversion

| Method        | Returns     | Purpose                                                             |
| ------------- | ----------- | ------------------------------------------------------------------- |
| `toJs(value)` | `!napi.Val` | Convert any [convertible Zig type](/type-conversion) to a JS value. |

## Primitives

| Method                        | Returns     | JS result |
| ----------------------------- | ----------- | --------- |
| `createBoolean(v: bool)`      | `!napi.Val` | Boolean   |
| `createInt32(v: i32)`         | `!napi.Val` | Number    |
| `createUint32(v: u32)`        | `!napi.Val` | Number    |
| `createInt64(v: i64)`         | `!napi.Val` | Number    |
| `createFloat64(v: f64)`       | `!napi.Val` | Number    |
| `createBigintInt64(v: i64)`   | `!napi.Val` | BigInt    |
| `createBigintUint64(v: u64)`  | `!napi.Val` | BigInt    |
| `createString(s: []const u8)` | `!napi.Val` | String    |

## Singletons

| Method              | Returns     | JS result    |
| ------------------- | ----------- | ------------ |
| `createNull()`      | `!napi.Val` | `null`       |
| `createUndefined()` | `!napi.Val` | `undefined`  |
| `getGlobal()`       | `!napi.Val` | `globalThis` |

## Containers

| Method                                 | Returns     | Purpose                           |
| -------------------------------------- | ----------- | --------------------------------- |
| `createObject()`                       | `!napi.Val` | Empty object.                     |
| `createArray()`                        | `!napi.Val` | Empty array.                      |
| `createArrayWithLength(len: u32)`      | `!napi.Val` | Array pre-sized to `len`.         |
| `createSymbol(description: ?napi.Val)` | `!napi.Val` | Symbol with optional description. |
| `createDate(time_ms: f64)`             | `!napi.Val` | Date from epoch milliseconds.     |

## Buffers

| Method                                                | Returns        | Purpose                                                              |
| ----------------------------------------------------- | -------------- | -------------------------------------------------------------------- |
| `createArrayBuffer(len: usize)`                       | `!ArrayBuffer` | Returns `{ .val, .data }`. `data` is `[]u8` into the backing memory. |
| `createBuffer(len: usize)`                            | `!ArrayBuffer` | Same shape, but a Node.js `Buffer`.                                  |
| `createTypedArray(typ, len, ab, offset)`              | `!napi.Val`    | TypedArray view over an existing ArrayBuffer.                        |
| `createExternalArrayBuffer(ptr, len, finalize, hint)` | `!napi.Val`    | ArrayBuffer over externally-owned memory.                            |

```zig
pub const ArrayBuffer = struct {
    val: napi.Val,
    data: []u8,
};
```

## External handles

| Method                                | Returns     | Purpose                     |
| ------------------------------------- | ----------- | --------------------------- |
| `createExternal(ptr, finalize, hint)` | `!napi.Val` | Wrap an opaque Zig pointer. |

Pair with `Val.getExternalData(env)` to unwrap.

## Functions and references

| Method                                 | Returns     | Purpose                                    |
| -------------------------------------- | ----------- | ------------------------------------------ |
| `createFunction(name, callback, data)` | `!napi.Val` | Native-backed JS function.                 |
| `createReference(val: napi.Val)`       | `!napi.Ref` | Strong GC reference (prevents collection). |

## Promises and async

| Method                     | Returns     | Purpose                                |
| -------------------------- | ----------- | -------------------------------------- |
| `createPromise()`          | `!Promise`  | Returns `{ .promise, .deferred }`.     |
| `runWorker(name, context)` | `!napi.Val` | Background work, returns a JS Promise. |

```zig
pub const Promise = struct {
    promise: napi.Val,
    deferred: napi.Deferred,
};
```

See [Workers](/async/workers) and [Promises](/async/promises).

## Errors

| Method                      | Returns     | Purpose                                     |
| --------------------------- | ----------- | ------------------------------------------- |
| `throwError(msg)`           | `void`      | Throw a JS `Error`.                         |
| `throwTypeError(msg)`       | `void`      | Throw a JS `TypeError`.                     |
| `throwRangeError(msg)`      | `void`      | Throw a JS `RangeError`.                    |
| `throwValue(val: napi.Val)` | `!void`     | Throw an existing JS value.                 |
| `createError(message)`      | `!napi.Val` | Construct a JS `Error` without throwing it. |
| `isExceptionPending()`      | `bool`      | Whether an exception is currently pending.  |

After `throw*`, return any error from your function to abort. See [Errors](/errors).

## Version info

| Method             | Returns                       | Purpose                          |
| ------------------ | ----------------------------- | -------------------------------- |
| `getVersion()`     | `!u32`                        | N-API version supported by Node. |
| `getNodeVersion()` | `!*const c.napi_node_version` | Node version info.               |
