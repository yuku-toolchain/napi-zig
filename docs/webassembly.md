# WebAssembly

Every napi-zig addon can also be compiled to WebAssembly. The same Zig source produces a `.node` for native targets and a `.wasm` for WebAssembly. Users do not change anything: when no native binding matches their machine, the loader falls back to wasm and the addon runs anyway.

```zig
pub fn add(a: i32, b: i32) i32 { return a + b; }
```

```js
import addon from "my-addon";
addon.add(2, 3); // 5. runs natively where possible, wasm where not.
```

## Why wasm matters

A native addon only loads on platforms you cross-compiled for. Users on architectures you forgot, in environments without prebuilt binaries (StackBlitz, WebContainers, novel CI hosts), or behind sandboxes that block loading `.node` files would otherwise see a hard failure on `import`. The wasm binding is a single portable artifact that runs on any of them, so installs never break for the long tail of consumers.

## What it costs

The wasm binding adds three things to your published package:

1. A `binding-wasm32-wasi/<name>.wasm` sub-package. For a small addon that is around **13 KB** (compiled with `ReleaseSmall`).
2. Two runtime dependencies on the main package: `@emnapi/core` and `@emnapi/runtime`. They polyfill the Node-API C ABI as wasm imports.
3. A small fallback branch in `binding.js` that runs only when no native binding matches.

The native path is unaffected. Users on platforms with a prebuilt `.node` never load `@emnapi/*` and never read the `.wasm` file.

## How it works

A native addon is a shared library that exports `napi_register_module_v1`. The Node binary loads it with `dlopen`, calls that entry point, and the addon registers its functions onto `exports`.

A wasm addon does the same dance, just with a different backbone:

1. The Zig module is compiled for `wasm32-wasi` in **reactor mode** (no `_start`, just exported functions). Reactor mode means the module can be instantiated, called any number of times, and never tries to take over `main`.
2. The module exports `napi_register_wasm_v1` (the wasm equivalent of `napi_register_module_v1`), `node_api_module_get_api_version_v1`, the `__indirect_function_table`, and `malloc`/`free`.
3. The wasm imports every `napi_*` symbol from its `env` import object. Those imports are not satisfied by the JS engine. They are satisfied by [emnapi](https://github.com/toyobayashi/emnapi), a JS implementation of the Node-API C ABI. emnapi receives wasm calls like `napi_create_string_utf8(env, ptr, len, &out)`, manipulates the JS heap on the wasm's behalf, and returns through the function table.
4. At load time, the generated `binding.js` reads the `.wasm` bytes, instantiates them with `instantiateNapiModuleSync` from `@emnapi/core`, runs the registration callback, and returns the resulting exports object.

emnapi maintains the implementation. napi-zig only ships the build glue and the loader.

## What works

Most of napi-zig works in wasm without any source changes:

| Feature                              | Native | wasm32-wasi |
| ------------------------------------ | ------ | ----------- |
| Functions, classes, namespaces       | yes    | yes         |
| All scalar, struct, enum conversions | yes    | yes         |
| Strings, arrays, buffers, typedarray | yes    | yes         |
| Errors and exceptions                | yes    | yes         |
| Promises (synchronous resolve)       | yes    | yes         |
| `env.runWorker`                      | yes    | yes         |
| `cb.threadsafe(...)` from JS thread  | yes    | yes         |
| `std.Thread.spawn`                   | yes    | **no**      |
| Threadsafe fn called from a worker   | yes    | **no**      |

`env.runWorker` works because emnapi provides its own async-work pool. The `compute` and `resolve` callbacks run in the right order, and the returned promise settles like it does on native.

A `ThreadsafeFn` works as long as you only call it from the JS thread. The whole point of `ThreadsafeFn` on native is to call from a Zig-side thread, and `wasm32-wasi` (single-threaded) has no `std.Thread.spawn`, so any pattern that spawns threads from Zig will not compile for wasm. Real wasm threading (via `wasm32-wasi-threads` and shared memory) is intentionally out of scope for the minimal target shipped here.

## Default behaviour

`.wasm32_wasi` is in `Platform.defaults`. If you do nothing, every `napi build --release` produces:

```
npm/<name>/
├── package.json                          # adds @emnapi/core + @emnapi/runtime as dependencies
├── index.js
├── binding.js                            # tries .node, falls back to .wasm
├── index.d.ts
└── @<scope>/
    ├── binding-darwin-arm64/             # native
    ├── binding-linux-x64-gnu/            # native
    ├── ...                               # other natives
    └── binding-wasm32-wasi/
        └── <name>.wasm
```

The extra `binding-wasm32-wasi` subpackage publishes alongside the native ones. It has no `os` or `cpu` field, so npm installs it on every platform as a fallback (npm picks the matching native by `os`/`cpu` and the wasm by absence of those fields).

## Opting out

Drop `.wasm32_wasi` from `.platforms` if you do not want to ship a wasm fallback:

```zig
.npm = .{
    .scope = "@myscope",
    .platforms = &.{
        .linux_x64_gnu,
        .linux_arm64_gnu,
        .macos_arm64,
        .windows_x64,
    },
},
```

When wasm is not in `.platforms`, the build does not pull in `@emnapi/core` or `@emnapi/runtime`, the wasm fallback in `binding.js` becomes a dead branch (it cannot find a `.wasm` file), and your package stays dep-free.

## Wasm only

The opposite is also valid. If you want the simplicity of a single artifact and accept the speed cost, you can publish wasm only:

```zig
.platforms = &.{ .wasm32_wasi },
```

The result is one cross-platform package with no `os`/`cpu` filter. `napi install` works on every architecture, every libc, and every host that runs Node.

## Loader order

`binding.js` tries three paths in order, returning the first that succeeds:

1. The local `<scope>/binding-<os>-<arch>(-<libc>)/<name>.node` directory inside the package.
2. The published `<scope>/binding-<os>-<arch>(-<libc>)` package via `require`.
3. The wasm fallback: read `<scope>/binding-wasm32-wasi/<name>.wasm`, then load with `@emnapi/core` + `@emnapi/runtime` + `node:wasi`.

Each failure is recorded. If all three fail, the thrown error lists every cause. The wasm path is silent when no `.wasm` is published (the `findWasm` helper returns `null` and the loader keeps going).

## Output size

Wasm cross-compiles use `ReleaseSmall`, not `ReleaseFast`. For a wasm fallback, download and parse cost matter more than raw throughput, and `ReleaseSmall` plus libc dead-stripping plus `lib.link_gc_sections` typically lands a small addon under 20 KB. Native targets continue to use `ReleaseFast`.

If you need a different optimization level for wasm, edit `build.zig` directly. The default applies to the cross-compile path generated by `addNpmRelease`.

## Building wasm locally

You can build the wasm binding without a release run:

```sh
zig build -Dtarget=wasm32-wasi-musl
```

That produces `zig-out/lib/<name>.wasm`. Useful for inspecting size, disassembly, or running outside the bundled loader.

## When wasm is not enough

This integration targets **basic libraries**: pure computation, allocations, sync and async work, JS-thread threadsafe callbacks. If your addon needs:

- Real OS threads from Zig, with shared memory.
- Direct system calls beyond what WASI preview1 exposes.
- C dependencies that assume a full `libc` and a real filesystem.

then a wasm fallback will not cover you. Either keep your `.platforms` list to native-only, or drop down to a custom build with `wasm32-wasi-threads` + `@napi-rs/wasm-runtime` and wire the worker plumbing yourself. Zig's build system is up to it. This default is just the minimal, idiomatic, no-config path.
