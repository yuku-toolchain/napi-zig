const c = @import("c.zig");
const convert = @import("convert.zig");
const Env = @import("env.zig").Env;
const std = @import("std");

/// A JavaScript value handle, wrapping a raw `napi_value`.
///
/// Use `to*` methods to convert JS values into Zig types,
/// `get*`/`set*` for property and element access,
/// and `typeOf`/`is*` for introspection.
pub const Val = struct {
    raw: c.napi_value,

    /// Converts this JS value to a Zig type.
    ///
    /// Supports bool, integers, floats, optionals, enums, `[]const u8`,
    /// `[]T`, structs, and `Val` (passthrough). Slices and strings are
    /// allocated on `env.arena`.
    pub fn to(self: Val, env: Env, comptime T: type) !T {
        return convert.fromJs(T, env, self);
    }

    /// JS Boolean -> `bool`.
    pub fn toBool(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_get_value_bool(env.raw, self.raw, &result));
        return result;
    }

    /// JS Number -> `i32`.
    pub fn toInt32(self: Val, env: Env) !i32 {
        var result: i32 = undefined;
        try check(c.napi_get_value_int32(env.raw, self.raw, &result));
        return result;
    }

    /// JS Number -> `u32`.
    pub fn toUint32(self: Val, env: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_value_uint32(env.raw, self.raw, &result));
        return result;
    }

    /// JS Number -> `i64`.
    pub fn toInt64(self: Val, env: Env) !i64 {
        var result: i64 = undefined;
        try check(c.napi_get_value_int64(env.raw, self.raw, &result));
        return result;
    }

    /// JS Number -> `f64`.
    pub fn toFloat64(self: Val, env: Env) !f64 {
        var result: f64 = undefined;
        try check(c.napi_get_value_double(env.raw, self.raw, &result));
        return result;
    }

    /// JS BigInt -> `i64`.
    pub fn toBigintInt64(self: Val, env: Env) !i64 {
        var result: i64 = undefined;
        var lossless: bool = undefined;
        try check(c.napi_get_value_bigint_int64(env.raw, self.raw, &result, &lossless));
        return result;
    }

    /// JS BigInt -> `u64`.
    pub fn toBigintUint64(self: Val, env: Env) !u64 {
        var result: u64 = undefined;
        var lossless: bool = undefined;
        try check(c.napi_get_value_bigint_uint64(env.raw, self.raw, &result, &lossless));
        return result;
    }

    /// Returns the UTF-8 byte length of a JS String (excluding null terminator).
    pub fn getStringLength(self: Val, env: Env) !usize {
        var len: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, null, 0, &len));
        return len;
    }

    /// JS String -> caller-provided buffer as UTF-8.
    ///
    /// Returns the written sub-slice. Truncates if buffer is too small.
    pub fn toStringBuf(self: Val, env: Env, buf: []u8) ![]const u8 {
        var len: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, buf.ptr, buf.len, &len));
        return buf[0..len];
    }

    /// JS String -> heap-allocated UTF-8 buffer.
    ///
    /// Caller owns the memory. For arena-managed strings,
    /// use `val.to(env, []const u8)` instead.
    pub fn toStringAlloc(self: Val, env: Env, allocator: std.mem.Allocator) ![]u8 {
        const len = try self.getStringLength(env);
        const buf = try allocator.alloc(u8, len + 1);
        var written: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, buf.ptr, buf.len, &written));
        return buf[0..written];
    }

    /// Returns the JS type of this value.
    pub fn typeOf(self: Val, env: Env) !c.napi_valuetype {
        var result: c.napi_valuetype = undefined;
        try check(c.napi_typeof(env.raw, self.raw, &result));
        return result;
    }

    /// Returns `true` if this value is a JS Array.
    pub fn isArray(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_array(env.raw, self.raw, &result));
        return result;
    }

    /// Returns `true` if this value is a JS ArrayBuffer.
    pub fn isArrayBuffer(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_arraybuffer(env.raw, self.raw, &result));
        return result;
    }

    /// Returns `true` if this value is a Node.js Buffer.
    pub fn isBuffer(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_buffer(env.raw, self.raw, &result));
        return result;
    }

    /// Returns `true` if this value is a JS TypedArray.
    pub fn isTypedArray(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_typedarray(env.raw, self.raw, &result));
        return result;
    }

    /// Gets an object property by dynamic key.
    pub fn getProperty(self: Val, env: Env, key: Val) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_property(env.raw, self.raw, key.raw, &result));
        return .{ .raw = result };
    }

    /// Gets an object property by compile-time string key.
    pub fn getNamedProperty(self: Val, env: Env, key: [:0]const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_named_property(env.raw, self.raw, key, &result));
        return .{ .raw = result };
    }

    /// Sets an object property by dynamic key.
    pub fn setProperty(self: Val, env: Env, key: Val, value: Val) !void {
        try check(c.napi_set_property(env.raw, self.raw, key.raw, value.raw));
    }

    /// Sets an object property by compile-time string key.
    pub fn setNamedProperty(self: Val, env: Env, key: [:0]const u8, value: Val) !void {
        try check(c.napi_set_named_property(env.raw, self.raw, key, value.raw));
    }

    /// Returns `true` if the object has a property with the given key.
    pub fn hasNamedProperty(self: Val, env: Env, key: [:0]const u8) !bool {
        var result: bool = undefined;
        try check(c.napi_has_named_property(env.raw, self.raw, key, &result));
        return result;
    }

    /// Gets an array element by index.
    pub fn getElement(self: Val, env: Env, index: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_element(env.raw, self.raw, index, &result));
        return .{ .raw = result };
    }

    /// Sets an array element by index.
    pub fn setElement(self: Val, env: Env, index: u32, value: Val) !void {
        try check(c.napi_set_element(env.raw, self.raw, index, value.raw));
    }

    /// Returns the length of a JS Array.
    pub fn getArrayLength(self: Val, env: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_array_length(env.raw, self.raw, &result));
        return result;
    }

    /// Returns a Zig slice over the raw bytes of an ArrayBuffer.
    pub fn getArrayBufferData(self: Val, env: Env) ![]u8 {
        var data: ?*anyopaque = null;
        var len: usize = 0;
        try check(c.napi_get_arraybuffer_info(env.raw, self.raw, &data, &len));
        return if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{};
    }

    /// Returns a Zig slice over the raw bytes of a Node.js Buffer.
    pub fn getBufferData(self: Val, env: Env) ![]u8 {
        var data: ?*anyopaque = null;
        var len: usize = 0;
        try check(c.napi_get_buffer_info(env.raw, self.raw, &data, &len));
        return if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{};
    }

    /// Calls this value as a JS function.
    pub fn callFunction(self: Val, env: Env, this: Val, args: []const Val) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_call_function(
            env.raw,
            this.raw,
            self.raw,
            args.len,
            if (args.len > 0) @ptrCast(args.ptr) else null,
            &result,
        ));
        return .{ .raw = result };
    }
};

/// A strong reference to a JS value, preventing garbage collection.
/// Created via `Env.createReference`.
pub const Ref = struct {
    raw: c.napi_ref,

    /// Releases the reference. Must be called when no longer needed.
    pub fn delete(self: Ref, env: Env) !void {
        try check(c.napi_delete_reference(env.raw, self.raw));
    }

    /// Returns the referenced JS value.
    pub fn value(self: Ref, env: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_reference_value(env.raw, self.raw, &result));
        return .{ .raw = result };
    }
};

/// A deferred handle for resolving or rejecting a Promise.
/// Created via `Env.createPromise`, consumed on resolve/reject.
pub const Deferred = struct {
    raw: c.napi_deferred,

    /// Resolves the promise with the given value.
    pub fn resolve(self: Deferred, env: Env, val: Val) !void {
        try check(c.napi_resolve_deferred(env.raw, self.raw, val.raw));
    }

    /// Rejects the promise with the given value.
    pub fn reject(self: Deferred, env: Env, val: Val) !void {
        try check(c.napi_reject_deferred(env.raw, self.raw, val.raw));
    }
};

/// Raw function call info for extracting arguments and `this`.
pub const CallInfo = struct {
    raw: c.napi_callback_info,

    /// Extracts up to `max` arguments. Missing positions filled with `undefined`.
    pub fn getArgs(self: CallInfo, env: Env, comptime max: usize) ![max]Val {
        var arg_count: usize = max;
        if (max > 0) {
            var argv: [max]c.napi_value = undefined;
            try check(c.napi_get_cb_info(env.raw, self.raw, &arg_count, &argv, null, null));
            const undef = try env.createUndefined();
            var args: [max]Val = undefined;
            inline for (0..max) |i| {
                args[i] = if (i < arg_count) .{ .raw = argv[i] } else undef;
            }
            return args;
        } else {
            try check(c.napi_get_cb_info(env.raw, self.raw, &arg_count, null, null, null));
            return .{};
        }
    }

    /// Returns the number of arguments actually passed.
    pub fn getArgCount(self: CallInfo, env: Env) !usize {
        var count: usize = 0;
        try check(c.napi_get_cb_info(env.raw, self.raw, &count, null, null, null));
        return count;
    }

    /// Returns the `this` binding of the call.
    pub fn getThis(self: CallInfo, env: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_cb_info(env.raw, self.raw, null, null, &result, null));
        return .{ .raw = result };
    }
};

pub const NapiError = error{napi_error};

pub fn check(status: c.napi_status) NapiError!void {
    if (status != .ok) return error.napi_error;
}
