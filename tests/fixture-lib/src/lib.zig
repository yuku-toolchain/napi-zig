//! test fixture for napi-zig integration tests. every export is shaped
//! to exercise a specific conversion path or edge case. tests in
//! tests/library/ call into this addon and assert behaviour.

const std = @import("std");
const napi = @import("napi-zig");

comptime {
    napi.module(@This());
}

// ---- constants (exercises the `.constant` registration path) ----

pub const bool_true: bool = true;
pub const bool_false: bool = false;
pub const i32_value: i32 = 42;
pub const i32_neg: i32 = -42;
pub const i32_max: i32 = std.math.maxInt(i32);
pub const u32_max: u32 = std.math.maxInt(u32);
pub const f64_pi: f64 = 3.14159265358979;
pub const string_value: []const u8 = "constant string";
pub const empty_string: []const u8 = "";
pub const snake_case_name: u32 = 7; // verifies snake → camel on constants
pub const comptime_int_value = 12345; // exercises .comptime_int branch
pub const comptime_float_value = 1.5; // exercises .comptime_float branch
pub const sentinel_string: *const [5:0]u8 = "hello"; // exercises .pointer .one [N:0]u8

// ---- primitive round-trips ----

pub fn roundtripBool(b: bool) bool {
    return b;
}

pub fn roundtripI8(v: i8) i8 {
    return v;
}
pub fn roundtripI16(v: i16) i16 {
    return v;
}
pub fn roundtripI32(v: i32) i32 {
    return v;
}
pub fn roundtripI53(v: i53) i53 {
    return v;
}
pub fn roundtripI64(v: i64) i64 {
    return v;
}

pub fn roundtripU8(v: u8) u8 {
    return v;
}
pub fn roundtripU16(v: u16) u16 {
    return v;
}
pub fn roundtripU32(v: u32) u32 {
    return v;
}
pub fn roundtripU53(v: u53) u53 {
    return v;
}
pub fn roundtripU64(v: u64) u64 {
    return v;
}

pub fn roundtripF32(v: f32) f32 {
    return v;
}
pub fn roundtripF64(v: f64) f64 {
    return v;
}
pub fn roundtripF16(v: f16) f16 {
    return v;
}

pub fn roundtripOptionalI32(v: ?i32) ?i32 {
    return v;
}

pub fn returnsNull() ?i32 {
    return null;
}

pub fn returnsSomeInt() ?i32 {
    return 7;
}

pub fn returnsVoid() void {}

// ---- strings ----

pub fn roundtripString(env: napi.Env, s: []const u8) ![]const u8 {
    return env.allocator().dupe(u8, s);
}

pub fn stringByteLength(s: []const u8) u32 {
    return @intCast(s.len);
}

pub fn concatStrings(env: napi.Env, a: []const u8, b: []const u8) ![]const u8 {
    return std.mem.concat(env.allocator(), u8, &.{ a, b });
}

pub fn returnsEmptyString() []const u8 {
    return "";
}

pub fn returnsLargeString(env: napi.Env, n: u32) ![]const u8 {
    const buf = try env.allocator().alloc(u8, n);
    @memset(buf, 'a');
    return buf;
}

// ---- arrays ----

pub fn sumI32Slice(arr: []const i32) i32 {
    var total: i32 = 0;
    for (arr) |x| total += x;
    return total;
}

pub fn roundtripFixedArray(arr: [3]i32) [3]i32 {
    return arr;
}

pub fn returnsArrayOfN(env: napi.Env, n: u32) ![]i32 {
    const buf = try env.allocator().alloc(i32, n);
    for (buf, 0..) |*item, i| item.* = @intCast(i);
    return buf;
}

pub fn returnsEmptyArray(env: napi.Env) ![]i32 {
    return env.allocator().alloc(i32, 0);
}

const Pair = struct { i32, []const u8 };

pub fn tupleFirst(t: Pair) i32 {
    return t[0];
}

pub fn tupleSecondLen(t: Pair) u32 {
    return @intCast(t[1].len);
}

pub fn returnsTuple(env: napi.Env) !struct { i32, []const u8 } {
    return .{ 42, try env.allocator().dupe(u8, "hello") };
}

// ---- structs ----

const Point = struct { x: i32, y: i32 };

pub fn roundtripPoint(p: Point) Point {
    return p;
}

pub fn pointSum(p: Point) i32 {
    return p.x + p.y;
}

const Options = struct {
    file_path: []const u8,
    line_count: i32,
    verbose: bool = false,
};

pub fn formatOptions(env: napi.Env, opts: Options) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "{s}:{d}:{}", .{
        opts.file_path, opts.line_count, opts.verbose,
    });
}

const Container = struct {
    name: []const u8,
    point: Point,
};

pub fn formatContainer(env: napi.Env, c: Container) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "{s}@{d},{d}", .{
        c.name, c.point.x, c.point.y,
    });
}

const FullStruct = struct {
    name: []const u8,
    age: i32,
    nick_name: ?[]const u8,
    is_admin: bool = false,
};

pub fn formatFullStruct(env: napi.Env, s: FullStruct) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "{s}/{d}/{?s}/{}", .{
        s.name, s.age, s.nick_name, s.is_admin,
    });
}

const Settings = struct {
    debug: bool = false,
    level: i32 = 0,
};

pub fn formatSettings(env: napi.Env, s: Settings) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "{}/{d}", .{ s.debug, s.level });
}

// ---- enums ----

const Level = enum { debug, info, warning, error_level };

pub fn roundtripLevel(l: Level) Level {
    return l;
}

pub fn levelTagName(env: napi.Env, l: Level) ![]const u8 {
    return env.allocator().dupe(u8, @tagName(l));
}

// ---- namespaces ----

pub const math = struct {
    pub fn square(x: i32) i32 {
        return x * x;
    }

    pub fn cube(x: i32) i32 {
        return x * x * x;
    }

    pub const inner = struct {
        pub fn deep(x: i32) i32 {
            return x + 1000;
        }

        pub const deeper = struct {
            pub fn deepest(x: i32) i32 {
                return x + 1_000_000;
            }
        };
    };
};

pub const constants_ns = struct {
    pub const pi: f64 = 3.14159;
    pub const e: f64 = 2.71828;
    pub const greeting: []const u8 = "hello from namespace";
};

// ---- errors ----

pub fn throwIfTrue(b: bool) !i32 {
    if (b) return error.RequestedFailure;
    return 1;
}

pub fn divideF64(a: f64, b: f64) !f64 {
    if (b == 0) return error.DivisionByZero;
    return a / b;
}

pub fn throwTypeErrorExplicit(env: napi.Env) !void {
    env.throwTypeError("explicit type error");
    return error.InvalidArg;
}

pub fn throwRangeErrorExplicit(env: napi.Env) !void {
    env.throwRangeError("explicit range error");
    return error.InvalidArg;
}

pub fn throwGenericErrorExplicit(env: napi.Env) !void {
    env.throwError("explicit generic error");
    return error.InvalidArg;
}
