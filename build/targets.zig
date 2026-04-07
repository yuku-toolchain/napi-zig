const std = @import("std");

pub const Platform = enum {
    linux_x64_gnu,
    linux_x64_musl,
    linux_arm64_gnu,
    linux_arm64_musl,
    linux_arm_gnu,
    linux_arm_musl,
    macos_x64,
    macos_arm64,
    windows_x64,
    windows_arm64,
    freebsd_x64,

    pub const defaults: []const Platform = &.{
        .linux_x64_gnu,
        .linux_arm64_gnu,
        .linux_arm_gnu,
        .linux_x64_musl,
        .linux_arm64_musl,
        .linux_arm_musl,
        .macos_x64,
        .macos_arm64,
        .windows_x64,
        .windows_arm64,
        .freebsd_x64,
    };

    const Info = struct {
        cpu_arch: std.Target.Cpu.Arch,
        os_tag: std.Target.Os.Tag,
        abi: std.Target.Abi = .none,
        npm_os: []const u8,
        npm_cpu: []const u8,
        npm_libc: ?[]const u8 = null,
        suffix: []const u8,
    };

    fn info(self: Platform) Info {
        return switch (self) {
            .linux_x64_gnu => .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .gnu, .npm_os = "linux", .npm_cpu = "x64", .npm_libc = "glibc", .suffix = "linux-x64-gnu" },
            .linux_x64_musl => .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl, .npm_os = "linux", .npm_cpu = "x64", .npm_libc = "musl", .suffix = "linux-x64-musl" },
            .linux_arm64_gnu => .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .gnu, .npm_os = "linux", .npm_cpu = "arm64", .npm_libc = "glibc", .suffix = "linux-arm64-gnu" },
            .linux_arm64_musl => .{ .cpu_arch = .aarch64, .os_tag = .linux, .abi = .musl, .npm_os = "linux", .npm_cpu = "arm64", .npm_libc = "musl", .suffix = "linux-arm64-musl" },
            .linux_arm_gnu => .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .gnueabihf, .npm_os = "linux", .npm_cpu = "arm", .npm_libc = "glibc", .suffix = "linux-arm-gnu" },
            .linux_arm_musl => .{ .cpu_arch = .arm, .os_tag = .linux, .abi = .musleabihf, .npm_os = "linux", .npm_cpu = "arm", .npm_libc = "musl", .suffix = "linux-arm-musl" },
            .macos_x64 => .{ .cpu_arch = .x86_64, .os_tag = .macos, .npm_os = "darwin", .npm_cpu = "x64", .suffix = "darwin-x64" },
            .macos_arm64 => .{ .cpu_arch = .aarch64, .os_tag = .macos, .npm_os = "darwin", .npm_cpu = "arm64", .suffix = "darwin-arm64" },
            .windows_x64 => .{ .cpu_arch = .x86_64, .os_tag = .windows, .npm_os = "win32", .npm_cpu = "x64", .suffix = "win32-x64" },
            .windows_arm64 => .{ .cpu_arch = .aarch64, .os_tag = .windows, .npm_os = "win32", .npm_cpu = "arm64", .suffix = "win32-arm64" },
            .freebsd_x64 => .{ .cpu_arch = .x86_64, .os_tag = .freebsd, .npm_os = "freebsd", .npm_cpu = "x64", .suffix = "freebsd-x64" },
        };
    }

    pub fn zigTarget(self: Platform) std.Target.Query {
        const i = self.info();
        return .{ .cpu_arch = i.cpu_arch, .os_tag = i.os_tag, .abi = i.abi };
    }

    pub fn npmOs(self: Platform) []const u8 {
        return self.info().npm_os;
    }

    pub fn npmCpu(self: Platform) []const u8 {
        return self.info().npm_cpu;
    }

    pub fn npmLibc(self: Platform) ?[]const u8 {
        return self.info().npm_libc;
    }

    pub fn suffix(self: Platform) []const u8 {
        return self.info().suffix;
    }
};
