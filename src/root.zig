// public api surface

pub const c = @import("c.zig");

pub const Error = @import("error.zig").Error;

pub const Env = @import("env.zig").Env;

const val_mod = @import("val.zig");
pub const Val = val_mod.Val;
pub const Callback = val_mod.Callback;
pub const ThreadsafeFn = val_mod.ThreadsafeFn;
pub const CallInfo = val_mod.CallInfo;
pub const Ref = val_mod.Ref;
pub const Deferred = val_mod.Deferred;

pub const dts = @import("dts.zig");

pub const class = @import("class.zig").class;

/// register every pub declaration of the given struct as a node addon.
/// call from a comptime block at the top of your module file.
pub fn module(comptime Module: type) void {
    @import("module.zig").registerModule(Module);
}
