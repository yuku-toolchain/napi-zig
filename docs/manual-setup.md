# Manual setup

If you would rather wire up a project by hand, or you are adding napi-zig to a repo that already exists, this is the four-step path.

## 1. Add napi-zig

```sh
zig fetch --save git+https://github.com/yuku-toolchain/napi-zig.git/#HEAD
npm install -D napi-zig
```

The first command pins napi-zig as a Zig dependency in `build.zig.zon`. The second installs the `napi` CLI as a dev dependency.

## 2. Write your addon

```zig
// src/lib.zig
const std = @import("std");
const napi = @import("napi-zig");

comptime { napi.module(@This()); }

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn greet(env: napi.Env, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "Hello, {s}!", .{name});
}
```

`napi.module(@This())` walks every public declaration of the file at comptime:

| Declaration                           | Becomes               |
| ------------------------------------- | --------------------- |
| `pub fn name(...)`                    | A JS function         |
| `pub const x = <JS-mappable value>`   | A JS property         |
| `pub const x = struct { pub fn ... }` | A nested JS namespace |

Names are translated `snake_case` to `camelCase` automatically. See [Functions](/functions) for the full rules.

## 3. Configure `build.zig`

```zig
const std = @import("std");
const napi_zig = @import("napi_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    napi_zig.addLib(b, b.dependency("napi_zig", .{}), .{
        .name = "my-addon",
        .root = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .npm = .{
            .scope = "@myscope",
        },
    });
}
```

`addLib` is the only thing you need to call. It registers an artifact, sets up the right linker flags for each OS, and (when `--release` is set) generates the cross-compile graph and the npm package skeleton. See [build.zig (addLib)](/reference/build) for every option.

## 4. Build and use

```sh
napi build
```

```js
import addon from "./my-addon.js";

console.log(addon.add(2, 3)); // 5
console.log(addon.greet("world")); // "Hello, world!"
```

That's the whole setup. From here, the rest of the guide covers what you can put inside `src/lib.zig`.

## Next steps

- [Project layout](/project-layout) describes the files the scaffolder writes.
- [Functions](/functions) is the core mental model.
- [Cross-compiling](/cross-compiling) explains what `--release` actually does.
