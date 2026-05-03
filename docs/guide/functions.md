# Functions

There is one rule for what makes a JS-visible function:

```
pub fn name([env: napi.Env,] [info: napi.CallInfo,] ...js_args) Return
```

`Env` and `CallInfo` are recognized by type and injected automatically. They never consume a JS argument. Everything else is converted from the JS arguments at the call site, and the return value is converted back.

## The progression

Three flavors of function, in order of how often you need them.

### Just values

The simplest case: take JS arguments, return a value. No environment needed.

```zig
pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```js
addon.add(2, 3); // 5
```

If your function does not allocate, throw, or call back into JS, this is all you need. `add(i32, i32)` does not even touch the allocator.

### Take an `Env`

Add `env: napi.Env` as the first parameter when you need to allocate, build complex JS values, or throw.

```zig
pub fn greet(env: napi.Env, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "Hello, {s}!", .{name});
}
```

`env.allocator()` is an arena that resets when your function returns. See [Memory model](/guide/memory).

### Take raw `CallInfo`

For variadic or dynamic-arity functions, take `info: napi.CallInfo` and pull out the arguments yourself.

```zig
pub fn sum(env: napi.Env, info: napi.CallInfo) !napi.Val {
    const args = try info.args(env, 16);
    const argc = try info.argCount(env);
    var total: f64 = 0;
    for (0..argc) |i| total += try args[i].to(env, f64);
    return env.toJs(total);
}
```

```js
addon.sum(1, 2, 3, 4); // 10
```

This is the escape hatch when the static type system cannot describe what you want.

## Returning your own JS values

For values the auto-converter cannot build (Buffers, dynamic-key objects, hand-built arrays), return `!napi.Val` and construct it yourself:

```zig
pub fn makeBuffer(env: napi.Env, size: u32) !napi.Val {
    const buf = try env.createBuffer(size);
    @memset(buf.data, 0xff);
    return buf.val;
}

pub fn getInfo(env: napi.Env) !napi.Val {
    const obj = try env.createObject();
    try obj.setNamedProperty(env, "name", try env.toJs("napi-zig"));
    try obj.setNamedProperty(env, "version", try env.toJs(1));
    return obj;
}
```

`napi.Val` is a passthrough type. Anywhere a JS value is expected (return values, callback arguments, struct fields), you can substitute a `Val` and it travels through unconverted.

## Naming

Field and function names are translated from `snake_case` to `camelCase` automatically. Both forms work in the published `.d.ts`:

```zig
pub fn read_file(path: []const u8) ![]const u8 { ... }
```

```js
addon.readFile("/etc/hosts");
```

If you want a JS-visible name that is not a valid Zig identifier, build the export manually with `env.createObject()` and `setNamedProperty`.

## What's next?

- [Namespaces](/guide/namespaces) explains how `pub const x = struct { ... }` becomes a nested object.
- [Type conversion](/guide/type-conversion) is the table of every Zig type and what it maps to in JS.
- [Errors](/guide/errors) covers throwing, rejecting, and the `napi.Error` set.
