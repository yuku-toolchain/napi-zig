pub const c = @import("c.zig");

pub const Env = @import("env.zig").Env;

const val_mod = @import("val.zig");
pub const Val = val_mod.Val;
pub const Callback = val_mod.Callback;
pub const ThreadsafeFn = val_mod.ThreadsafeFn;
pub const CallInfo = val_mod.CallInfo;
pub const Ref = val_mod.Ref;
pub const Deferred = val_mod.Deferred;

/// Registers all public declarations from `Module` as a Node.js native addon.
///
/// Standard mode, args and return auto-converted:
///
///     pub fn add(a: i32, b: i32) i32 {
///         return a + b;
///     }
///
/// Standard mode with `Env` for callbacks, allocations, or manual JS creation:
///
///     pub fn greet(env: napi.Env, callback: napi.Callback, name: []const u8) !napi.Val {
///         return callback.call(env, &.{try env.toJs(name)});
///     }
///
/// Raw mode for full manual control:
///
///     pub fn custom(env: napi.Env, info: napi.CallInfo) !napi.Val {
///         const args = try info.getArgs(env, 1);
///         return args[0];
///     }
pub fn module(comptime Module: type) void {
    @import("module.zig").registerModule(Module);
}
