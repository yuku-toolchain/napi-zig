# Cross-compiling

```sh
napi-zig build --release
```

That single command builds your addon for every platform listed in `.npm.platforms` and lays out the npm package structure ready to publish. Zig's cross-compilation is built in: there are no toolchains to install, no Docker images, no QEMU.

The same command is also safe to run repeatedly. The build owns and reconciles the files it generates; anything you've added or edited (your seam over the addon, user fields on the main `package.json`, the version, files unrelated to the build) is preserved.

## Output layout

The first `napi-zig build --release` writes a complete `npm/` tree:

```
npm/<name>/
├── package.json              # main package
├── index.js                  # your seam over the addon
├── binding.js                # platform detection + dynamic require
├── index.d.ts                # auto-generated or your hand-written file
└── <scope>/
    ├── binding-darwin-arm64/
    │   ├── package.json
    │   └── <name>.node
    ├── binding-linux-x64-gnu/
    │   └── ...
    └── ...                   # one binding per platform
```

`<name>` is your addon's name. `<scope>` is the npm scope from the `.scope` field of the `.npm` block in `build.zig`. Every per-platform binding lives under that scope.

Calling `addLib` more than once in `build.zig` is supported; each addon gets its own `npm/<name>/` subtree and is reconciled independently. See [Multiple addons in one repo](/publishing#multiple-addons-in-one-repo).

## What every release build does

`napi-zig build --release` is the only command you need during release. It cross-compiles, then reconciles `npm/` against the policy in `build.zig`. Re-run it as often as you like; you cannot drift `npm/` out of sync with `build.zig`.

The reconciler is conservative about your work:

| File or directory                    | Behavior on every release build                                                                                                                |
| ------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- |
| `<name>.node` (each platform)        | Refreshed.                                                                                                                                     |
| `binding.js`                         | Refreshed.                                                                                                                                     |
| `index.d.ts`                         | Refreshed when `.dts` is `.auto` or `.{ .file = … }`.                                                                                          |
| `package.json` (main, policy fields) | Refreshed: `name`, `type`, `main`, `types`, `optionalDependencies`. The keys of `optionalDependencies` track `.platforms`.                     |
| `package.json` (main, `files`)       | Merged: the canonical entries (`index.js`, `binding.js`, `index.d.ts`) are always present; any extras you add (e.g. `assets/`) are preserved.  |
| `package.json` (main, user fields)   | Preserved: `description`, `repository`, `homepage`, `keywords`, `author`, `bugs`, `funding`, `engines`, `scripts`, anything else you've added. |
| `package.json` (main, version)       | Preserved. Only `napi-zig bump` changes it. The bindings' `optionalDependencies` values are kept in lockstep with this version.                |
| `package.json` (per-binding)         | Refreshed: `name`, `os`, `cpu`, `libc`, `main`, `files`. `version` is pinned to the main package's `version`.                                  |
| `<scope>/binding-*/`                 | Recreated to match `.platforms`. Bindings for removed platforms are deleted; bindings for newly added platforms are created.                   |
| `<scope>/`                           | Renames cleanly. If you change `.scope` in `build.zig`, the old scope dir is removed on the next build and the new one takes its place.        |
| `index.js`                           | Seeded once on the first release build, then preserved. Your seam: edit it freely.                                                             |
| Anything else under `npm/<name>/`    | Preserved. Add `CHANGELOG.md`, `.npmignore`, etc.; the build will not touch them.                                                              |

The practical guarantee: **edit `build.zig`, then re-run `napi-zig build --release`.** That works for every change, including renaming the scope, adding or removing platforms, changing `.dts`, and renaming `.host_exe`. You do not need to delete `npm/` first; the reconciler does the right thing.

The one exception is renaming the addon's `.name` itself. The new tree is created fresh under `npm/<new-name>/`, the old `npm/<old-name>/` becomes an orphan, and the build prints a warning that asks you to copy any user fields you want to keep on the new main `package.json` and delete the old folder. (Renaming a published npm package is a rare and disruptive event; this is intentional.)

## What `index.js` is for

`binding.js` is fully owned by the build. It implements platform detection and loads the matching `<scope>/binding-…` package. Do not edit it; your changes will be overwritten on the next build.

`index.js` is your seam. The default `napi-zig build --release` writes is a plain re-export:

```js
import binding from "./binding.js";
export default binding;
```

That is already a working entry point. Keep it as-is, or use it for JS-side wrapping, normalization, or higher-level helpers. Edits to `index.js` survive every rebuild.

## Default platforms

If `.platforms` is omitted from `.npm`, you get this set:

| OS      | Architectures   | libc           |
| ------- | --------------- | -------------- |
| Linux   | x64, arm64, arm | glibc and musl |
| macOS   | x64, arm64      | n/a            |
| Windows | x64, arm64      | n/a            |
| FreeBSD | x64             | n/a            |

That is 11 binaries from one `napi-zig build --release` call.

## Custom platforms

Override the default list to ship only what you need:

```zig
napi_zig.addLib(b, napi_dep, .{
    // ...
    .npm = .{
        .scope = "@myscope",
        .platforms = &.{
            .linux_x64_gnu,
            .macos_arm64,
        },
    },
});
```

Adding or removing entries from `.platforms` is a regular edit. The next `napi-zig build --release` adds bindings for the new entries and deletes bindings for ones you took out. The full list of `Platform` values is in [build.zig (addLib)](/reference/build).

## Electron and other hosts

By default, addons are compiled to load into `node.exe` on Windows. To target Electron, set `.host_exe`:

```zig
napi_zig.addLib(b, napi_dep, .{
    // ...
    .host_exe = "electron.exe",
});
```

This only affects Windows import-library generation. On macOS and Linux the addon loads into whatever process imports it without any host-specific configuration.

## Optimization

`napi-zig build --release` uses `ReleaseFast` for every cross-compiled binary. For development, `napi-zig build` uses whatever `-Doptimize` you specify (default `Debug`). Override the release mode with:

```sh
napi-zig build --release --optimize=safe    # ReleaseSafe
napi-zig build --release --optimize=small   # ReleaseSmall
```
