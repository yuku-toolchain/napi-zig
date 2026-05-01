const std = @import("std");
const napi_zig = @import("napi_zig");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    napi_zig.addLib(b, b.dependency("napi_zig", .{}), .{
        .name = "fcli",
        .root = b.path("src/lib.zig"),
        .target = target,
        .optimize = optimize,
        .npm = .{
            .scope = "@fixture",
            .repository = .{ .url = "https://example.com/fixture" },
            .description = "fixture for cli tests",
            .platforms = &.{ .linux_x64_gnu, .macos_arm64, .windows_x64 },
        },
    });
}
