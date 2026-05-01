// shared call-site machinery for the function, constructor, and method
// bridges. each fetches cb_info, builds an args tuple, and unwraps a
// return value, so all of that lives here.

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
    comptime Fn: type,
    comptime js_start: usize,
    env: Env,
    info: c.napi_callback_info,
    args: *std.meta.ArgsTuple(Fn),
    this_out: ?*c.napi_value,
    comptime label: []const u8,
) bool {
    const params = @typeInfo(Fn).@"fn".params;
    const js_count = params.len - js_start;

    var argv: [@max(js_count, 1)]c.napi_value = undefined;
    var argc: usize = js_count;
    const argv_ptr: ?[*]c.napi_value = if (js_count == 0) null else &argv;
    if (c.napi_get_cb_info(env.handle, info, &argc, argv_ptr, this_out, null) != .ok) {
        env.throwError("napi-zig: cb_info failed in " ++ label);
        return false;
    }

    inline for (js_start..params.len) |i| {
        const T = params[i].type.?;
        const js_i = i - js_start;
        if (js_i >= argc) {
            if (@typeInfo(T) == .optional) {
                args[i] = null;
            } else if (@typeInfo(T) == .@"struct" and comptime isAllDefaults(T)) {
                args[i] = .{};
            } else {
                env.throwTypeError(label ++ " expects " ++ std.fmt.comptimePrint("{d}", .{js_count}) ++ " arguments");
                return false;
            }
        } else {
            args[i] = convert.fromJs(T, env, .{ .handle = argv[js_i] }) catch return false;
        }
    }
    return true;
}

/// convert the raw result of `@call` to a napi_value. handles error
/// unions, void, and Val passthrough. returns null on any failure with
/// a js exception already pending.
pub fn returnResult(env: Env, comptime Payload: type, raw: anytype) ?c.napi_value {
    const Return = @TypeOf(raw);
    const value = if (@typeInfo(Return) == .error_union) (raw catch |e| {
        if (!env.isExceptionPending()) env.throwError(@errorName(e));
        return null;
    }) else raw;

    if (Payload == void) {
        const undef = env.createUndefined() catch return null;
        return undef.handle;
    }
    if (Payload == Val) return value.handle;
    const v = convert.toJs(Payload, env, value) catch return null;
    return v.handle;
}

fn isAllDefaults(comptime T: type) bool {
    for (@typeInfo(T).@"struct".fields) |f| {
        if (f.default_value_ptr == null) return false;
    }
    return true;
}
