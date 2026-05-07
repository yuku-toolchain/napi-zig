// host helper for npm release. prints the user module's index.js to argv[1].

const std = @import("std");
const napi = @import("napi-zig");
const user = @import("user-root");

pub fn main(init: std.process.Init) !void {
    var iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer iter.deinit();

    _ = iter.next();
    const out_path = iter.next() orelse {
        try std.Io.File.stderr().writeStreamingAll(init.io, "usage: index-js-emit <output-path>\n");
        return error.MissingOutputPath;
    };

    const js_text = comptime napi.index_js.generate(user);

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = out_path,
        .data = js_text,
    });
}
