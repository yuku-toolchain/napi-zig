const std = @import("std");
const napi_zig = @import("napi_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    napi_zig.addLib(b, b.dependency("napi_zig", .{}), .{
        .name = "showcase",
        .root = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .npm = .{
            .scope = "@napi-zig",
            .repository = .{ .url = "https://github.com/yuku-toolchain/napi-zig" },
            .description = "napi-zig showcase example",
            .dts = .auto,
        },
    });
}
