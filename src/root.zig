/// Public entry point for the `napi-zig` module.
///
/// Re-exports every type and function that addon authors need:
///
/// ```zig
/// const napi = @import("napi-zig");
///
/// pub const version = "1.0.0";
/// pub const max_retries: i32 = 3;
///
/// pub fn add(a: i32, b: i32) i32 { return a + b; }
///
/// comptime { napi.module(@This()); }
/// ```

pub const c = @import("c.zig");
pub const Env = @import("env.zig").Env;
pub const Val = @import("val.zig").Val;
pub const NapiError = @import("val.zig").NapiError;
pub const check = @import("val.zig").check;
pub const CallInfo = @import("call_info.zig").CallInfo;

pub const toJs = @import("convert.zig").toJs;
pub const fromJs = @import("convert.zig").fromJs;

/// N-API module ABI version exported by this library.
pub const napi_module_version = @import("module.zig").napi_module_version;

/// Registers all public declarations from `Module` as a Node.js native addon.
///
/// Call this in a `comptime` block at the top level of your root source file:
///
/// ```zig
/// const napi = @import("napi-zig");
///
/// pub const version = "1.0.0";
/// pub fn add(a: i32, b: i32) i32 { return a + b; }
///
/// comptime { napi.module(@This()); }
/// ```
///
/// - Every `pub fn` (except those starting with `_`) is exported as a JS function.
/// - Every `pub const` with a JS-compatible type is exported as a JS value.
/// - Snake_case names are automatically converted to camelCase.
pub fn module(comptime Module: type) void {
    @import("module.zig").registerModule(Module);
}
