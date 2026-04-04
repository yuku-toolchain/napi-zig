pub const c = @import("c.zig");
pub const Env = @import("env.zig").Env;
pub const Val = @import("val.zig").Val;
pub const NapiError = @import("val.zig").NapiError;
pub const check = @import("val.zig").check;

pub const toJs = @import("convert.zig").toJs;
pub const fromJs = @import("convert.zig").fromJs;

/// raw function call info. wraps napi_callback_info for raw-mode functions.
pub const CallInfo = struct {
    raw: c.napi_callback_info,

    /// extract up to `max` arguments.
    pub fn get(self: CallInfo, env: Env, comptime max: usize) ![max]Val {
        var arg_count: usize = max;
        var argv: [max]c.napi_value = undefined;
        try check(c.napi_get_cb_info(env.raw, self.raw, &arg_count, &argv, null, null));

        var result: [max]Val = undefined;
        inline for (0..max) |i| {
            result[i] = if (i < arg_count) .{ .raw = argv[i] } else Val.null_val;
        }
        return result;
    }

    /// get the number of arguments passed.
    pub fn argCount(self: CallInfo, env: Env) !usize {
        var count: usize = 0;
        try check(c.napi_get_cb_info(env.raw, self.raw, &count, null, null, null));
        return count;
    }

    /// get `this` value.
    pub fn getThis(self: CallInfo, env: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_cb_info(env.raw, self.raw, null, null, &result, null));
        return .{ .raw = result };
    }
};

/// napi module version.
pub const napi_module_version: u32 = 1;

/// usage: `comptime { napi.module(@This()); }`
pub fn module(comptime Module: type) void {
    @import("auto.zig").registerModule(Module);
}
