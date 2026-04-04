const std = @import("std");
const c = @import("c.zig");
const Env = @import("env.zig").Env;
const Val = @import("val.zig").Val;
const check = @import("val.zig").check;
const convert = @import("convert.zig");
const util = @import("util.zig");
const CallInfo = @import("call_info.zig").CallInfo;

pub const napi_module_version: u32 = 1;

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
            const env: Env = .{ .raw = raw_env };
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
                                    const e: Env = .{ .raw = raw_env };
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

/// bridges a single Zig function to a C-callable N-API callback.
///
/// extracts JS arguments via `napi_get_cb_info`, converts them to zig types
/// with `convert.fromJs`, calls the user function, and converts the return
/// value back with `convert.toJs`. errors become js exceptions.
fn FnBridge(comptime Module: type, comptime name: []const u8) type {
    const func = @field(Module, name);
    const FnType = @TypeOf(func);
    const fn_info = @typeInfo(FnType).@"fn";
    const params = fn_info.params;
    const param_count = params.len;
    const ReturnType = fn_info.return_type orelse void;
    const Payload = switch (@typeInfo(ReturnType)) {
        .error_union => |eu| eu.payload,
        else => ReturnType,
    };
    const buf_len = if (param_count == 0) 1 else param_count;

    return struct {
        fn call(raw_env: c.napi_env, info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            const env: Env = .{ .raw = raw_env };
            return invoke(env, info) catch {
                if (!env.isExceptionPending()) {
                    env.throwError("napi-zig: call to '" ++ name ++ "' failed");
                }
                return null;
            };
        }

        fn invoke(env: Env, info: c.napi_callback_info) !c.napi_value {
            var argc: usize = param_count;
            var argv: [buf_len]c.napi_value = undefined;

            try check(c.napi_get_cb_info(env.raw, info, &argc, if (param_count == 0) null else &argv, null, null));

            var string_allocs: [buf_len]?StringAlloc = .{null} ** buf_len;

            defer for (&string_allocs) |*sa| {
                if (sa.*) |s| s.deinit();
            };

            const args = try convertArgs(env, &argv, &string_allocs, argc);

            const result = @call(.auto, func, args);

            const value = switch (@typeInfo(ReturnType)) {
                .error_union => result catch |err| {
                    env.throwError(@errorName(err));
                    return error.napi_error;
                },
                else => result,
            };

            return (try convert.toJs(Payload, env, value)).raw;
        }

        fn convertArgs(env: Env, argv: []c.napi_value, string_allocs: []?StringAlloc, argc: usize) !std.meta.ArgsTuple(FnType) {
            var args: std.meta.ArgsTuple(FnType) = undefined;
            inline for (0..param_count) |i| {
                const T = params[i].type.?;
                if (i >= argc) {
                    if (@typeInfo(T) == .optional) {
                        args[i] = null;
                    } else if (@typeInfo(T) == .@"struct" and comptime isAllDefaults(T)) {
                        args[i] = .{};
                    } else {
                        env.throwTypeError("expected " ++ std.fmt.comptimePrint("{d}", .{param_count}) ++ " arguments");
                        return error.napi_error;
                    }
                } else if (T == []const u8 or T == []u8) {
                    const sa = try extractString(env, .{ .raw = argv[i] });
                    string_allocs[i] = sa;
                    args[i] = sa.bytes;
                } else {
                    args[i] = try convert.fromJs(T, env, .{ .raw = argv[i] });
                }
            }
            return args;
        }

        fn extractString(env: Env, val: Val) !StringAlloc {
            const len = try val.getStringLength(env);
            const buf = try std.heap.c_allocator.alloc(u8, len + 1);
            var written: usize = 0;
            try check(c.napi_get_value_string_utf8(env.raw, val.raw, buf.ptr, buf.len, &written));
            return .{ .bytes = buf[0..written], .allocator = std.heap.c_allocator };
        }
    };
}

// owns a heap-allocated string buffer extracted from a JS value.
const StringAlloc = struct {
    bytes: []const u8,
    allocator: std.mem.Allocator,

    fn deinit(self: StringAlloc) void {
        self.allocator.free(self.bytes);
    }
};

/// how a public declaration is exported to js.
const DeclKind = enum { func, constant, skip };

/// classifies a declaration type for export.
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

/// collects the names of all exportable public declarations in `Module`.
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

/// returns `true` if `Fn` is a function whose first parameter is `Env`,
/// indicating it uses the raw-mode calling convention `(Env, CallInfo)`.
fn isRawFn(comptime Fn: type) bool {
    const info = @typeInfo(Fn);
    if (info != .@"fn") return false;
    const params = info.@"fn".params;
    if (params.len == 0) return false;
    return if (params[0].type) |T| T == Env else false;
}

/// returns `true` if every field of struct `T` has a default value,
/// meaning a zero-argument initializer `.{}` is valid.
fn isAllDefaults(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct") return false;
    for (info.@"struct".fields) |field| {
        if (field.default_value_ptr == null) return false;
    }
    return true;
}
