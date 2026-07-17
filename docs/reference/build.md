# build.zig (addLib)

`napi_zig.addLib` is the only `build.zig` API you need. It registers your addon as a Zig artifact, applies the right linker flags for each OS, sets up the `.d.ts` install, and (with `-Dnpm=true`) builds the cross-compile graph and generates the npm package skeleton.

You can call it more than once in the same `build.zig` to ship multiple addons from one repo. Each call writes its own `zig-out/lib/<name>.node` and its own `bindings/<name>/` tree, and the CLI (`napi-zig build`, `napi-zig build --release`, `napi-zig bump`, `napi-zig publish`, `napi-zig npm-init`) picks up every one. Give each addon its own `.scope`; per-platform binding package names are derived from the scope, so two addons sharing a scope would publish under the same binding names.

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

## `LibOptions`

| Option      | Required | Type             | Description                                                             |
| ----------- | -------- | ---------------- | ----------------------------------------------------------------------- |
| `.name`     | Yes      | `[]const u8`     | Package name. Used for the `.node` binary and the npm package.          |
| `.root`     | Yes      | `LazyPath`       | Path to the root Zig source file (`src/lib.zig`).                       |
| `.target`   | Yes      | `ResolvedTarget` | Build target. Use `b.standardTargetOptions`.                            |
| `.optimize` | Yes      | `OptimizeMode`   | Optimization mode. Use `b.standardOptimizeOption`.                      |
| `.imports`  | No       | `[]const Import` | Additional Zig modules to import.                                       |
| `.npm`      | No       | `?NpmConfig`     | npm package config. Required for cross-compile + publish.               |
| `.host_exe` | No       | `[]const u8`     | Windows host binary (default `"node.exe"`, use `"electron.exe"`, etc.). |

## `Import`

```zig
pub const Import = struct {
    name: []const u8,
    module: *std.Build.Module,
};
```

Pass via `.imports = &.{ .{ .name = "parser", .module = parser } }`. See [Project layout: importing other Zig modules](/project-layout#importing-other-zig-modules).

## `NpmConfig`

| Option         | Default             | Description                                                              |
| -------------- | ------------------- | ------------------------------------------------------------------------ |
| `.scope`       | required            | npm scope (e.g. `"@myscope"`).                                           |
| `.description` | `""`                | Package description.                                                     |
| `.license`     | `"MIT"`             | License identifier.                                                      |
| `.repository`  | `""`                | Git repository (`"owner/repo"` shorthand or a full URL). See below.      |
| `.dts`         | `.none`             | `.{ .file = path }`, `.auto`, or `.none`. See [TypeScript](/typescript). |
| `.platforms`   | `Platform.defaults` | Cross-compilation targets.                                               |

### `.repository`

npm requires a `repository` field on every published package for [provenance](https://docs.npmjs.com/generating-provenance-statements/) to verify against the source tree, otherwise `napi-zig publish` fails in CI with "package must specify a repository". An addon ships as the main package plus one binding per platform (twelve `package.json` files with the default platform set), and setting `.repository` once in `build.zig` writes the field into every one of them on each release build, so you never have to keep them in sync by hand.

Two accepted forms:

```zig
.repository = "yuku-toolchain/napi-zig",                       // GitHub shorthand
.repository = "git+https://github.com/yuku-toolchain/napi-zig.git", // explicit URL
```

The shorthand expands to `git+https://github.com/owner/repo.git`. Anything starting with `http://`, `https://`, `git+`, `git@`, or `ssh://` is passed through unchanged so non-GitHub hosts work too. If `.repository` is empty, no field is emitted and any value already in the existing `package.json` is preserved.

## `Dts`

```zig
pub const Dts = union(enum) {
    none,
    auto,
    file: std.Build.LazyPath,
};
```

See [TypeScript declarations](/typescript) for what each mode produces.

## `Platform`

A tagged enum of every supported (OS, architecture, libc) tuple. Used in `.npm.platforms`. Defaults are exposed as `Platform.defaults`:

| Platform value          | OS      | Arch  | libc  |
| ----------------------- | ------- | ----- | ----- |
| `.linux_x64_gnu`        | Linux   | x64   | glibc |
| `.linux_x64_musl`       | Linux   | x64   | musl  |
| `.linux_arm64_gnu`      | Linux   | arm64 | glibc |
| `.linux_arm64_musl`     | Linux   | arm64 | musl  |
| `.linux_arm_gnueabihf`  | Linux   | arm   | glibc |
| `.linux_arm_musleabihf` | Linux   | arm   | musl  |
| `.darwin_x64`           | macOS   | x64   | n/a   |
| `.darwin_arm64`         | macOS   | arm64 | n/a   |
| `.win32_x64_msvc`       | Windows | x64   | n/a   |
| `.win32_arm64_msvc`     | Windows | arm64 | n/a   |
| `.freebsd_x64`          | FreeBSD | x64   | n/a   |

Override the default set with:

```zig
.platforms = &.{ .linux_x64_gnu, .darwin_arm64 },
```

## What `addLib` does

1. Creates a Zig module from `.root` and adds the `napi-zig` import.
2. Adds any `.imports` to the module.
3. Builds a dynamic library named `<name>.node`.
4. Configures linker flags per OS:
   - macOS: `linker_allow_shlib_undefined = true`.
   - Linux/FreeBSD: links libc, restricts exports to N-API entry points via `exports.ld`.
   - Windows: generates an import library from `node_api.def` so the linker resolves N-API symbols against the host `.exe` at runtime.
5. Drops red zone, unwind tables, and unreferenced sections (smaller binaries, no surprise symbols).
6. If `.npm` is set, installs the `.d.ts` next to the binary in the right format.
7. If both `.npm` is set and `-Dnpm=true` is passed, generates the full cross-compile graph and the `bindings/` package tree.

`napi-zig build --release` is exactly `zig build -Dnpm=true -Doptimize=ReleaseFast` with the per-platform target loop applied to every entry in `.npm.platforms`. You can run it directly if you prefer.

Two build options narrow that loop, set for you by the matching CLI flags:

| Build option      | CLI flag     | Effect                                                        |
| ----------------- | ------------ | ------------------------------------------------------------- |
| `-Dnpm-only=a,b`  | `--only a,b` | Only run the npm release for addons whose `.name` is listed.  |
| `-Dnpm-host=true` | `--current`  | Cross-compile only the host platform instead of `.platforms`. |

Under `-Dnpm-host` the main `package.json` still lists every platform in `optionalDependencies`, so a later full build stays complete. See [Building a subset](/cross-compiling#building-a-subset).
