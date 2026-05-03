# Classes

Wrap a Zig struct as a JS class with `napi.class`. Methods become methods, the constructor returns a stateful instance, and the underlying memory is managed for you.

## A counter

```zig
const napi = @import("napi-zig");

comptime { napi.module(@This()); }

pub const Counter = napi.class("Counter", struct {
    value: i32,

    pub fn init(start: i32) @This() {
        return .{ .value = start };
    }

    pub fn increment(self: *@This()) i32 {
        self.value += 1;
        return self.value;
    }

    pub fn get(self: *const @This()) i32 {
        return self.value;
    }

    pub fn deinit(self: *@This()) void {
        // optional, runs when the JS instance is GC'd
        _ = self;
    }
});
```

```js
const c = new Counter(10);
c.increment(); // 11
c.increment(); // 12
c.get(); // 12
```

## Rules

| Method   | Required | Signature                                    | Purpose                                            |
| -------- | -------- | -------------------------------------------- | -------------------------------------------------- |
| `init`   | Yes      | `fn(...args) T` or `fn(env: Env, ...args) T` | Constructor. Return value seeds the instance.      |
| methods  | No       | `fn(self: *Self, ...args) R`                 | Mutating methods. May also take `env: Env` second. |
| methods  | No       | `fn(self: *const Self, ...args) R`           | Read-only methods.                                 |
| `deinit` | No       | `fn(self: *Self) void`                       | Runs when the JS instance is garbage-collected.    |

- `init` can return either `T` or `!T`. An error rejects the constructor call.
- `Env` is recognized by type. As a constructor first param or method second param, it does not consume a JS argument.
- The instance is heap-allocated once during `new` and reused across every method call. There is no per-call boxing.
- The Zig allocation is freed automatically when the JS instance is collected, whether you define `deinit` or not. Define `deinit` only if your struct holds resources you need to release (file handles, sockets, freed allocations from a long-lived allocator).

## A class that allocates

If your class holds memory that outlives a single call (string fields, slices, references), use a long-lived allocator and free in `deinit`. The per-call arena will not work because the arena resets between calls.

```zig
pub const Greeter = napi.class("Greeter", struct {
    prefix: []const u8,

    pub fn init(prefix: []const u8) !@This() {
        const owned = try std.heap.smp_allocator.dupe(u8, prefix);
        return .{ .prefix = owned };
    }

    pub fn say(self: *const @This(), env: napi.Env, name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(env.allocator(), "{s}, {s}!", .{ self.prefix, name });
    }

    pub fn deinit(self: *@This()) void {
        std.heap.smp_allocator.free(self.prefix);
    }
});
```

`init` here uses `smp_allocator` for the field that lives across calls. `say` uses the per-call arena (`env.allocator()`) because the result string is consumed by the JS bridge before the function returns and does not need to outlive it.

::: tip
The general rule: state that lives on the instance uses a long-lived allocator; scratch within a single method uses `env.allocator()`.
:::

## Why not just use `pub const`?

A `pub const` struct with `pub fn` declarations becomes a [namespace](/guide/namespaces): a static set of functions on a JS object. It has no `this`. `napi.class` is for stateful instances backed by a Zig struct, instantiated with `new`, with methods that take `*Self`.
