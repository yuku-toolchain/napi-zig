# Project layout

A napi-zig project is a small Zig project plus a small Node.js project, sharing the same root.

## Files the scaffolder generates

```
my-addon/
├── build.zig              # napi_zig.addLib entry point
├── build.zig.zon          # Zig dependency lockfile
├── package.json           # name, version, engines
├── src/
│   └── lib.zig            # your addon source
├── test.mjs               # smoke test
└── .github/
    └── workflows/
        └── publish.yml    # release pipeline (OIDC, no NPM_TOKEN)
```

After `napi build`, you also get:

```
zig-out/
└── lib/
    ├── my-addon.node      # the binary you load from JS
    └── my-addon.d.ts      # generated TypeScript declarations (if .dts is set)
```

The `.node` file is the native module Node loads via `require` or `import`. The CLI also drops a `my-addon.js` re-exporter so the import path matches what users will see after publish.

## Source organization

`src/lib.zig` is the **root module**. Everything you `pub` in this file becomes a JS export. As your addon grows, split into more files and re-export:

```zig
// src/lib.zig
const std = @import("std");
const napi = @import("napi-zig");

comptime { napi.module(@This()); }

pub const crypto = @import("crypto.zig");
pub const fs = @import("fs.zig");

pub fn version() []const u8 {
    return "0.1.0";
}
```

Each `pub const` whose value is a struct with `pub fn` declarations becomes a nested JS namespace:

```js
addon.crypto.hash(buf);
addon.fs.read(path);
addon.version(); // "0.1.0"
```

See [Namespaces](/namespaces) for the full rules.

## Importing other Zig modules

If you have shared Zig code outside of `src/lib.zig` and want it to be importable as `@import("parser")`, register it as a Zig module and pass it via `.imports`:

```zig
const parser = b.addModule("parser", .{
    .root_source_file = b.path("src/parser/root.zig"),
    .target = target,
    .optimize = optimize,
});

napi_zig.addLib(b, napi_dep, .{
    .name = "my-addon",
    .root = b.path("src/lib.zig"),
    .target = target,
    .optimize = optimize,
    .imports = &.{ .{ .name = "parser", .module = parser } },
    .npm = .{ ... },
});
```

Then in your addon:

```zig
const parser = @import("parser");
```

## What ships to npm

After `napi build --release` and `napi publish`, the published structure looks like this:

```
my-addon/                  # the meta-package users install
├── package.json           # depends on each binding via optionalDependencies
├── index.js               # re-exports binding.js
├── binding.js             # platform detection + dynamic require
├── index.d.ts             # types

@myscope/binding-darwin-arm64/
├── package.json           # os: ["darwin"], cpu: ["arm64"]
└── my-addon.node

@myscope/binding-linux-x64-gnu/
├── package.json           # os: ["linux"], cpu: ["x64"], libc: ["glibc"]
└── my-addon.node

# ...one per platform
```

A user runs `npm i my-addon` and npm picks the right binding via `optionalDependencies` and the `os`, `cpu`, and `libc` fields. There is no `postinstall` script and no native build step on the consumer's machine. See [Publishing](/publishing) for the full pipeline.

`index.js` is the file users hit when they `import` the package. It is written once on the first release build and preserved after that, so it is the right place to add JS-side wrapping or helpers on top of the auto-generated `binding.js`. See [Subsequent release builds](/cross-compiling#subsequent-release-builds).
