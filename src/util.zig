const std = @import("std");
const builtin = @import("builtin");

// translate zig snake_case identifiers to js camelCase at the boundary.

/// long-lived allocator used for state that outlives a single call (class
/// instances, async-work payloads, threadsafe-fn refs). picks `wasm_allocator`
/// on wasm (where smp_allocator's threading and PageAllocator's mmap aren't
/// available) and `smp_allocator` everywhere else.
pub const default_allocator: std.mem.Allocator = if (builtin.target.cpu.arch.isWasm())
    std.heap.wasm_allocator
else
    std.heap.smp_allocator;

pub fn snakeToCamel(comptime input: []const u8) [:0]const u8 {
    comptime {
        var buf: []const u8 = "";
        var cap = false;
        for (input) |ch| {
            if (ch == '_') {
                cap = true;
            } else if (cap) {
                buf = buf ++ &[_]u8{if (ch >= 'a' and ch <= 'z') ch - 32 else ch};
                cap = false;
            } else {
                buf = buf ++ &[_]u8{ch};
            }
        }
        const z = buf ++ "\x00";
        return z[0 .. z.len - 1 :0];
    }
}

const testing = std.testing;

test "single word stays unchanged" {
    try testing.expectEqualStrings("hello", comptime snakeToCamel("hello"));
}

test "two words converts to camel case" {
    try testing.expectEqualStrings("helloWorld", comptime snakeToCamel("hello_world"));
}

test "three words converts to camel case" {
    try testing.expectEqualStrings("myLongName", comptime snakeToCamel("my_long_name"));
}

test "empty string returns empty" {
    try testing.expectEqualStrings("", comptime snakeToCamel(""));
}

test "leading underscore is stripped" {
    try testing.expectEqualStrings("Hello", comptime snakeToCamel("_hello"));
}

test "consecutive underscores are collapsed" {
    try testing.expectEqualStrings("aB", comptime snakeToCamel("a__b"));
}

test "trailing underscore is stripped" {
    try testing.expectEqualStrings("hello", comptime snakeToCamel("hello_"));
}

test "uppercase letters after underscore stay uppercase" {
    try testing.expectEqualStrings("myXMLParser", comptime snakeToCamel("my_XML_parser"));
}

test "single char stays unchanged" {
    try testing.expectEqualStrings("x", comptime snakeToCamel("x"));
}

test "result is null terminated" {
    const z = comptime snakeToCamel("file_path");
    try testing.expectEqual(@as(u8, 0), z[z.len]);
}
