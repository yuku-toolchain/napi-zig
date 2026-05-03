# Type conversion

The bridge auto-converts every supported Zig type to and from a JS value. The two endpoints are:

- **`env.toJs(value)`** for Zig to JS. Used implicitly on every return value, callback argument, and field assignment.
- **`val.to(env, T)`** for JS to Zig. Used implicitly on every JS argument that is bound to a typed parameter.

You usually never call them directly. They are listed here so you know what is happening underneath, and so you can call them yourself when working with `napi.Val` directly.

## Zig to JS

| Zig type                         | JS result                                |
| -------------------------------- | ---------------------------------------- |
| `void`                           | `undefined`                              |
| `bool`                           | Boolean                                  |
| `?T`                             | inner value or `null`                    |
| `comptime_int`, `comptime_float` | Number                                   |
| `i1`..`i32`, `u1`..`u32`         | Number                                   |
| `i33`..`i53`, `u33`..`u53`       | Number (via `f64`, safe-integer range)   |
| `i54`..`i64`, `u54`..`u64`       | BigInt                                   |
| `f16`, `f32`, `f64`              | Number                                   |
| `[]const u8`, `*const [N:0]u8`   | String                                   |
| `[N]T`, `[]T`                    | Array                                    |
| `struct { S, T }` (tuple)        | Array                                    |
| `enum`                           | String (tag name, snake to camel)        |
| `struct { foo, bar }`            | Object (snake_case fields to camelCase)  |
| `napi.Val`                       | passthrough                              |
| Type with `pub fn toJs`          | custom (see [below](#custom-conversion)) |

## JS to Zig

| JS type          | Zig type                   | Notes                                        |
| ---------------- | -------------------------- | -------------------------------------------- |
| Boolean          | `bool`                     |                                              |
| Number           | `i1`..`i32`, `u1`..`u32`   |                                              |
| Number           | `i33`..`i53`, `u33`..`u53` | via `i64`/`f64`                              |
| Number           | `f16`, `f32`, `f64`        |                                              |
| BigInt           | `i54`..`i64`, `u54`..`u64` | strict, throws RangeError if lossy           |
| null / undefined | `?T` returns `null`        |                                              |
| String           | `[]const u8`               | allocated on `env.allocator()`               |
| String           | `enum`                     | accepts camelCase or snake_case              |
| Array            | `[N]T`, `[]T`              | by-index conversion                          |
| Array            | `struct { S, T }` (tuple)  | by-index conversion                          |
| Object           | `struct`                   | camelCase field matching, defaults respected |
| Function         | `napi.Callback`            | validated, throws TypeError if not callable  |
| any              | `napi.Val`                 | passthrough                                  |
| any              | Type with `pub fn fromJs`  | custom (see [below](#custom-conversion))     |

Type mismatches throw a JS `TypeError` with the actual JS type:

```
TypeError: expected number, got string
TypeError: invalid enum value for Level: 'foo'
```

A BigInt that does not fit the target Zig int throws `RangeError: bigint out of range for ...`. To handle lossy values yourself instead of erroring, take a `napi.Val` parameter and call [`getBigIntI64` / `getBigIntU64`](/reference/val#bigint-access).

## Structs

Struct fields are matched by camelCase name. Zig default values are used when the JS object omits a property:

```zig
const Options = struct {
    file_path: []const u8,
    line_count: i32,
    verbose: bool = false,
};

pub fn compile(opts: Options) !void { ... }
```

```js
compile({ filePath: "main.zig", lineCount: 100 });
// verbose defaults to false
```

This makes it cheap to add a field: bump the Zig struct, give it a default, no JS callers break.

## Enums

Enums map to and from strings.

```zig
const Level = enum { warning, error_level, info };

pub fn log(level: Level, msg: []const u8) void { ... }
```

```js
addon.log("warning", "disk almost full");
addon.log("errorLevel", "out of memory"); // camelCase also works
addon.log("info", "service started");
addon.log("invalid", "..."); // TypeError: invalid enum value
```

Both the snake_case and camelCase form of every variant is accepted on the way in. The way out is always camelCase.

## Tuples

A Zig anonymous tuple maps to a JS array, and vice versa.

```zig
pub fn pair() struct { i32, []const u8 } {
    return .{ 42, "hello" };
}
```

```js
addon.pair(); // [42, "hello"]
```

## Optionals and null

`?T` is `T | null` on the JS side. `null` on the Zig side becomes `null` in JS. `undefined` on the JS side is treated as `null` when converting to `?T`.

```zig
pub fn maybe(env: napi.Env, name: ?[]const u8) ![]const u8 {
    return name orelse "default";
}
```

```js
addon.maybe("custom"); // "custom"
addon.maybe(null); // "default"
addon.maybe(); // "default"  (undefined treated as null)
```

## Custom conversion

For types the converter cannot handle (unions, opaque handles, tagged shapes), define `toJs` and `fromJs` on the type. They take priority over the default field-by-field walk.

```zig
const Color = union(enum) {
    rgb: struct { r: u8, g: u8, b: u8 },
    hex: []const u8,

    pub fn toJs(self: Color, env: napi.Env) !napi.Val {
        return switch (self) {
            .rgb => |c| env.toJs(c),
            .hex => |s| env.toJs(s),
        };
    }

    pub fn fromJs(env: napi.Env, val: napi.Val) !Color {
        if ((try val.typeOf(env)) == .string) {
            return .{ .hex = try val.to(env, []const u8) };
        }
        return .{ .rgb = try val.to(env, struct { r: u8, g: u8, b: u8 }) };
    }
};
```

Both methods are looked up by name. Defining only one is fine; the auto-converter handles the other direction.

## Buffers and typed arrays

Buffers are intentionally not in the auto-conversion table. The converter cannot know whether you want a copy, a borrowed slice, or a typed array view. Build them explicitly:

- `env.createBuffer(len)` returns `{ .val, .data }` (a JS Buffer plus a writable `[]u8`).
- `env.createArrayBuffer(len)` does the same for `ArrayBuffer`.
- `val.getBufferData(env)` returns a `[]u8` into the existing memory.

See the [Env reference](/reference/env) for the full list.
