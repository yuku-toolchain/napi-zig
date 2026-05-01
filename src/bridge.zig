// Shared call-site machinery for every C-callable bridge.
//
// Three bridges in napi-zig wrap a Zig function as a `napi_callback`:
// the top-level function bridge (`module.zig`), the class constructor
// bridge, and the class method bridge (`class.zig`). They share most
// of their work, fetch arg info, build the args tuple, convert each
// JS argument, unwrap the return. This module factors all of it out.

const std = @import("std");
const c = @import("c.zig");
const env_mod = @import("env.zig");
const convert = @import("convert.zig");
const Val = @import("val.zig").Val;

const Env = env_mod.Env;

/// Fetch the cb_info and fill `args[js_start..]` from the JS arguments.
/// Returns `true` on success, `false` if a JS exception is now pending.
///
/// `args[0..js_start]` is left untouched, the caller fills it with any
/// injected values (`Env`, `*Self`) after this returns.
///
/// Pass `&this_val` to `this_out` for class methods/constructors that
/// need the JS receiver; pass `null` for plain functions.
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

/// Convert the result of `@call(.auto, fn, args)` to a `napi_value`,
/// handling error unions, void returns, and `Val` passthrough. Returns
/// `null` if the user fn errored or the conversion failed (a JS
/// exception is pending in either case).
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
