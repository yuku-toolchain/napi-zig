pub const c = @import("c.zig");

pub const Env = @import("env.zig").Env;
pub const Val = @import("val.zig").Val;

pub const NapiError = @import("val.zig").NapiError;
pub const CallInfo = @import("val.zig").CallInfo;

pub const napi_module_version = @import("module.zig").napi_module_version;

/// Registers all public declarations from `Module` as a Node.js native addon.
pub fn module(comptime Module: type) void {
    @import("module.zig").registerModule(Module);
}
