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
            .description = "fixture for cli tests",
            // covers every target the cross-install matrix loads on.
            // macos_x64 is intentionally omitted, github no longer offers
            // a hosted x86_64 macos runner.
            .platforms = &.{
                .linux_x64_gnu,
                .linux_arm64_gnu,
                .linux_arm_gnu,
                .linux_x64_musl,
                .linux_arm64_musl,
                .linux_arm_musl,
                .macos_arm64,
                .windows_x64,
                .windows_arm64,
                .freebsd_x64,
            },
        },
    });
}
