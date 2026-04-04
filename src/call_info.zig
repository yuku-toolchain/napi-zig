/// Raw function call info.
///
/// Wraps `napi_callback_info` and provides helpers for extracting arguments
/// and the `this` value. Used by "raw mode" functions whose first parameter
/// is `Env`.

const c = @import("c.zig");
const Env = @import("env.zig").Env;
const Val = @import("val.zig").Val;
const check = @import("val.zig").check;

pub const CallInfo = struct {
    /// The underlying raw `napi_callback_info` handle.
    raw: c.napi_callback_info,

    /// Extracts up to `max` arguments from the call.
    ///
    /// If fewer than `max` arguments were actually passed, the missing
    /// positions are filled with JavaScript `undefined`.
    pub fn get(self: CallInfo, env: Env, comptime max: usize) ![max]Val {
        var arg_count: usize = max;
        var argv: [max]c.napi_value = undefined;
        try check(c.napi_get_cb_info(env.raw, self.raw, &arg_count, &argv, null, null));

        const undef = try env.createUndefined();
        var result: [max]Val = undefined;
        inline for (0..max) |i| {
            result[i] = if (i < arg_count) .{ .raw = argv[i] } else undef;
        }
        return result;
    }

    /// Returns the number of arguments the caller actually passed.
    pub fn argCount(self: CallInfo, env: Env) !usize {
        var count: usize = 0;
        try check(c.napi_get_cb_info(env.raw, self.raw, &count, null, null, null));
        return count;
    }

    /// Returns the `this` value of the function call.
    pub fn getThis(self: CallInfo, env: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_cb_info(env.raw, self.raw, null, null, &result, null));
        return .{ .raw = result };
    }
};
