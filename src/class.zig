// js class wrapping. init becomes the constructor, every pub fn taking
// *Self becomes a method, optional deinit runs on gc.

const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const env_mod = @import("env.zig");
const util = @import("util.zig");
const val_mod = @import("val.zig");
const bridge = @import("bridge.zig");

const Env = env_mod.Env;
const Val = val_mod.Val;
const check = err.check;

/// wrap a zig struct as a js class. T must declare `pub fn init(...) T`
/// (or `!T`). js_name is the constructor name visible to js.
pub fn class(comptime js_name: [*:0]const u8, comptime T: type) type {
    if (!@hasDecl(T, "init")) {
        @compileError("napi.class: '" ++ @typeName(T) ++ "' must declare `pub fn init(...)`");
    }
    return struct {
        pub const __napi_class_name = js_name;
        pub const __napi_class_inner = T;
    };
}

/// true if `T` is a wrapper produced by `napi.class`.
pub fn isClass(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "__napi_class_name");
}

/// define the js class on `target` under the given field name.
pub fn register(env: Env, target: Val, comptime field_name: []const u8, comptime Wrapper: type) !void {
    const T = Wrapper.__napi_class_inner;
    const methods = comptime collectMethods(T);

    var properties: [methods.len]c.napi_property_descriptor = undefined;
    inline for (methods, 0..) |method_name, i| {
        properties[i] = .{
            .utf8name = comptime util.snakeToCamel(method_name).ptr,
            .method = MethodBridge(T, method_name).call,
            .attributes = c.napi_property_attributes.default_method,
        };
    }

    var class_val: c.napi_value = undefined;
    try check(c.napi_define_class(
        env.handle,
        Wrapper.__napi_class_name,
        c.NAPI_AUTO_LENGTH,
        ConstructorBridge(T).call,
        null,
        properties.len,
        if (properties.len > 0) &properties else null,
        &class_val,
    ));

    try target.setNamedProperty(env, comptime util.snakeToCamel(field_name), .{ .handle = class_val });
}

pub fn collectMethods(comptime T: type) []const []const u8 {
    comptime {
        var names: []const []const u8 = &.{};
        for (@typeInfo(T).@"struct".decls) |d| {
            if (d.name[0] == '_') continue;
            if (std.mem.eql(u8, d.name, "init")) continue;
            if (std.mem.eql(u8, d.name, "deinit")) continue;
            const VT = @TypeOf(@field(T, d.name));
            if (@typeInfo(VT) != .@"fn") continue;
            const fn_info = @typeInfo(VT).@"fn";
            if (fn_info.params.len < 1) continue;
            const first = fn_info.params[0].type orelse continue;
            const fi = @typeInfo(first);
            if (fi != .pointer) continue;
            if (fi.pointer.child != T) continue;
            names = names ++ &[_][]const u8{d.name};
        }
        return names;
    }
}

fn ConstructorBridge(comptime T: type) type {
    const Init = @TypeOf(@field(T, "init"));
    const params = @typeInfo(Init).@"fn".params;
    const inject_env = params.len > 0 and params[0].type.? == Env;
    const js_start: usize = if (inject_env) 1 else 0;
    const Return = @typeInfo(Init).@"fn".return_type.?;
    const Payload = switch (@typeInfo(Return)) {
        .error_union => |eu| eu.payload,
        else => Return,
    };

    if (Payload != T) {
        @compileError("napi.class: '" ++ @typeName(T) ++ ".init' must return " ++ @typeName(T) ++ " or !" ++ @typeName(T));
    }

    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            const arena = env_mod.borrowArena();
            defer env_mod.releaseArena(arena);
            const env: Env = .{ .handle = raw_env, .arena = arena };

            var this_val: c.napi_value = undefined;
            var args: std.meta.ArgsTuple(Init) = undefined;
            if (inject_env) args[0] = env;
            if (!bridge.invoke(Init, js_start, env, raw_info, &args, &this_val, "constructor")) return null;

            const raw = @call(.auto, @field(T, "init"), args);
            const value = if (@typeInfo(Return) == .error_union) (raw catch |e| {
                if (!env.isExceptionPending()) env.throwError(@errorName(e));
                return null;
            }) else raw;

            const instance = std.heap.smp_allocator.create(T) catch {
                env.throwError("napi-zig: out of memory");
                return null;
            };
            instance.* = value;

            if (c.napi_wrap(env.handle, this_val, instance, &finalize, null, null) != .ok) {
                std.heap.smp_allocator.destroy(instance);
                env.throwError("napi-zig: napi_wrap failed");
                return null;
            }
            return this_val;
        }

        fn finalize(_: c.napi_env, data: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
            const instance: *T = @ptrCast(@alignCast(data orelse return));
            if (@hasDecl(T, "deinit")) instance.deinit();
            std.heap.smp_allocator.destroy(instance);
        }
    };
}

fn MethodBridge(comptime T: type, comptime method_name: []const u8) type {
    const Method = @TypeOf(@field(T, method_name));
    const params = @typeInfo(Method).@"fn".params;
    // params[0] is *Self, params[1] is optional Env.
    const inject_env = params.len > 1 and params[1].type.? == Env;
    const js_start: usize = if (inject_env) 2 else 1;
    const Return = @typeInfo(Method).@"fn".return_type orelse void;
    const Payload = switch (@typeInfo(Return)) {
        .error_union => |eu| eu.payload,
        else => Return,
    };

    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            const arena = env_mod.borrowArena();
            defer env_mod.releaseArena(arena);
            const env: Env = .{ .handle = raw_env, .arena = arena };

            var this_val: c.napi_value = undefined;
            var args: std.meta.ArgsTuple(Method) = undefined;
            if (inject_env) args[1] = env;
            if (!bridge.invoke(Method, js_start, env, raw_info, &args, &this_val, "method '" ++ method_name ++ "'")) return null;

            var unwrapped: ?*anyopaque = null;
            if (c.napi_unwrap(env.handle, this_val, &unwrapped) != .ok) {
                env.throwError("napi-zig: napi_unwrap failed");
                return null;
            }
            args[0] = @ptrCast(@alignCast(unwrapped));

            return bridge.returnResult(env, Payload, @call(.auto, @field(T, method_name), args));
        }
    };
}

const testing = std.testing;

test "isClass detects class wrappers" {
    const Counter = class("Counter", struct {
        value: i32,
        pub fn init(v: i32) @This() {
            return .{ .value = v };
        }
        pub fn get(self: *@This()) i32 {
            return self.value;
        }
    });
    try testing.expect(comptime isClass(Counter));
    try testing.expect(comptime !isClass(struct {}));
    try testing.expect(comptime !isClass(i32));
}

test "collectMethods gathers self-receiving fns and skips init/deinit" {
    const T = struct {
        v: i32,
        pub fn init() @This() {
            return .{ .v = 0 };
        }
        pub fn deinit(_: *@This()) void {}
        pub fn a(_: *@This()) i32 {
            return 0;
        }
        pub fn b(_: *const @This()) i32 {
            return 0;
        }
        pub fn c(_: i32) void {} // no self, skipped
        pub fn _hidden(_: *@This()) void {}
    };
    const ms = comptime collectMethods(T);
    try testing.expectEqual(@as(usize, 2), ms.len);
    try testing.expectEqualStrings("a", ms[0]);
    try testing.expectEqualStrings("b", ms[1]);
}

test "class wrapper exposes inner type" {
    const Inner = struct {
        v: i32,
        pub fn init() @This() {
            return .{ .v = 0 };
        }
    };
    const Wrapped = class("Inner", Inner);
    try testing.expectEqual(Inner, Wrapped.__napi_class_inner);
}
