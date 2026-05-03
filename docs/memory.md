# Memory model

Every JS-to-Zig call hands you an `Env` carrying an arena allocator. Use `env.allocator()` for any temporary memory: strings, slices, scratch space. Everything is freed automatically when your function returns.

```zig
pub fn process(env: napi.Env, input: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "processed: {s}", .{input});
}
```

The arena is constructed at the start of each call and torn down at the end. There is no `defer arena.deinit()` to write because there is no arena variable to manage; the bridge owns it.

## How it performs

The arena's backing pages come from `std.heap.smp_allocator`, a thread-cached allocator. The arena is **lazy**: `init` only writes a few struct fields. The first `alloc` call requests a page from `smp_allocator`; subsequent allocs come from the same page. If no allocation ever happens during the call, `deinit` has nothing to free and returns immediately.

That means a function whose arguments and return value all fit in registers truly never goes near the allocator. `add(i32, i32)` does no syscall, no `smp_allocator` call, no kernel touch. Just N-API conversion and the bridge wrapper.

## What lives where

| Lifetime                                  | Allocator                         |
| ----------------------------------------- | --------------------------------- |
| Temporary within a single function call   | `env.allocator()` (the arena)     |
| Fields of a `napi.class` instance         | `std.heap.smp_allocator` or yours |
| State you pass to `env.runWorker`         | `std.heap.smp_allocator` or yours |
| Any data you cross a thread boundary with | `std.heap.smp_allocator` or yours |

::: warning
Arena memory is valid only for the duration of the call. For data that outlives the function (workers, threads, instance fields), copy to a long-lived allocator yourself.
:::

A typical pattern:

```zig
pub fn asyncParse(env: napi.Env, source: []const u8) !napi.Val {
    // `source` lives on the per-call arena and will be freed
    // when this function returns. Copy it before handing off.
    const owned = try std.heap.smp_allocator.dupe(u8, source);
    return env.runWorker("parse", ParseWork{ .source = owned });
}
```

The worker is then responsible for freeing `owned` (typically in `resolve`, after the result is read out).

## Returning data you allocated yourself

There is one footgun. `defer` fires before your function returns to the bridge, and the bridge is what serializes your return value into a JS handle. So this is **broken**:

```zig
pub fn bad(n: u32) ![]u8 {
    const buf = try std.heap.smp_allocator.alloc(u8, n);
    defer std.heap.smp_allocator.free(buf); // fires before the bridge reads `buf`
    @memset(buf, 'x');
    return buf;                              // dangling slice
}
```

Two correct patterns:

**Use the arena.** Easiest. The arena outlives the conversion step, so a slice allocated on `env.allocator()` is still valid when the bridge serializes it.

```zig
pub fn good(env: napi.Env, n: u32) ![]u8 {
    const buf = try env.allocator().alloc(u8, n);
    @memset(buf, 'x');
    return buf;
}
```

**Convert to a `Val` yourself, then free.** `env.toJs([]const u8, ...)` copies the bytes into V8 (via `napi_create_string_utf8`). Once you hold the `Val`, your source buffer is safe to free.

```zig
pub fn good(env: napi.Env, n: u32) !napi.Val {
    const buf = try std.heap.smp_allocator.alloc(u8, n);
    defer std.heap.smp_allocator.free(buf); // fires after toJs, safe
    @memset(buf, 'x');
    return env.toJs(buf);
}
```

The same applies to any owned type: structs containing slices, arrays of strings, etc. If you want to free with `defer`, return a `napi.Val` you constructed via `env.toJs` rather than the raw Zig value.

## Skipping the auto-copy for arguments

A `[]const u8` parameter triggers one arena alloc. The bridge probes the JS string's byte length, reserves exactly that, and copies the UTF-8 bytes in. That is the right default. N-API has no zero-copy path for UTF-8 strings (V8 owns the original UTF-16 representation), and the arena makes the copy free at end-of-call.

If you don't need the bytes (e.g., you only want the length, the type tag, or a `Ref` to keep around), take a `napi.Val` instead. The bridge passes the JS handle through unmodified, no probe, no alloc, no copy:

```zig
pub fn lengthOf(env: napi.Env, value: napi.Val) !u32 {
    return @intCast(try value.getStringLength(env));
}
```

Same goes for arrays and structs: `[]const T` and structs auto-decode element-by-element via the arena. A `napi.Val` parameter skips that entirely and lets you pull only what you need.
