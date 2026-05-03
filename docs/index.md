# Introduction

napi-zig is a toolchain for writing [Node.js native addons](https://nodejs.org/api/n-api.html) in [Zig](https://ziglang.org). It provides three things:

1. A Zig library that turns ordinary `pub fn` declarations into N-API functions, with automatic conversion of arguments, return values, errors, and complex types like structs and enums.
2. A `build.zig` helper that compiles your addon for the current platform during development, and cross-compiles every platform you target during release.
3. A `napi` CLI that scaffolds new projects, bumps versions, and publishes per-platform npm packages with [trusted publishing](https://docs.npmjs.com/trusted-publishers).

The result is an addon you write as a normal Zig module, ship as a single `npm install`, and distribute as prebuilt binaries for every platform your users run on.

## Why Zig?

Zig is a small systems language with no hidden control flow and a build system that already knows how to cross-compile. With N-API, that gives you:

- No GC, no runtime, no surprise allocations.
- Cross-compilation for Linux (glibc and musl), macOS, Windows, and FreeBSD from a single machine.
- Comptime for type conversion, dispatch, and `.d.ts` generation.
- Direct C interop with the N-API headers when you need to drop down.

## Example

```zig
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
import addon from "./my-addon.js";

addon.add(2, 3); // 5
addon.greet("world"); // "Hello, world!"
```

The line `comptime { napi.module(@This()); }` registers every public declaration in the file. Functions become JS functions, constants become JS properties, nested structs become nested namespaces.

## Compared to napi-rs

[napi-rs](https://napi.rs) does the same thing for Rust. napi-zig follows the same shape (one source, prebuilt platform binaries, an npm meta-package, OIDC publish) with these differences:

- The Zig build system is already cross-compile aware, so there is no `cargo zigbuild` equivalent to install.
- Comptime replaces procedural macros. There is no `#[napi]` attribute; a function is exported because it is `pub`.
- Errors are values, not panics. Returning `error.X` rejects a promise or throws an exception automatically.

## Next steps

- [Quick start](/quick-start) scaffolds a working addon in one command.
- [Manual setup](/manual-setup) wires it up step by step.
- [Functions](/functions) covers the core concept that explains most of the library.
