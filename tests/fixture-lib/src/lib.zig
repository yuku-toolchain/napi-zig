//! test fixture for napi-zig integration tests. every export is shaped
//! to exercise a specific conversion path or edge case. tests in
//! tests/library/ call into this addon and assert behaviour.

const std = @import("std");
const napi = @import("napi-zig");

comptime {
    napi.module(@This());
}

// constants (exercises the `.constant` registration path)

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

// primitive round-trips

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

// strings

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

// arrays

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

// structs

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

// enums

const Level = enum { debug, info, warning, error_level };

pub fn roundtripLevel(l: Level) Level {
    return l;
}

pub fn levelTagName(env: napi.Env, l: Level) ![]const u8 {
    return env.allocator().dupe(u8, @tagName(l));
}

// namespaces

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

// errors

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

// classes

// underscore-prefixed module-level vars are skipped by registerInto, so we
// can use them as test probes that the JS side reads through wrapper fns.
var _deinit_counter: u32 = 0;

pub fn deinitCount() u32 {
    return _deinit_counter;
}

pub fn resetDeinitCount() void {
    _deinit_counter = 0;
}

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

    pub fn deinit(_: *@This()) void {
        _deinit_counter += 1;
    }
});

// `init` takes Env as first param. heap-allocates the name on smp_allocator
// because the per-call arena is freed when init returns.
pub const Greeter = napi.class("Greeter", struct {
    name: []const u8,

    pub fn init(_: napi.Env, name: []const u8) !@This() {
        const owned = try std.heap.smp_allocator.dupe(u8, name);
        return .{ .name = owned };
    }

    pub fn greet(self: *const @This(), env: napi.Env) ![]const u8 {
        return std.fmt.allocPrint(env.allocator(), "Hello, {s}!", .{self.name});
    }

    pub fn deinit(self: *@This()) void {
        std.heap.smp_allocator.free(self.name);
    }
});

// no deinit, exercises the no-deinit gc path
pub const Plain = napi.class("Plain", struct {
    value: i32,

    pub fn init(v: i32) @This() {
        return .{ .value = v };
    }

    pub fn get(self: *const @This()) i32 {
        return self.value;
    }
});

// init returning !T, exercises the rejection path
pub const Validating = napi.class("Validating", struct {
    value: i32,

    pub fn init(v: i32) !@This() {
        if (v < 0) return error.NegativeNotAllowed;
        return .{ .value = v };
    }

    pub fn get(self: *const @This()) i32 {
        return self.value;
    }
});

// callbacks

pub fn forEach(env: napi.Env, items: []napi.Val, cb: napi.Callback) !void {
    for (items, 0..) |item, i| {
        _ = try cb.call(env, .{ item, @as(u32, @intCast(i)) });
    }
}

pub fn applyTwice(env: napi.Env, cb: napi.Callback, x: i32) !i32 {
    const v1 = try cb.call(env, .{x});
    const v1_int = try v1.to(env, i32);
    const v2 = try cb.call(env, .{v1_int});
    return v2.to(env, i32);
}

pub fn callWithThis(env: napi.Env, this: napi.Val, cb: napi.Callback) !napi.Val {
    return cb.callWith(env, this, .{});
}

pub fn callbackWithSliceArgs(env: napi.Env, cb: napi.Callback) !napi.Val {
    var args = [_]napi.Val{
        try env.toJs(@as(i32, 1)),
        try env.toJs(@as(i32, 2)),
        try env.toJs(@as(i32, 3)),
    };
    const slice: []const napi.Val = &args;
    return cb.call(env, slice);
}

// raw mode (CallInfo)

pub fn variadicSum(env: napi.Env, info: napi.CallInfo) !napi.Val {
    const args = try info.args(env, 16);
    const argc = try info.argCount(env);
    var total: f64 = 0;
    for (0..argc) |i| total += try args[i].to(env, f64);
    return env.toJs(total);
}

pub fn rawArgCount(env: napi.Env, info: napi.CallInfo) !napi.Val {
    return env.toJs(@as(u32, @intCast(try info.argCount(env))));
}

pub fn rawThisMarker(env: napi.Env, info: napi.CallInfo) !napi.Val {
    const this = try info.this(env);
    return this.getNamedProperty(env, "marker");
}

// custom conversion

const CustomPoint = struct {
    x: i32,
    y: i32,

    pub fn toJs(self: @This(), env: napi.Env) !napi.Val {
        const s = try std.fmt.allocPrint(env.allocator(), "{d},{d}", .{ self.x, self.y });
        return env.toJs(s);
    }

    pub fn fromJs(env: napi.Env, val: napi.Val) !@This() {
        const s = try val.to(env, []const u8);
        const comma = std.mem.indexOfScalar(u8, s, ',') orelse return error.InvalidFormat;
        return .{
            .x = try std.fmt.parseInt(i32, s[0..comma], 10),
            .y = try std.fmt.parseInt(i32, s[comma + 1 ..], 10),
        };
    }
};

pub fn roundtripCustomPoint(p: CustomPoint) CustomPoint {
    return p;
}

const Rgb = struct { r: u8, g: u8, b: u8 };

const Color = union(enum) {
    rgb: Rgb,
    hex: []const u8,

    pub fn toJs(self: @This(), env: napi.Env) !napi.Val {
        return switch (self) {
            .rgb => |c| env.toJs(c),
            .hex => |s| env.toJs(s),
        };
    }

    pub fn fromJs(env: napi.Env, val: napi.Val) !@This() {
        if (try val.typeOf(env) == .string) {
            return .{ .hex = try val.to(env, []const u8) };
        }
        return .{ .rgb = try val.to(env, Rgb) };
    }
};

pub fn rgbColor() Color {
    return .{ .rgb = .{ .r = 255, .g = 128, .b = 0 } };
}

pub fn hexColor() Color {
    return .{ .hex = "ff8000" };
}

pub fn colorBrightness(c: Color) i32 {
    return switch (c) {
        .rgb => |rgb| @as(i32, rgb.r) + @as(i32, rgb.g) + @as(i32, rgb.b),
        .hex => |h| @intCast(h.len),
    };
}

// buffers

pub fn createFilledBuffer(env: napi.Env, size: u32, fill: u8) !napi.Val {
    const buf = try env.createBuffer(size);
    @memset(buf.data, fill);
    return buf.val;
}

pub fn createFilledArrayBuffer(env: napi.Env, size: u32, fill: u8) !napi.Val {
    const buf = try env.createArrayBuffer(size);
    @memset(buf.data, fill);
    return buf.val;
}

pub fn bufferSum(env: napi.Env, b: napi.Val) !u32 {
    const data = try b.getBufferData(env);
    var sum: u32 = 0;
    for (data) |byte| sum += byte;
    return sum;
}

pub fn arrayBufferSum(env: napi.Env, ab: napi.Val) !u32 {
    const data = try ab.getArrayBufferData(env);
    var sum: u32 = 0;
    for (data) |byte| sum += byte;
    return sum;
}

pub fn writeIntoBuffer(env: napi.Env, b: napi.Val, value: u8) !u32 {
    const data = try b.getBufferData(env);
    @memset(data, value);
    return @intCast(data.len);
}

pub fn isBuffer(env: napi.Env, v: napi.Val) !bool {
    return v.isBuffer(env);
}

pub fn isArrayBuffer(env: napi.Env, v: napi.Val) !bool {
    return v.isArrayBuffer(env);
}

// external array buffer with finalize. backed by a static buf so we don't
// have to track size in the finalize callback.
var _external_buf: [16]u8 = undefined;
var _external_finalize_count: u32 = 0;

pub fn externalFinalizeCount() u32 {
    return _external_finalize_count;
}

pub fn resetExternalFinalizeCount() void {
    _external_finalize_count = 0;
}

fn externalFinalize(_: napi.c.napi_env, _: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
    _external_finalize_count += 1;
}

pub fn createExternalArrayBuffer(env: napi.Env, fill: u8) !napi.Val {
    @memset(&_external_buf, fill);
    return env.createExternalArrayBuffer(&_external_buf, _external_buf.len, externalFinalize, null);
}

// misc: symbols, dates, externals, version

pub fn createSymbolWithDesc(env: napi.Env, desc: []const u8) !napi.Val {
    const desc_val = try env.toJs(desc);
    return env.createSymbol(desc_val);
}

pub fn createSymbolWithoutDesc(env: napi.Env) !napi.Val {
    return env.createSymbol(null);
}

pub fn isSymbol(env: napi.Env, v: napi.Val) !bool {
    return (try v.typeOf(env)) == .symbol;
}

pub fn dateToMs(env: napi.Env, val: napi.Val) !f64 {
    return val.getDateValue(env);
}

pub fn createDateMs(env: napi.Env, ms: f64) !napi.Val {
    return env.createDate(ms);
}

pub fn isDate(env: napi.Env, v: napi.Val) !bool {
    return v.isDate(env);
}

var _external_value: i32 = 99;

pub fn makeExternal(env: napi.Env) !napi.Val {
    return env.createExternal(&_external_value, null, null);
}

pub fn readExternalI32(env: napi.Env, ext: napi.Val) !i32 {
    const ptr = try ext.getExternalData(env) orelse return error.NoData;
    const typed: *i32 = @ptrCast(@alignCast(ptr));
    return typed.*;
}

pub fn napiVersion(env: napi.Env) !u32 {
    return env.getVersion();
}

pub fn nodeMajorVersion(env: napi.Env) !u32 {
    const v = try env.getNodeVersion();
    return v.major;
}

// promises (synchronous)

pub fn resolveImmediately(env: napi.Env, value: i32) !napi.Val {
    const p = try env.createPromise();
    try p.deferred.resolve(env, try env.toJs(value));
    return p.promise;
}

pub fn rejectImmediately(env: napi.Env, message: []const u8) !napi.Val {
    const p = try env.createPromise();
    const reason = try env.createError(message);
    try p.deferred.reject(env, reason);
    return p.promise;
}

pub fn isPromise(env: napi.Env, v: napi.Val) !bool {
    return v.isPromise(env);
}

// workers (background async)

const I32Work = struct {
    input: i32,
    result: i32 = 0,

    pub fn compute(self: *I32Work) void {
        self.result = fib(self.input);
    }

    pub fn resolve(self: *I32Work, _: napi.Env) !i32 {
        return self.result;
    }

    fn fib(n: i32) i32 {
        if (n <= 1) return n;
        return fib(n - 1) + fib(n - 2);
    }
};

pub fn asyncFib(env: napi.Env, n: i32) !napi.Val {
    return env.runWorker("fib", I32Work{ .input = n });
}

const VoidWork = struct {
    flag: u32 = 0,

    pub fn compute(self: *VoidWork) void {
        self.flag = 1;
    }

    pub fn resolve(_: *VoidWork, _: napi.Env) !void {}
};

pub fn asyncVoid(env: napi.Env) !napi.Val {
    return env.runWorker("void", VoidWork{});
}

const ErrorWork = struct {
    pub fn compute(_: *ErrorWork) void {}

    pub fn resolve(_: *ErrorWork, _: napi.Env) !i32 {
        return error.WorkerFailed;
    }
};

pub fn asyncError(env: napi.Env) !napi.Val {
    return env.runWorker("error", ErrorWork{});
}

const StructWork = struct {
    pub fn compute(_: *StructWork) void {}

    pub fn resolve(_: *StructWork, _: napi.Env) !struct { x: i32, y: i32 } {
        return .{ .x = 3, .y = 4 };
    }
};

pub fn asyncStruct(env: napi.Env) !napi.Val {
    return env.runWorker("struct", StructWork{});
}

const ValWork = struct {
    pub fn compute(_: *ValWork) void {}

    pub fn resolve(_: *ValWork, env: napi.Env) !napi.Val {
        return env.toJs(@as(i32, 99));
    }
};

pub fn asyncVal(env: napi.Env) !napi.Val {
    return env.runWorker("val", ValWork{});
}

const StringWork = struct {
    result: [16]u8 = undefined,
    len: usize = 0,

    pub fn compute(self: *StringWork) void {
        const msg = "from worker";
        @memcpy(self.result[0..msg.len], msg);
        self.len = msg.len;
    }

    pub fn resolve(self: *StringWork, env: napi.Env) ![]const u8 {
        return env.allocator().dupe(u8, self.result[0..self.len]);
    }
};

pub fn asyncString(env: napi.Env) !napi.Val {
    return env.runWorker("string", StringWork{});
}

// threadsafe functions

pub fn signalOnce(env: napi.Env, cb: napi.Callback) !void {
    const tsfn = try cb.threadsafe(env, "tick", void);
    try tsfn.call({}, .blocking);
    try tsfn.release();
}

pub fn signalOnceFromThread(env: napi.Env, cb: napi.Callback) !void {
    const tsfn = try cb.threadsafe(env, "thread_tick", void);
    const t = try std.Thread.spawn(.{}, struct {
        fn run(ts: napi.ThreadsafeFn(void)) void {
            ts.call({}, .blocking) catch {};
            ts.release() catch {};
        }
    }.run, .{tsfn});
    t.detach();
}

pub fn fanOutWorkers(env: napi.Env, cb: napi.Callback, count: u32) !void {
    const tsfn = try cb.threadsafe(env, "workers", u32);

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        try tsfn.acquire();
        const t = try std.Thread.spawn(.{}, struct {
            fn run(ts: napi.ThreadsafeFn(u32), id: u32) void {
                defer ts.release() catch {};
                ts.call(id, .blocking) catch {};
            }
        }.run, .{ tsfn, i });
        t.detach();
    }
    try tsfn.release();
}

// edge-case conversion shapes

pub fn joinStrings(env: napi.Env, items: []const []const u8, sep: []const u8) ![]const u8 {
    return std.mem.join(env.allocator(), sep, items);
}

pub fn returnsStringArray(env: napi.Env) ![]const []const u8 {
    const arr = try env.allocator().alloc([]const u8, 3);
    arr[0] = "alpha";
    arr[1] = "beta";
    arr[2] = "gamma";
    return arr;
}

pub fn sumPointXs(points: []const Point) i32 {
    var total: i32 = 0;
    for (points) |p| total += p.x;
    return total;
}

pub fn returnsPointArray(env: napi.Env) ![]Point {
    const arr = try env.allocator().alloc(Point, 2);
    arr[0] = .{ .x = 1, .y = 2 };
    arr[1] = .{ .x = 3, .y = 4 };
    return arr;
}

pub fn sumOptionalI32Slice(items: []const ?i32) i32 {
    var total: i32 = 0;
    for (items) |maybe| {
        if (maybe) |v| total += v;
    }
    return total;
}

const Inner = struct {
    a: ?i32,
    b: ?[]const u8,
};

const Outer = struct {
    name: []const u8,
    inner: ?Inner,
};

pub fn formatOuter(env: napi.Env, o: Outer) ![]const u8 {
    if (o.inner) |inner| {
        return std.fmt.allocPrint(env.allocator(), "{s}/{?d}/{?s}", .{ o.name, inner.a, inner.b });
    }
    return std.fmt.allocPrint(env.allocator(), "{s}/null", .{o.name});
}

pub fn maybeI32(present: bool) ?i32 {
    return if (present) 42 else null;
}

pub fn maybeString(present: bool) ?[]const u8 {
    return if (present) "hello" else null;
}

pub fn maybeVal(env: napi.Env, present: bool) !?napi.Val {
    if (present) return try env.toJs(@as(i32, 42));
    return null;
}

const Handlers = struct {
    on_data: napi.Callback,
    on_done: napi.Callback,
};

pub fn fireHandlers(env: napi.Env, handlers: Handlers, value: i32) !void {
    _ = try handlers.on_data.call(env, .{value});
    _ = try handlers.on_done.call(env, .{});
}

pub fn nestedSliceSum(items: []const []const i32) i32 {
    var total: i32 = 0;
    for (items) |inner| for (inner) |v| {
        total += v;
    };
    return total;
}

// direct Val method exposure for val-methods.test.ts

pub fn valTypeOf(env: napi.Env, v: napi.Val) ![]const u8 {
    const t = try v.typeOf(env);
    const name = switch (t) {
        .undefined => "undefined",
        .null => "null",
        .boolean => "boolean",
        .number => "number",
        .string => "string",
        .symbol => "symbol",
        .object => "object",
        .function => "function",
        .external => "external",
        .bigint => "bigint",
    };
    return env.allocator().dupe(u8, name);
}

pub fn valStrictEquals(env: napi.Env, a: napi.Val, b: napi.Val) !bool {
    return a.strictEquals(env, b);
}

pub fn valGetProperty(env: napi.Env, obj: napi.Val, key: napi.Val) !napi.Val {
    return obj.getProperty(env, key);
}

pub fn valSetProperty(env: napi.Env, obj: napi.Val, key: napi.Val, value: napi.Val) !void {
    return obj.setProperty(env, key, value);
}

pub fn valGetElement(env: napi.Env, arr: napi.Val, i: u32) !napi.Val {
    return arr.getElement(env, i);
}

pub fn valSetElement(env: napi.Env, arr: napi.Val, i: u32, value: napi.Val) !void {
    return arr.setElement(env, i, value);
}

pub fn valGetArrayLength(env: napi.Env, arr: napi.Val) !u32 {
    return arr.getArrayLength(env);
}

pub fn valHasNamedProperty(env: napi.Env, obj: napi.Val, key: []const u8) !bool {
    const kz = try env.allocator().dupeZ(u8, key);
    return obj.hasNamedProperty(env, kz);
}

pub fn buildObjectFromKeys(env: napi.Env, keys: []const []const u8, values: []const i32) !napi.Val {
    const obj = try env.createObject();
    for (keys, values) |k, v| {
        const kz = try env.allocator().dupeZ(u8, k);
        try obj.setNamedProperty(env, kz, try env.toJs(v));
    }
    return obj;
}

pub fn buildArrayFromInts(env: napi.Env, items: []const i32) !napi.Val {
    const arr = try env.createArrayWithLength(@intCast(items.len));
    for (items, 0..) |v, i| {
        try arr.setElement(env, @intCast(i), try env.toJs(v));
    }
    return arr;
}

pub fn getGlobalThis(env: napi.Env) !napi.Val {
    return env.getGlobal();
}

// Ref lifecycle for refs.test.ts

var _stored_ref: ?napi.Ref = null;

pub fn storeRef(env: napi.Env, value: napi.Val) !void {
    if (_stored_ref) |r| r.delete(env) catch {};
    _stored_ref = try env.createReference(value);
}

pub fn fetchStoredRef(env: napi.Env) !napi.Val {
    const r = _stored_ref orelse return error.NoStoredRef;
    return r.value(env);
}

pub fn clearStoredRef(env: napi.Env) !void {
    if (_stored_ref) |r| try r.delete(env);
    _stored_ref = null;
}

// TypedArray creation for typed-arrays.test.ts

pub fn makeUint8Array(env: napi.Env, len: u32, fill: u8) !napi.Val {
    const ab = try env.createArrayBuffer(len);
    @memset(ab.data, fill);
    return env.createTypedArray(.uint8_array, len, ab.val, 0);
}

pub fn makeInt32Array(env: napi.Env, len: u32) !napi.Val {
    const ab = try env.createArrayBuffer(len * 4);
    const view: [*]i32 = @ptrCast(@alignCast(ab.data.ptr));
    for (0..len) |i| view[i] = @intCast(i);
    return env.createTypedArray(.int32_array, len, ab.val, 0);
}

pub fn makeFloat64Array(env: napi.Env, len: u32) !napi.Val {
    const ab = try env.createArrayBuffer(len * 8);
    const view: [*]f64 = @ptrCast(@alignCast(ab.data.ptr));
    for (0..len) |i| view[i] = @as(f64, @floatFromInt(i)) * 0.5;
    return env.createTypedArray(.float64_array, len, ab.val, 0);
}

pub fn makeBigInt64Array(env: napi.Env, len: u32) !napi.Val {
    const ab = try env.createArrayBuffer(len * 8);
    const view: [*]i64 = @ptrCast(@alignCast(ab.data.ptr));
    for (0..len) |i| view[i] = @as(i64, @intCast(i)) * 1_000_000_000_000;
    return env.createTypedArray(.bigint64_array, len, ab.val, 0);
}

pub fn isTypedArray(env: napi.Env, v: napi.Val) !bool {
    return v.isTypedArray(env);
}

// Exceptions for exceptions.test.ts (extends errors.test.ts coverage)

pub fn throwArbitraryValue(env: napi.Env, value: napi.Val) !void {
    try env.throwValue(value);
    return error.PendingException;
}

pub fn isExceptionPendingNow(env: napi.Env) bool {
    return env.isExceptionPending();
}

// Re-entrancy for callbacks.test.ts

pub fn reentrant(env: napi.Env, cb: napi.Callback, x: i32) !i32 {
    const out = try cb.call(env, .{x});
    const y = try out.to(env, i32);
    return y + 1;
}

// Module-shape edge cases for module-shape.test.ts

const Empty = struct {};

pub fn acceptEmpty(_: Empty) i32 {
    return 99;
}

pub fn returnsEmptyStruct() Empty {
    return .{};
}

const PointPair = struct { Point, Point };

const WithEnum = struct {
    name: []const u8,
    level: Level,
};

const WithTuple = struct {
    name: []const u8,
    point: struct { i32, i32 },
};

pub fn formatWithEnum(env: napi.Env, w: WithEnum) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "{s}/{s}", .{ w.name, @tagName(w.level) });
}

pub fn formatWithTuple(env: napi.Env, w: WithTuple) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "{s}/{d},{d}", .{ w.name, w.point[0], w.point[1] });
}

pub fn sumLevels(items: []const Level) i32 {
    var total: i32 = 0;
    for (items) |l| total += @intFromEnum(l);
    return total;
}

pub fn returnsLevelArray(env: napi.Env) ![]Level {
    const arr = try env.allocator().alloc(Level, 3);
    arr[0] = .info;
    arr[1] = .warning;
    arr[2] = .error_level;
    return arr;
}

pub fn pointPairSum(p: PointPair) i32 {
    return p[0].x + p[0].y + p[1].x + p[1].y;
}

// underscore-prefixed pub fns are skipped by registerInto. used by
// `usesHidden` so the fn isn't dead-stripped, lets js verify the skip.
pub fn _hidden_fn() i32 {
    return 777;
}

pub fn usesHidden() i32 {
    return _hidden_fn();
}
