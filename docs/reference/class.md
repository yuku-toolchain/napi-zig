# class

```zig
pub const MyClass = napi.class("MyClass", struct { ... });
```

Wrap a Zig struct as a JS class. The first argument is the JS-visible class name; the second is the Zig type.

```zig
pub const Counter = napi.class("Counter", struct {
    value: i32,

    pub fn init(start: i32) @This() {
        return .{ .value = start };
    }

    pub fn increment(self: *@This()) i32 {
        self.value += 1;
        return self.value;
    }

    pub fn deinit(self: *@This()) void {
        _ = self;
    }
});
```

```js
const c = new Counter(10);
c.increment(); // 11
```

For the conceptual model, see [Classes](/classes).

## Recognized members

| Member           | Required | Signature                                    | Purpose                                          |
| ---------------- | -------- | -------------------------------------------- | ------------------------------------------------ |
| `init`           | Yes      | `fn(...args) T` or `fn(env: Env, ...args) T` | Constructor. Returns the struct value (or `!T`). |
| Mutating method  | No       | `fn(self: *Self, ...args) R`                 | Becomes a JS method.                             |
| Read-only method | No       | `fn(self: *const Self, ...args) R`           | Becomes a JS method.                             |
| `deinit`         | No       | `fn(self: *Self) void`                       | Runs on JS GC.                                   |
| Other `pub fn`   | No       | (no `*Self` first param)                     | Skipped silently.                                |

`init` may also return `!T` to make construction fallible. `Env` is recognized in the constructor's first slot and any method's second slot, and does not consume a JS argument.

## Allocation

The instance is heap-allocated once (on `std.heap.smp_allocator`) during `new` and reused across every method call. Released automatically when JS collects the wrapper, after running `deinit` if defined.

If your fields hold long-lived allocations (strings, slices, file handles), free them in `deinit`. The arena from `env.allocator()` is per-call only and is **not** suitable for instance state.
