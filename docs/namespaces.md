# Namespaces

Group related exports under a struct. Each `pub const` whose value is a struct with `pub fn` members becomes a nested JS namespace.

```zig
const napi = @import("napi-zig");

comptime { napi.module(@This()); }

pub const crypto = struct {
    pub fn hash(data: []const u8) [32]u8 {
        // ...
    }

    pub fn verify(sig: []const u8, data: []const u8) bool {
        // ...
    }
};

pub const fs = struct {
    pub fn read(path: []const u8) ![]const u8 { ... }
    pub fn write(path: []const u8, data: []const u8) !void { ... }
};
```

```js
addon.crypto.hash(buf);
addon.crypto.verify(sig, buf);
addon.fs.read("/etc/hosts");
```

## Arbitrary nesting

Namespaces nest as deeply as you want. The walker recurses through every public struct.

```zig
pub const net = struct {
    pub const http = struct {
        pub fn get(url: []const u8) ![]const u8 { ... }
        pub fn post(url: []const u8, body: []const u8) ![]const u8 { ... }
    };

    pub const ws = struct {
        pub fn connect(url: []const u8) !napi.Val { ... }
    };
};
```

```js
addon.net.http.get("https://example.com");
addon.net.ws.connect("wss://example.com");
```

## Splitting across files

Anonymous `struct {}` literals work, but in practice you will want to split into files. `@import` in Zig produces a struct, which is exactly what the walker is looking for:

```zig
// src/crypto.zig
const std = @import("std");

pub fn hash(data: []const u8) [32]u8 { ... }
pub fn verify(sig: []const u8, data: []const u8) bool { ... }
```

```zig
// src/lib.zig
const napi = @import("napi-zig");

comptime { napi.module(@This()); }

pub const crypto = @import("crypto.zig");
```

The `crypto` namespace ends up identical to the inline version.

## Constants and properties

A `pub const` that holds a JS-mappable value (number, string, enum, struct literal) becomes a JS property:

```zig
pub const VERSION = "1.0.0";
pub const MAX_SIZE: u32 = 4096;
pub const DEFAULTS = .{ .timeout = 5000, .retries = 3 };
```

```js
addon.VERSION; // "1.0.0"
addon.MAX_SIZE; // 4096
addon.DEFAULTS; // { timeout: 5000, retries: 3 }
```

If a `pub const` is a type or a value the converter cannot map, it is silently skipped. (You will not see it in the output and you will not get a comptime error for it.)
