pub const c = @import("c.zig");

pub const Env = @import("env.zig").Env;

const val_mod = @import("val.zig");
pub const Val = val_mod.Val;
pub const CallInfo = val_mod.CallInfo;
pub const Ref = val_mod.Ref;
pub const Deferred = val_mod.Deferred;

/// Registers all public declarations from `Module` as a Node.js native addon.
pub fn module(comptime Module: type) void {
    @import("module.zig").registerModule(Module);
}
