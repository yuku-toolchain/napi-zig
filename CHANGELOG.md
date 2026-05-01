# Changelog

## Unreleased

This release is a substantial rewrite of the runtime, build system, and CLI based on a top-to-bottom design review. Many APIs are renamed; minor edits are required to upgrade.

### Added

- **Classes**, `napi.class("Name", T)` wraps a Zig struct as a JS class. `init` is the constructor, `pub fn method(self: *Self, ...)` becomes a method, optional `deinit` runs on GC. Methods can take `Env` as their second parameter.
- **Symbol-export limiting on Linux/FreeBSD** via `build/exports.ld`, only `napi_register_module_v1` and `node_api_module_get_api_version_v1` are visible. Smaller binaries; no symbol collisions when multiple addons share a process.
- **`link_gc_sections`** enabled by default, drops unreferenced sections.
- **Nested namespaces**, `pub const ns = struct { pub fn ... };` becomes `addon.ns.fn(...)`. Nests arbitrarily deep.
- **`.d.ts` generation**, three modes: `.{ .file = path }` (recommended for published libraries), `.auto` (comptime walk for prototypes / internal addons), `.none` (default).
- **`napi.Error`**, full N-API error set with one named variant per `napi_status`. Use it to handle specific failures (`error.QueueFull`, `error.PendingException`, etc).
- **Thread-local arena pool**, `env.allocator()` is backed by a per-thread arena that resets between calls instead of being re-mmapped. Calls that don't allocate pay zero syscalls; first call on a thread allocates once.
- **`env.allocator()`** shorthand for `env.arena.allocator()`.
- **Tuple callback args**, `cb.call(env, .{ "hi", 42, true })` auto-converts mixed Zig values. `[]const Val` slices still work for dynamic cases.
- **`host_exe` build option**, set to `"electron.exe"` etc. for non-Node hosts on Windows.
- **Symbols / Dates / Externals / strict equals / instanceof**, full N-API surface now wrapped.
- **Example addon**, `example/` exercises every major capability end-to-end. Run `bun run test:example` to build and verify it.
- **`Env.createError(message)`**, construct a JS `Error` without throwing it. Used internally so worker rejections carry a real `Error` (consumers see `e.message`); useful from user code for the same reason.

### Changed

- **`raw` → `handle`** on `Env`, `Val`, `Ref`, `Deferred`, `CallInfo`, `ThreadsafeFn`. Signals "opaque, don't poke."
- **Function bridging is one rule, not three modes**, optionally accept `Env` first, optionally accept `CallInfo` second; everything else is JS args. Documentation reframed accordingly.
- **`runWorker` now uses `errdefer`** for cleanup, failed promise creation no longer leaks the work handle, the state struct, or strands the deferred.
- **`info.getArgs`/`getArgCount`/`getThis` → `info.args`/`argCount`/`this`** (shorter, more idiomatic).
- **N-API version pinned to 8** (was 4), enables newer features.
- **Struct decoding does one `napi_get_named_property` per field** instead of `has` + `get`. Half the round-trips.
- **`info.args` skips creating the `undefined` placeholder** when all slots are filled.

### Fixed

- `runWorker` no longer leaks the worker state or async-work handle on partial-construction failure.
- `expect()` formatting now correctly returns `[*:0]const u8` on the fallback path (Zig 0.17 type compatibility).

### CLI

- `napi bump` now uses `git push --follow-tags`, branch + annotated tag in a single round-trip.

### Internal

- Targets Zig 0.17. `dts_emit.zig` uses the new `main(init: std.process.Init)` signature, `std.Io.File.stderr().writeStreamingAll`, and `std.Io.Dir.cwd().writeFile`.
- Bumped `build.zig.zon` to `0.2.0`, minimum Zig `0.17.0`.
- All three callback bridges (top-level fn, class constructor, class method) share `bridge.buildArgs` / `bridge.returnValue`, one place to fix bugs, ~80 lines of duplication eliminated.
- `dts.zig` shares `paramList` / `returnTs` between `emitFn` and `emitClass`.

### Breaking

- `Env.raw`, `Val.raw`, etc. → `.handle`
- `napi.error.napi_error` → real `napi.Error.X` variants
- `cb.call(env, &.{a, b})` → `cb.call(env, .{ a, b })` (Val slices still accepted)
- `info.getArgs` → `info.args`, `info.getArgCount` → `info.argCount`, `info.getThis` → `info.this`
- `.dts = b.path("...")` → `.dts = .{ .file = b.path("...") }`. **Default is now `.none`**, opt in to `.auto` for prototypes or `.{ .file = ... }` for published libraries. (See [TypeScript declarations](README.md#typescript-declarations).)
