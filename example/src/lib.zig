//! kitchen-sink napi-zig example exercising every major capability.

const std = @import("std");
const napi = @import("napi-zig");

comptime {
    napi.module(@This());
}

pub const version: []const u8 = "0.1.0";
pub const max_buffer: u32 = 1 << 20;

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn double(x: f64) f64 {
    return x * 2;
}

pub fn greet(env: napi.Env, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "Hello, {s}!", .{name});
}

pub fn parse(env: napi.Env, input: []const u8) ![]const u8 {
    return std.ascii.allocUpperString(env.allocator(), input);
}

const CompileOptions = struct {
    file_path: []const u8,
    line_count: i32,
    verbose: bool = false,
};

pub fn compile(env: napi.Env, opts: CompileOptions) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "{s}: {d} lines (verbose={})", .{
        opts.file_path, opts.line_count, opts.verbose,
    });
}

const Level = enum { debug, info, warning, error_level };

pub fn log(env: napi.Env, level: Level, message: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "[{s}] {s}", .{ @tagName(level), message });
}

pub const crypto = struct {
    pub fn hash(env: napi.Env, data: []const u8) ![]const u8 {
        var h: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &h, .{});
        return std.fmt.allocPrint(env.allocator(), "{x}", .{h});
    }

    pub fn verify(expected: []const u8, data: []const u8) bool {
        var h: [32]u8 = undefined;
        std.crypto.hash.sha2.Sha256.hash(data, &h, .{});
        var hex: [64]u8 = undefined;
        _ = std.fmt.bufPrint(&hex, "{x}", .{h}) catch return false;
        return std.mem.eql(u8, expected, &hex);
    }
};

pub const Counter = napi.class("Counter", struct {
    value: i32,

    pub fn init(start: i32) @This() {
        return .{ .value = start };
    }

    pub fn increment(self: *@This()) i32 {
        self.value += 1;
        return self.value;
    }

    pub fn add_n(self: *@This(), n: i32) i32 {
        self.value += n;
        return self.value;
    }

    pub fn get(self: *const @This()) i32 {
        return self.value;
    }

    pub fn reset(self: *@This()) void {
        self.value = 0;
    }
});

const FibWork = struct {
    n: i32,
    result: i32 = 0,

    pub fn compute(self: *FibWork) void {
        self.result = fib(self.n);
    }

    pub fn resolve(self: *FibWork, _: napi.Env) !i32 {
        return self.result;
    }

    fn fib(n: i32) i32 {
        if (n <= 1) return n;
        return fib(n - 1) + fib(n - 2);
    }
};

pub fn asyncFib(env: napi.Env, n: i32) !napi.Val {
    return env.runWorker("fib", FibWork{ .n = n });
}

pub fn sum(env: napi.Env, info: napi.CallInfo) !napi.Val {
    const args = try info.args(env, 16);
    const argc = try info.argCount(env);
    var total: f64 = 0;
    for (0..argc) |i| total += try args[i].to(env, f64);
    return env.toJs(total);
}

pub fn forEach(env: napi.Env, items: []napi.Val, cb: napi.Callback) !void {
    for (items, 0..) |item, i| {
        _ = try cb.call(env, .{ item, @as(u32, @intCast(i)) });
    }
}
