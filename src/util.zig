pub fn snakeToCamel(comptime input: []const u8) [:0]const u8 {
    return comptime blk: {
        if (input.len == 0) break :blk &[_:0]u8{};
        const s = snakeToCamelSlice(input);
        const final = s ++ .{0};
        break :blk final[0 .. final.len - 1 :0];
    };
}

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

const testing = @import("std").testing;

test "single word stays unchanged" {
    try testing.expectEqualStrings("hello", comptime snakeToCamelSlice("hello"));
}

test "two words converts to camel case" {
    try testing.expectEqualStrings("helloWorld", comptime snakeToCamelSlice("hello_world"));
}

test "three words converts to camel case" {
    try testing.expectEqualStrings("myLongName", comptime snakeToCamelSlice("my_long_name"));
}

test "empty string returns empty" {
    try testing.expectEqualStrings("", comptime snakeToCamelSlice(""));
}

test "leading underscore is stripped" {
    try testing.expectEqualStrings("Hello", comptime snakeToCamelSlice("_hello"));
}

test "consecutive underscores are collapsed" {
    try testing.expectEqualStrings("aB", comptime snakeToCamelSlice("a__b"));
}

test "trailing underscore is stripped" {
    try testing.expectEqualStrings("hello", comptime snakeToCamelSlice("hello_"));
}

test "uppercase letters after underscore stay uppercase" {
    try testing.expectEqualStrings("myXMLParser", comptime snakeToCamelSlice("my_XML_parser"));
}

test "single char stays unchanged" {
    try testing.expectEqualStrings("x", comptime snakeToCamelSlice("x"));
}

test "null terminated version matches slice version" {
    const slice = comptime snakeToCamelSlice("file_path");
    const z = comptime snakeToCamel("file_path");
    try testing.expectEqualStrings(slice, z);
    try testing.expectEqual(@as(u8, 0), z[z.len]);
}

test "null terminated empty string" {
    const z = comptime snakeToCamel("");
    try testing.expectEqual(@as(usize, 0), z.len);
}
