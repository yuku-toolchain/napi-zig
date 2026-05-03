# Quick start

The fastest path to a working addon is the scaffolder. It picks up your package manager, writes a starter project, installs everything, and produces a built binary you can `import` from Node.

## Prerequisites

- [Zig](https://ziglang.org/download/) (master or any recent build).
- Node.js 18+ and a package manager (`npm`, `pnpm`, `yarn`, or `bun`).

## Scaffold

```sh
npx napi-zig@latest new my-addon
```

The CLI prompts for any missing details, then:

- Writes `build.zig`, `build.zig.zon`, and `package.json`.
- Drops a starter `src/lib.zig` with two example functions.
- Installs `napi-zig` from npm and fetches the Zig dependency.
- Adds a `.github/workflows/publish.yml` ready for trusted publishing.
- Runs an initial build so the binary is available immediately.

## Try it

```sh
cd my-addon
node test.mjs
```

```
add(2, 3) = 5
greet('world') = Hello, world!
```

That's it. You have a working native Node.js addon written in Zig.

## What the starter contains

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

```js
// test.mjs
import addon from "./my-addon.js";

console.log("add(2, 3) =", addon.add(2, 3));
console.log("greet('world') =", addon.greet("world"));
```

## The development loop

Every iteration is the same two-step:

```sh
# edit src/lib.zig, then:
napi build
node test.mjs
```

`napi build` compiles for the current host. When you are ready to ship, `napi build --release` cross-compiles every platform at once. See [Cross-compiling](/cross-compiling).

## Next steps

- [Functions](/functions) covers everything you can put after `pub fn`.
- [Type conversion](/type-conversion) is the table of which Zig types map to which JS types.
- [Project layout](/project-layout) is a one-stop map of every file in the project.
