# Memory model

Every JS-to-Zig call hands you an `Env` carrying an arena allocator. Use `env.allocator()` for any temporary memory: strings, slices, scratch space. Everything is freed automatically when your function returns.

```zig
pub fn process(env: napi.Env, input: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "processed: {s}", .{input});
}
```

The arena is constructed at the start of each call and torn down at the end. There is no `defer arena.deinit()` to write because there is no arena variable to manage; the bridge owns it.

## How it performs

The arena's backing pages come from `std.heap.smp_allocator`, a thread-cached allocator. When the arena tears down, freed pages stay on the thread's freelist for the next call to reuse, so the hot path does not hit the kernel.

Calls that do not allocate pay nothing. `add(i32, i32)` never goes near the allocator.

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

## What about `std.heap.GeneralPurposeAllocator`?

Use it for development if you want allocation tracking. For production, prefer `smp_allocator` for shared state and let the per-call arena handle scratch. The arena is faster than a GPA for the common case (allocate a few small things, throw it all away) and avoids the bookkeeping cost.

## What about `defer`?

`defer` works exactly the way it does in regular Zig. The bridge does not change anything about Zig's control flow; it only constructs the arena, calls your function, and then tears down. If you allocate from a long-lived allocator inside a function, free it with `defer` as you would in any Zig code.
