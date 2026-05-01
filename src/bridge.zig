// shared call-site machinery for the function, constructor, and method
// bridges. argument unpacking + return marshalling live here so each
// bridge only contains its unique behaviour.

const std = @import("std");
const c = @import("c.zig");
const env_mod = @import("env.zig");
const convert = @import("convert.zig");
const Val = @import("val.zig").Val;

const Env = env_mod.Env;

/// fetch cb_info and fill `args[js_start..]` from the js arguments.
/// returns false if a js exception is now pending. caller fills any
/// `args[0..js_start]` slots (Env, *Self) after this returns.
pub fn invoke(
    comptime js_start: usize,
    env: Env,
    info: c.napi_callback_info,
    args: anytype,
    this_out: ?*c.napi_value,
    comptime label: []const u8,
) bool {
    const fields = @typeInfo(@typeInfo(@TypeOf(args)).pointer.child).@"struct".fields;
    const js_count = fields.len - js_start;

    var argv: [@max(js_count, 1)]c.napi_value = undefined;
    var argc: usize = js_count;
    const argv_ptr: ?[*]c.napi_value = if (js_count == 0) null else &argv;
    if (c.napi_get_cb_info(env.handle, info, &argc, argv_ptr, this_out, null) != .ok) {
        env.throwError("napi-zig: cb_info failed in " ++ label);
        return false;
    }

    inline for (fields[js_start..], js_start..) |field, i| {
        const T = field.type;
        const js_i = i - js_start;
        if (js_i < argc) {
            args[i] = convert.fromJs(T, env, .{ .handle = argv[js_i] }) catch |e| {
                // user-defined fromJs may return an error without throwing a
                // js exception; in that case, surface the zig error name.
                if (!env.isExceptionPending()) env.throwError(@errorName(e));
                return false;
            };
        } else if (@typeInfo(T) == .optional) {
            args[i] = null;
        } else if (@typeInfo(T) == .@"struct" and comptime isAllDefaults(T)) {
            args[i] = .{};
        } else {
            env.throwTypeError(label ++ " expects " ++ std.fmt.comptimePrint("{d}", .{js_count}) ++ " arguments");
            return false;
        }
    }
    return true;
}

/// convert the raw result of `@call` to a napi_value. handles error
/// unions, void, and Val passthrough. returns null on any failure with
/// a js exception already pending.
pub fn returnResult(env: Env, raw: anytype) ?c.napi_value {
    const Return = @TypeOf(raw);
    const value = if (@typeInfo(Return) == .error_union) (raw catch |e| {
        if (!env.isExceptionPending()) env.throwError(@errorName(e));
        return null;
    }) else raw;

    const Payload = @TypeOf(value);
    if (Payload == void) {
        const undef = env.createUndefined() catch return null;
        return undef.handle;
    }
    if (Payload == Val) return value.handle;
    const v = convert.toJs(Payload, env, value) catch return null;
    return v.handle;
}

fn isAllDefaults(comptime T: type) bool {
    inline for (@typeInfo(T).@"struct".fields) |f| {
        if (f.default_value_ptr == null) return false;
    }
    return true;
}
