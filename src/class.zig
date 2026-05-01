// JS class wrapping.
//
//     pub const Counter = napi.class("Counter", struct {
//         value: i32,
//
//         pub fn init(start: i32) @This() {
//             return .{ .value = start };
//         }
//
//         pub fn increment(self: *@This()) i32 {
//             self.value += 1;
//             return self.value;
//         }
//     });
//
//     // in JS: new Counter(10).increment() → 11
//
// `init` becomes the constructor. Every other `pub fn` whose first
// parameter is `*Self` (or `*const Self`) becomes a method. An
// optional `pub fn deinit(self: *Self) void` is invoked when the JS
// instance is garbage collected.
//
// Both `init` and methods may take `Env` as their first non-self
// parameter — it's injected automatically and doesn't consume a JS arg.

const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const env_mod = @import("env.zig");
const convert = @import("convert.zig");
const util = @import("util.zig");
const val_mod = @import("val.zig");

const Env = env_mod.Env;
const Val = val_mod.Val;
const check = err.check;

/// Wrap a Zig struct as a JS class.
///
/// `js_name` is the constructor name visible to JS. `T` must declare
/// a `pub fn init(...)` returning `T` or `!T`.
pub fn class(comptime js_name: [*:0]const u8, comptime T: type) type {
    if (!@hasDecl(T, "init")) {
        @compileError("napi.class: '" ++ @typeName(T) ++ "' must declare `pub fn init(...)`");
    }
    return struct {
        pub const __napi_class_name = js_name;
        pub const __napi_class_inner = T;
    };
}

/// Returns true if `T` is a wrapper produced by `napi.class`.
pub fn isClass(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "__napi_class_name");
}

/// Define the JS class on `target` under the given field name.
pub fn register(env: Env, target: Val, comptime field_name: []const u8, comptime Wrapper: type) !void {
    const T = Wrapper.__napi_class_inner;
    const class_name = Wrapper.__napi_class_name;
    const methods = comptime collectMethods(T);

    // Static so the descriptor name pointers stay valid for the addon's lifetime.
    const Names = struct {
        const list = blk: {
            var names: [methods.len][:0]const u8 = undefined;
            for (methods, 0..) |m, i| names[i] = util.snakeToCamel(m);
            break :blk names;
        };
    };

    var properties: [methods.len]c.napi_property_descriptor = undefined;
    inline for (methods, 0..) |method_name, i| {
        properties[i] = .{
            .utf8name = Names.list[i].ptr,
            .method = MethodBridge(T, method_name).call,
            .attributes = c.napi_property_attributes.default_method,
        };
    }

    var class_val: c.napi_value = undefined;
    try check(c.napi_define_class(
        env.handle,
        class_name,
        c.NAPI_AUTO_LENGTH,
        ConstructorBridge(T).call,
        null,
        properties.len,
        if (properties.len > 0) &properties else null,
        &class_val,
    ));

    const js_field = comptime util.snakeToCamel(field_name);
    try target.setNamedProperty(env, js_field, .{ .handle = class_val });
}

// ── Method enumeration ────────────────────────────────────────────────

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

// ── Constructor bridge ────────────────────────────────────────────────

fn ConstructorBridge(comptime T: type) type {
    const init_fn = @field(T, "init");
    const InitFn = @TypeOf(init_fn);
    const init_info = @typeInfo(InitFn).@"fn";
    const params = init_info.params;
    const inject_env = params.len > 0 and params[0].type != null and params[0].type.? == Env;
    const js_start: usize = if (inject_env) 1 else 0;
    const js_count = params.len - js_start;
    const Return = init_info.return_type orelse @compileError("init must return a type");
    const is_error_union = @typeInfo(Return) == .error_union;
    const Payload = if (is_error_union) @typeInfo(Return).error_union.payload else Return;

    if (Payload != T) {
        @compileError("napi.class: '" ++ @typeName(T) ++ ".init' must return " ++ @typeName(T) ++ " or !" ++ @typeName(T));
    }

    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            const arena = env_mod.borrowArena();
            defer env_mod.releaseArena(arena);
            const env: Env = .{ .handle = raw_env, .arena = arena };

            const StorageLen = @max(js_count, 1);
            var argv: [StorageLen]c.napi_value = undefined;
            var argc: usize = js_count;
            var this_val: c.napi_value = undefined;
            const argv_ptr: ?[*]c.napi_value = if (js_count == 0) null else &argv;
            if (c.napi_get_cb_info(env.handle, raw_info, &argc, argv_ptr, &this_val, null) != .ok) {
                env.throwError("napi-zig: constructor cb_info failed");
                return null;
            }

            var args: std.meta.ArgsTuple(InitFn) = undefined;
            if (inject_env) args[0] = env;
            inline for (js_start..params.len) |i| {
                const ParamT = params[i].type.?;
                const js_i = i - js_start;
                if (js_i >= argc) {
                    if (@typeInfo(ParamT) == .optional) {
                        args[i] = null;
                    } else {
                        env.throwTypeError("constructor expects " ++ std.fmt.comptimePrint("{d}", .{js_count}) ++ " arguments");
                        return null;
                    }
                } else {
                    const v: Val = .{ .handle = argv[js_i] };
                    args[i] = convert.fromJs(ParamT, env, v) catch return null;
                }
            }

            const init_result = @call(.auto, init_fn, args);
            const value = if (is_error_union) (init_result catch |e| {
                if (!env.isExceptionPending()) env.throwError(@errorName(e));
                return null;
            }) else init_result;

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
            if (@hasDecl(T, "deinit")) {
                const deinit_fn = @field(T, "deinit");
                const di_info = @typeInfo(@TypeOf(deinit_fn)).@"fn";
                if (di_info.params.len == 1) {
                    instance.deinit();
                }
            }
            std.heap.smp_allocator.destroy(instance);
        }
    };
}

// ── Method bridge ─────────────────────────────────────────────────────

fn MethodBridge(comptime T: type, comptime method_name: []const u8) type {
    const method_fn = @field(T, method_name);
    const MethodFn = @TypeOf(method_fn);
    const method_info = @typeInfo(MethodFn).@"fn";
    const params = method_info.params;
    // params[0] = *Self or *const Self (already validated by collectMethods)
    // params[1] = optional Env injection
    const inject_env = params.len > 1 and params[1].type != null and params[1].type.? == Env;
    const js_start: usize = if (inject_env) 2 else 1;
    const js_count = params.len - js_start;
    const Return = method_info.return_type orelse void;
    const is_error_union = @typeInfo(Return) == .error_union;
    const Payload = if (is_error_union) @typeInfo(Return).error_union.payload else Return;

    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            const arena = env_mod.borrowArena();
            defer env_mod.releaseArena(arena);
            const env: Env = .{ .handle = raw_env, .arena = arena };

            const StorageLen = @max(js_count, 1);
            var argv: [StorageLen]c.napi_value = undefined;
            var argc: usize = js_count;
            var this_val: c.napi_value = undefined;
            const argv_ptr: ?[*]c.napi_value = if (js_count == 0) null else &argv;
            if (c.napi_get_cb_info(env.handle, raw_info, &argc, argv_ptr, &this_val, null) != .ok) {
                env.throwError("napi-zig: method cb_info failed");
                return null;
            }

            var unwrapped: ?*anyopaque = null;
            if (c.napi_unwrap(env.handle, this_val, &unwrapped) != .ok) {
                env.throwError("napi-zig: napi_unwrap failed");
                return null;
            }

            var args: std.meta.ArgsTuple(MethodFn) = undefined;
            args[0] = @ptrCast(@alignCast(unwrapped));
            if (inject_env) args[1] = env;

            inline for (js_start..params.len) |i| {
                const ParamT = params[i].type.?;
                const js_i = i - js_start;
                if (js_i >= argc) {
                    if (@typeInfo(ParamT) == .optional) {
                        args[i] = null;
                    } else {
                        env.throwTypeError("method '" ++ method_name ++ "' expects " ++ std.fmt.comptimePrint("{d}", .{js_count}) ++ " arguments");
                        return null;
                    }
                } else {
                    const v: Val = .{ .handle = argv[js_i] };
                    args[i] = convert.fromJs(ParamT, env, v) catch return null;
                }
            }

            const result = @call(.auto, method_fn, args);
            const value = if (is_error_union) (result catch |e| {
                if (!env.isExceptionPending()) env.throwError(@errorName(e));
                return null;
            }) else result;

            const js_val = if (Payload == void)
                env.createUndefined() catch return null
            else if (Payload == Val)
                value
            else
                convert.toJs(Payload, env, value) catch return null;
            return js_val.handle;
        }
    };
}

// ── Tests ─────────────────────────────────────────────────────────────

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
        pub fn c(_: i32) void {} // no self → skipped
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
