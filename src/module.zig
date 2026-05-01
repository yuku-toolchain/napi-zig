const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");
const env_mod = @import("env.zig");
const convert = @import("convert.zig");
const util = @import("util.zig");
const val_mod = @import("val.zig");
const class_mod = @import("class.zig");
const bridge = @import("bridge.zig");

const Env = env_mod.Env;
const Val = val_mod.Val;
const CallInfo = val_mod.CallInfo;

pub const NAPI_MODULE_VERSION: u32 = 8;

const Kind = enum { func, constant, namespace, class, skip };

pub fn registerModule(comptime Module: type) void {
    // skip emitting c entry points when the module is pulled into a
    // host executable (e.g. dts_emit). lib targets only.
    if (builtin.output_mode != .Lib) return;

    const Init = ModuleInit(Module);
    @export(&Init.init, .{ .name = "napi_register_module_v1", .linkage = .strong });
    @export(&Init.apiVersion, .{ .name = "node_api_module_get_api_version_v1", .linkage = .strong });
}

fn ModuleInit(comptime Module: type) type {
    return struct {
        fn init(raw_env: c.napi_env, exports: c.napi_value) callconv(.c) ?c.napi_value {
            const arena = env_mod.borrowArena();
            defer env_mod.releaseArena(arena);
            const env: Env = .{ .handle = raw_env, .arena = arena };

            registerInto(env, .{ .handle = exports }, Module) catch {
                if (!env.isExceptionPending()) env.throwError("napi-zig: module init failed");
                return null;
            };
            return exports;
        }

        fn apiVersion() callconv(.c) u32 {
            return NAPI_MODULE_VERSION;
        }
    };
}

/// recursively register every exportable pub declaration of `Module`
/// onto `target`.
pub fn registerInto(env: Env, target: Val, comptime Module: type) !void {
    const decls = @typeInfo(Module).@"struct".decls;
    inline for (decls) |decl| {
        if (decl.name[0] == '_') continue;
        const kind = comptime classify(Module, decl.name);
        switch (kind) {
            .skip => {},
            .func => try registerFn(env, target, Module, decl.name),
            .constant => try registerConst(env, target, Module, decl.name),
            .namespace => try registerNamespace(env, target, Module, decl.name),
            .class => try class_mod.register(env, target, decl.name, @field(Module, decl.name)),
        }
    }
}

inline fn registerFn(env: Env, target: Val, comptime Module: type, comptime name: []const u8) !void {
    const js_name = comptime util.snakeToCamel(name);
    const fn_type = @TypeOf(@field(Module, name));
    const cb = if (comptime isRawFn(fn_type)) RawBridge(Module, name).call else FnBridge(Module, name).call;
    try target.setNamedProperty(env, js_name, try env.createFunction(js_name, cb));
}

inline fn registerConst(env: Env, target: Val, comptime Module: type, comptime name: []const u8) !void {
    const js_name = comptime util.snakeToCamel(name);
    const T = @TypeOf(@field(Module, name));
    try target.setNamedProperty(env, js_name, try convert.toJs(T, env, @field(Module, name)));
}

inline fn registerNamespace(env: Env, target: Val, comptime Module: type, comptime name: []const u8) !void {
    const js_name = comptime util.snakeToCamel(name);
    const Inner = @field(Module, name);
    const obj = try env.createObject();
    try registerInto(env, obj, Inner);
    try target.setNamedProperty(env, js_name, obj);
}

// wrap `Module.name` as a napi_callback. injects Env if it's the first
// param, converts the rest from js, converts the return back.
fn FnBridge(comptime Module: type, comptime name: []const u8) type {
    const Fn = @TypeOf(@field(Module, name));
    const params = @typeInfo(Fn).@"fn".params;
    const inject_env = params.len > 0 and params[0].type.? == Env;
    const js_start: usize = if (inject_env) 1 else 0;
    const Return = @typeInfo(Fn).@"fn".return_type orelse void;
    const Payload = switch (@typeInfo(Return)) {
        .error_union => |eu| eu.payload,
        else => Return,
    };

    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            const arena = env_mod.borrowArena();
            defer env_mod.releaseArena(arena);
            const env: Env = .{ .handle = raw_env, .arena = arena };

            var args: std.meta.ArgsTuple(Fn) = undefined;
            if (inject_env) args[0] = env;
            if (!bridge.invoke(Fn, js_start, env, raw_info, &args, null, "function '" ++ name ++ "'")) return null;

            return bridge.returnResult(env, Payload, @call(.auto, @field(Module, name), args));
        }
    };
}

// raw mode: fn(Env, CallInfo) !Val. user extracts args themselves.
fn RawBridge(comptime Module: type, comptime name: []const u8) type {
    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            const arena = env_mod.borrowArena();
            defer env_mod.releaseArena(arena);
            const env: Env = .{ .handle = raw_env, .arena = arena };

            const result = @field(Module, name)(env, CallInfo{ .handle = raw_info }) catch |e| {
                if (!env.isExceptionPending()) env.throwError(@errorName(e));
                return null;
            };
            return result.handle;
        }
    };
}

fn classify(comptime Module: type, comptime name: []const u8) Kind {
    const T = @TypeOf(@field(Module, name));

    if (T == type) {
        const Inner = @field(Module, name);
        if (@typeInfo(Inner) == .@"struct") {
            if (class_mod.isClass(Inner)) return .class;
            if (hasExportable(Inner)) return .namespace;
        }
        return .skip;
    }

    return switch (@typeInfo(T)) {
        .@"fn" => .func,
        .comptime_int, .comptime_float => .constant,
        .bool, .int, .float, .@"enum", .@"struct", .optional => .constant,
        .pointer => |ptr| {
            if (ptr.size == .one) {
                const child = @typeInfo(ptr.child);
                if (child == .array and child.array.child == u8) return .constant;
            }
            if (ptr.size == .slice and ptr.child == u8) return .constant;
            return .skip;
        },
        else => .skip,
    };
}

fn hasExportable(comptime T: type) bool {
    if (@typeInfo(T) != .@"struct") return false;
    const decls = @typeInfo(T).@"struct".decls;
    for (decls) |d| {
        if (d.name[0] == '_') continue;
        if (classify(T, d.name) != .skip) return true;
    }
    return false;
}

fn isRawFn(comptime Fn: type) bool {
    const info = @typeInfo(Fn);
    if (info != .@"fn") return false;
    const params = info.@"fn".params;
    if (params.len < 2) return false;
    const first = if (params[0].type) |T| T == Env else false;
    const second = if (params[1].type) |T| T == CallInfo else false;
    return first and second;
}

const testing = std.testing;

test "classify identifies functions" {
    const M = struct {
        pub fn f() void {}
        pub fn g(_: i32, _: i32) i32 {
            return 0;
        }
    };
    try testing.expectEqual(Kind.func, comptime classify(M, "f"));
    try testing.expectEqual(Kind.func, comptime classify(M, "g"));
}

test "classify identifies constants" {
    const M = struct {
        pub const a: i32 = 1;
        pub const b: bool = true;
        pub const c: []const u8 = "hi";
    };
    try testing.expectEqual(Kind.constant, comptime classify(M, "a"));
    try testing.expectEqual(Kind.constant, comptime classify(M, "b"));
    try testing.expectEqual(Kind.constant, comptime classify(M, "c"));
}

test "classify identifies namespaces" {
    const M = struct {
        pub const crypto = struct {
            pub fn hash() void {}
        };
        pub const Empty = struct {};
        pub const Just_a_type = i32;
    };
    try testing.expectEqual(Kind.namespace, comptime classify(M, "crypto"));
    try testing.expectEqual(Kind.skip, comptime classify(M, "Empty"));
    try testing.expectEqual(Kind.skip, comptime classify(M, "Just_a_type"));
}

test "classify identifies classes" {
    const M = struct {
        pub const Counter = class_mod.class("Counter", struct {
            v: i32,
            pub fn init() @This() {
                return .{ .v = 0 };
            }
            pub fn inc(self: *@This()) i32 {
                self.v += 1;
                return self.v;
            }
        });
    };
    try testing.expectEqual(Kind.class, comptime classify(M, "Counter"));
}

test "isRawFn detects (Env, CallInfo) signature" {
    const raw = struct {
        pub fn f(_: Env, _: CallInfo) !Val {
            unreachable;
        }
    };
    try testing.expect(comptime isRawFn(@TypeOf(raw.f)));
    try testing.expect(comptime !isRawFn(fn (i32) void));
    try testing.expect(comptime !isRawFn(fn (Env) void));
}

test "underscore prefixed decls are skipped during enumeration" {
    const M = struct {
        pub fn visible() void {}
        pub fn _hidden() void {}
    };
    var count: usize = 0;
    inline for (@typeInfo(M).@"struct".decls) |d| {
        if (d.name[0] == '_') continue;
        if (comptime classify(M, d.name) != .skip) count += 1;
    }
    try testing.expectEqual(@as(usize, 1), count);
}
