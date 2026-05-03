# dts

Comptime helpers for generating TypeScript declaration files. The `.dts = .auto` build option uses these internally; you do not normally call them directly.

## `napi.dts.generate(comptime Module: type)`

Returns the comptime-generated `.d.ts` string for `Module`. Walks every public declaration of `Module` (the same way `napi.module` does at runtime) and emits TypeScript that mirrors the Zig types.

```zig
const napi = @import("napi-zig");

const module = @import("./lib.zig");
const ts_source = napi.dts.generate(module);
// ts_source is a comptime []const u8.
```

What the walker does:

- `pub fn` becomes a TypeScript function signature.
- `pub const` (with a JS-mappable value) becomes a typed property.
- Nested namespaces become nested object types.
- `napi.Val` and `napi.Callback` become `unknown` and `(...args: unknown[]) => unknown` respectively.

For configuration and rules of thumb, see [TypeScript declarations](/typescript).
