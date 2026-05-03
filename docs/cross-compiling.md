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

## Subsequent release builds

The first `napi build --release` writes the full `npm/` tree. After that, only the build outputs are refreshed:

- Refreshed every build: `.node` files, `binding.js`, `index.d.ts`.
- Preserved (yours to edit): `index.js`, every `package.json`.

`index.js` is your seam over the addon. By default it re-exports `binding.js`. Use it to add JS-side wrapping, normalization, or helpers. Those edits survive every release rebuild. `binding.js` is regenerated, so do not edit it directly.

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
