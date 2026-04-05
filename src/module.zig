const std = @import("std");
const c = @import("c.zig");
const Env = @import("env.zig").Env;
const Val = @import("val.zig").Val;
const convert = @import("convert.zig");
const util = @import("util.zig");
const CallInfo = @import("val.zig").CallInfo;

pub const napi_module_version: u32 = 4;

// emits the napi module registration symbols so that Node.js can load the addon.
pub fn registerModule(comptime Module: type) void {
    const Init = ModuleInit(Module);
    @export(&Init.init, .{ .name = "napi_register_module_v1", .linkage = .strong });
    @export(&Init.apiVersion, .{ .name = "node_api_module_get_api_version_v1", .linkage = .strong });
}

// generates the `napi_register_module_v1` init function for a module.
fn ModuleInit(comptime Module: type) type {
    const names = comptime exportableNames(Module);

    return struct {
        fn init(raw_env: c.napi_env, exports: c.napi_value) callconv(.c) ?c.napi_value {
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const env: Env = .{ .raw = raw_env, .arena = &arena };
            register(env, .{ .raw = exports }) catch {
                if (!env.isExceptionPending()) {
                    env.throwError("napi-zig: module init failed");
                }
                return null;
            };
            return exports;
        }

        fn register(env: Env, exports: Val) !void {
            inline for (names) |name| {
                const js_name = comptime util.snakeToCamel(name);
                const T = @TypeOf(@field(Module, name));
                const kind = comptime classifyDecl(T);

                switch (kind) {
                    .func => {
                        if (comptime isRawFn(T)) {
                            const S = struct {
                                fn wrapper(raw_env: c.napi_env, info: c.napi_callback_info) callconv(.c) ?c.napi_value {
                                    var a = std.heap.ArenaAllocator.init(std.heap.c_allocator);
                                    defer a.deinit();
                                    const e: Env = .{ .raw = raw_env, .arena = &a };
                                    const result = @field(Module, name)(e, CallInfo{ .raw = info }) catch |err| {
                                        if (!e.isExceptionPending()) e.throwError(@errorName(err));
                                        return null;
                                    };
                                    return result.raw;
                                }
                            };
                            try exports.setNamedProperty(env, js_name, try env.createFunction(js_name, S.wrapper));
                        } else {
                            try exports.setNamedProperty(env, js_name, try env.createFunction(js_name, FnBridge(Module, name).call));
                        }
                    },
                    .constant => {
                        const value = @field(Module, name);
                        try exports.setNamedProperty(env, js_name, try convert.toJs(T, env, value));
                    },
                    .skip => {},
                }
            }
        }

        fn apiVersion() callconv(.c) u32 {
            return napi_module_version;
        }
    };
}

// bridges a standard-mode zig function to a C-callable Node-API callback.
// if the first parameter is Env, it is injected automatically.
// remaining parameters are converted from JS arguments, return value
// converted back. errors become JS exceptions.
fn FnBridge(comptime Module: type, comptime name: []const u8) type {
    const func = @field(Module, name);
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).@"fn";
    const params = fn_info.params;
    const param_count = params.len;
    const inject_env = param_count > 0 and params[0].type.? == Env;
    const js_start: usize = if (inject_env) 1 else 0;
    const js_count = param_count - js_start;
    const ReturnType = fn_info.return_type orelse void;
    const Payload = switch (@typeInfo(ReturnType)) {
        .error_union => |eu| eu.payload,
        else => ReturnType,
    };

    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            var arena = std.heap.ArenaAllocator.init(std.heap.c_allocator);
            defer arena.deinit();
            const env: Env = .{ .raw = raw_env, .arena = &arena };
            const result = invoke(env, .{ .raw = raw_info }) catch {
                if (!env.isExceptionPending()) {
                    env.throwError("napi-zig: call to '" ++ name ++ "' failed");
                }
                return null;
            };
            return result.raw;
        }

        fn invoke(env: Env, info: CallInfo) !Val {
            const arg_count = try info.getArgCount(env);
            const arg_values = try info.getArgs(env, js_count);
            const args = try convertArgs(env, arg_values, arg_count);

            const result = @call(.auto, func, args);

            const value = switch (@typeInfo(ReturnType)) {
                .error_union => result catch |err| {
                    env.throwError(@errorName(err));
                    return error.napi_error;
                },
                else => result,
            };

            return convert.toJs(Payload, env, value);
        }

        fn convertArgs(env: Env, argv: [js_count]Val, argc: usize) !std.meta.ArgsTuple(FnType) {
            var args: std.meta.ArgsTuple(FnType) = undefined;
            if (inject_env) args[0] = env;
            inline for (js_start..param_count) |i| {
                const js_i = i - js_start;
                const T = params[i].type.?;
                if (js_i >= argc) {
                    if (@typeInfo(T) == .optional) {
                        args[i] = null;
                    } else if (@typeInfo(T) == .@"struct" and comptime isAllDefaults(T)) {
                        args[i] = .{};
                    } else {
                        env.throwTypeError("expected " ++ std.fmt.comptimePrint("{d}", .{js_count}) ++ " arguments");
                        return error.napi_error;
                    }
                } else {
                    args[i] = try convert.fromJs(T, env, argv[js_i]);
                }
            }
            return args;
        }
    };
}

// how a public declaration is exported to js.
const DeclKind = enum { func, constant, skip };

// classifies a declaration type for export.
fn classifyDecl(comptime T: type) DeclKind {
    return switch (@typeInfo(T)) {
        .@"fn" => .func,
        .type => .skip,
        .comptime_int, .comptime_float => .constant,
        .bool, .int, .float, .@"enum", .@"struct", .optional => .constant,
        .pointer => |ptr| {
            // string literals, *const [N:0]u8, *const [N]u8
            if (ptr.size == .one) {
                const child = @typeInfo(ptr.child);
                if (child == .array and child.array.child == u8) return .constant;
            }
            // slices of u8 ([]const u8)
            if (ptr.size == .slice and ptr.child == u8) return .constant;
            return .skip;
        },
        else => .skip,
    };
}

// collects the names of all exportable public declarations.
fn exportableNames(comptime Module: type) []const []const u8 {
    const decls = @typeInfo(Module).@"struct".decls;
    var names: []const []const u8 = &.{};
    for (decls) |decl| {
        if (decl.name[0] == '_') continue;
        if (classifyDecl(@TypeOf(@field(Module, decl.name))) != .skip) {
            names = names ++ .{decl.name};
        }
    }
    return names;
}

// returns true for raw-mode functions: (Env, CallInfo) -> !Val.
fn isRawFn(comptime Fn: type) bool {
    const info = @typeInfo(Fn);
    if (info != .@"fn") return false;
    const params = info.@"fn".params;
    if (params.len < 2) return false;
    const first = if (params[0].type) |T| T == Env else false;
    const second = if (params[1].type) |T| T == CallInfo else false;
    return first and second;
}

// returns true if every field of the struct has a default value.
fn isAllDefaults(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    for (info.@"struct".fields) |field| {
        if (field.default_value_ptr == null) return false;
    }
    return true;
}
