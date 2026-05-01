// napi-zig — write Node.js native addons in idiomatic Zig.
//
// Quick start:
//
//   const napi = @import("napi-zig");
//
//   comptime { napi.module(@This()); }
//
//   pub fn add(a: i32, b: i32) i32 { return a + b; }
//
// Every public declaration of the root module is exported to JS:
// functions become JS functions, constants become JS properties,
// nested structs (with their own pub items) become JS namespaces.
// snake_case names are translated to camelCase automatically.

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

const module_mod = @import("module.zig");

/// Register every `pub` declaration of the root struct as a Node.js
/// native addon. Call from a `comptime` block at the top of your
/// module file:
///
///     comptime { napi.module(@This()); }
///
/// What gets exported:
///
///   pub fn name(...) -> JS function (snake_case → camelCase)
///   pub const x: T   -> JS property (when T has a JS-mappable value)
///   pub const ns = struct { pub fn ... }  -> nested JS namespace
///
/// Function signatures may optionally start with:
///
///   fn(env: napi.Env, ...)       — Env injected, no JS arg consumed
///   fn(env: napi.Env, info: napi.CallInfo)  — raw call info for variadics
pub fn module(comptime Module: type) void {
    module_mod.registerModule(Module);
}
