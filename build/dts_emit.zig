// dts-emit, host helper that prints the .d.ts for the user's module
// to a file path given as argv[1]. Built and run by `addLib` when
// `.dts = .auto`.
//
// `napi.module()` is a no-op when output_mode != .Lib, so importing
// the user module here doesn't try to register C entry points.
//
// Targets Zig 0.17's main(init) signature, `init` carries a default
// gpa, an Io implementation, and parsed args.

const std = @import("std");
const napi = @import("napi-zig");
const user = @import("user-root");

pub fn main(init: std.process.Init) !void {
    var iter = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer iter.deinit();

    _ = iter.next(); // skip the executable path
    const out_path = iter.next() orelse {
        try std.Io.File.stderr().writeStreamingAll(init.io, "usage: dts-emit <output-path>\n");
        return error.MissingOutputPath;
    };

    const dts_text = comptime napi.dts.generate(user);

    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = out_path,
        .data = dts_text,
    });
}
