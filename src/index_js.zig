// comptime index.js generator. emits a thin esm wrapper around binding.js
// that re-exports every js-visible top-level export by name.

const std = @import("std");
const util = @import("util.zig");
const module = @import("module.zig");

pub fn generate(comptime Module: type) []const u8 {
    @setEvalBranchQuota(100_000);
    comptime {
        var names: []const u8 = "";
        var first = true;

        for (@typeInfo(Module).@"struct".decls) |decl| {
            if (decl.name[0] == '_') continue;
            switch (module.classify(Module, decl.name)) {
                .skip => {},
                .func, .constant, .class, .namespace => {
                    if (!first) names = names ++ ", ";
                    names = names ++ util.snakeToCamel(decl.name);
                    first = false;
                },
            }
        }

        const head = "import binding from './binding.js';\n";
        const tail = "export default binding;\n";
        if (first) return head ++ tail;
        return head ++ "export const { " ++ names ++ " } = binding;\n" ++ tail;
    }
}

const testing = std.testing;

test "generate emits named exports for fns and constants" {
    const M = struct {
        pub fn add(_: i32, _: i32) i32 {
            return 0;
        }
        pub const version: []const u8 = "1.0.0";
    };
    const js = comptime generate(M);
    try testing.expect(std.mem.indexOf(u8, js, "export const { add, version } = binding;") != null);
    try testing.expect(std.mem.indexOf(u8, js, "export default binding;") != null);
}

test "generate camelCases snake_case exports" {
    const M = struct {
        pub fn read_file(_: []const u8) []const u8 {
            return "";
        }
    };
    const js = comptime generate(M);
    try testing.expect(std.mem.indexOf(u8, js, "{ readFile }") != null);
}

test "generate emits no destructure when module has no exports" {
    const M = struct {};
    const js = comptime generate(M);
    try testing.expectEqualStrings(
        \\import binding from './binding.js';
        \\export default binding;
        \\
    , js);
}

test "generate skips underscore-prefixed decls" {
    const M = struct {
        pub fn _internal() void {}
        pub fn visible() void {}
    };
    const js = comptime generate(M);
    try testing.expect(std.mem.indexOf(u8, js, "{ visible }") != null);
    try testing.expect(std.mem.indexOf(u8, js, "_internal") == null);
}
