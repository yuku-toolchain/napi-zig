# Cross-compiling

```sh
napi build --release
```

That single command builds your addon for every platform listed in `.npm.platforms` and lays out the npm package structure ready to publish. Zig's cross-compilation is built in: there are no toolchains to install, no Docker images, no QEMU.

## What gets generated

```
npm/my-addon/
├── package.json              # main package with optionalDependencies
├── index.js                  # re-exports the binding
├── binding.js                # platform detection + dynamic require
├── index.d.ts                # auto-generated or your hand-written file
└── @myscope/
    ├── binding-darwin-arm64/
    │   ├── package.json
    │   └── my-addon.node
    ├── binding-linux-x64-gnu/
    │   ├── package.json
    │   └── my-addon.node
    ├── binding-linux-x64-musl/
    │   ...
```

Each `binding-*` directory becomes its own npm package, gated by `os`, `cpu`, and `libc` so npm only installs the binary that matches the user's machine.

## Default platforms

If you do not specify `.platforms`, you get this set:

| OS      | Architectures   | libc           |
| ------- | --------------- | -------------- |
| Linux   | x64, arm64, arm | glibc and musl |
| macOS   | x64, arm64      | n/a            |
| Windows | x64, arm64      | n/a            |
| FreeBSD | x64             | n/a            |

That is 11 binaries from one `napi build --release` call.

## Custom platforms

Override the default list to ship only what you need:

```zig
const napi_zig = @import("napi_zig");

napi_zig.addLib(b, napi_dep, .{
    // ...
    .npm = .{
        .scope = "@myscope",
        .repository = .{ .url = "https://github.com/myorg/myrepo" },
        .platforms = &.{
            .linux_x64_gnu,
            .darwin_arm64,
        },
    },
});
```

The full list of `Platform` values is in [build.zig (addLib) reference](/reference/build).

## Electron and other hosts

By default, addons are compiled to load into `node.exe` on Windows. To target Electron, set `.host_exe`:

```zig
napi_zig.addLib(b, napi_dep, .{
    // ...
    .host_exe = "electron.exe",
});
```

This only affects Windows import-library generation. On macOS and Linux, the addon loads into whatever process imports it without any host-specific configuration.

## Optimization

`napi build --release` uses `ReleaseFast` for every cross-compiled binary. For development, `napi build` uses whatever `-Doptimize` you specify (default `Debug`).
