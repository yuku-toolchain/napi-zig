const std = @import("std");
const napi_zig = @import("napi_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    napi_zig.addLib(b, b.dependency("napi_zig", .{}), .{
        .name = "fixture",
        .root = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .npm = .{
            .scope = "@fixture",
            .repository = .{ .url = "https://example.com/fixture" },
            .description = "fixture for library tests",
            .dts = .auto,
            // platforms only matter for `-Dnpm=true` (release mode); we
            // never invoke that here, so the list can stay empty.
            .platforms = &.{},
        },
    });
}
