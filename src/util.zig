/// Comptime string utilities for name conversion.

/// Converts a `snake_case` identifier to a null-terminated `camelCase` string.
///
/// Used at comptime to translate Zig function / field names into JavaScript
/// convention (e.g. `my_func` -> `"myFunc"`).
pub fn snakeToCamel(comptime input: []const u8) [:0]const u8 {
    return comptime blk: {
        if (input.len == 0) break :blk &[_:0]u8{};
        const s = snakeToCamelSlice(input);
        const final = s ++ .{0};
        break :blk final[0 .. final.len - 1 :0];
    };
}

/// Converts a `snake_case` identifier to a `camelCase` string (no null terminator).
///
/// Same logic as `snakeToCamel` but returns a plain `[]const u8` for use
/// in comparisons where a sentinel is not needed.
pub fn snakeToCamelSlice(comptime input: []const u8) []const u8 {
    comptime {
        var result: []const u8 = "";
        var cap = false;
        for (input) |ch| {
            if (ch == '_') {
                cap = true;
            } else if (cap) {
                result = result ++ &[_]u8{if (ch >= 'a' and ch <= 'z') ch - 32 else ch};
                cap = false;
            } else {
                result = result ++ &[_]u8{ch};
            }
        }
        return result;
    }
}
