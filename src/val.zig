const c = @import("c.zig");
const Env = @import("env.zig").Env;
const std = @import("std");

const Allocator = std.mem.Allocator;

/// A JavaScript value handle.
///
/// Wraps a raw `napi_value` and provides methods for extracting primitive data,
/// inspecting types, and accessing object properties, array elements, and
/// buffer contents
pub const Val = struct {
    /// the underlying raw `napi_value` handle.
    raw: c.napi_value,

    /// Extracts the boolean value from a JavaScript `Boolean`.
    pub fn getBoolean(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_get_value_bool(env.raw, self.raw, &result));
        return result;
    }

    /// Extracts a signed 32-bit integer from a JavaScript `Number`.
    pub fn getInt32(self: Val, env: Env) !i32 {
        var result: i32 = undefined;
        try check(c.napi_get_value_int32(env.raw, self.raw, &result));
        return result;
    }

    /// Extracts an unsigned 32-bit integer from a JavaScript `Number`.
    pub fn getUint32(self: Val, env: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_value_uint32(env.raw, self.raw, &result));
        return result;
    }

    /// Extracts a signed 64-bit integer from a JavaScript `Number`.
    pub fn getInt64(self: Val, env: Env) !i64 {
        var result: i64 = undefined;
        try check(c.napi_get_value_int64(env.raw, self.raw, &result));
        return result;
    }

    /// Extracts a 64-bit float (double) from a JavaScript `Number`.
    pub fn getFloat64(self: Val, env: Env) !f64 {
        var result: f64 = undefined;
        try check(c.napi_get_value_double(env.raw, self.raw, &result));
        return result;
    }

    /// Extracts a signed 64-bit integer from a JavaScript `BigInt`.
    pub fn getBigintInt64(self: Val, env: Env) !i64 {
        var result: i64 = undefined;
        var lossless: bool = undefined;
        try check(c.napi_get_value_bigint_int64(env.raw, self.raw, &result, &lossless));
        return result;
    }

    /// Extracts an unsigned 64-bit integer from a JavaScript `BigInt`.
    pub fn getBigintUint64(self: Val, env: Env) !u64 {
        var result: u64 = undefined;
        var lossless: bool = undefined;
        try check(c.napi_get_value_bigint_uint64(env.raw, self.raw, &result, &lossless));
        return result;
    }

    /// Returns the UTF-8 byte length of a JavaScript `String`
    /// (excluding any null terminator).
    pub fn getStringLength(self: Val, env: Env) !usize {
        var len: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, null, 0, &len));
        return len;
    }

    /// Copies a JavaScript `String` into the caller-provided buffer as UTF-8.
    ///
    /// Returns the sub-slice of `buf` that was actually written.
    /// If the buffer is too small the string is truncated.
    pub fn getStringIntoBuf(self: Val, env: Env, buf: []u8) ![]const u8 {
        var len: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, buf.ptr, buf.len, &len));
        return buf[0..len];
    }

    /// Allocates a buffer and copies the JavaScript `String` into it as UTF-8.
    ///
    /// The caller owns the returned memory and must free it with the same
    /// `allocator`.
    pub fn allocString(self: Val, env: Env, allocator: Allocator) ![]u8 {
        const len = try self.getStringLength(env);
        const buf = try allocator.alloc(u8, len + 1);
        var written: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, buf.ptr, buf.len, &written));
        return buf[0..written];
    }

    /// Returns the `napi_valuetype` of this value (e.g. `.string`, `.number`,
    /// `.object`, `.function`, etc.).
    pub fn typeOf(self: Val, env: Env) !c.napi_valuetype {
        var result: c.napi_valuetype = undefined;
        try check(c.napi_typeof(env.raw, self.raw, &result));
        return result;
    }

    /// Returns `true` if this value is a JavaScript `Array`.
    pub fn isArray(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_array(env.raw, self.raw, &result));
        return result;
    }

    /// Returns `true` if this value is a JavaScript `ArrayBuffer`.
    pub fn isArrayBuffer(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_arraybuffer(env.raw, self.raw, &result));
        return result;
    }

    /// Returns `true` if this value is a Node.js `Buffer`.
    pub fn isBuffer(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_buffer(env.raw, self.raw, &result));
        return result;
    }

    /// Returns `true` if this value is a JavaScript `TypedArray`.
    pub fn isTypedArray(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_typedarray(env.raw, self.raw, &result));
        return result;
    }

    /// Gets an object property by a dynamic key (another `Val`).
    pub fn getProperty(self: Val, env: Env, key: Val) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_property(env.raw, self.raw, key.raw, &result));
        return .{ .raw = result };
    }

    /// Gets an object property by a compile-time-known string key.
    pub fn getNamedProperty(self: Val, env: Env, key: [:0]const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_named_property(env.raw, self.raw, key, &result));
        return .{ .raw = result };
    }

    /// Sets an object property by a dynamic key (another `Val`).
    pub fn setProperty(self: Val, env: Env, key: Val, value: Val) !void {
        try check(c.napi_set_property(env.raw, self.raw, key.raw, value.raw));
    }

    /// Sets an object property by a compile-time-known string key.
    pub fn setNamedProperty(self: Val, env: Env, key: [:0]const u8, value: Val) !void {
        try check(c.napi_set_named_property(env.raw, self.raw, key, value.raw));
    }

    /// Returns `true` if the object has a property with the given string key.
    pub fn hasNamedProperty(self: Val, env: Env, key: [:0]const u8) !bool {
        var result: bool = undefined;
        try check(c.napi_has_named_property(env.raw, self.raw, key, &result));
        return result;
    }

    /// Gets an element from a JavaScript `Array` by numeric index.
    pub fn getElement(self: Val, env: Env, index: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_element(env.raw, self.raw, index, &result));
        return .{ .raw = result };
    }

    /// Sets an element in a JavaScript `Array` at the given numeric index.
    pub fn setElement(self: Val, env: Env, index: u32, value: Val) !void {
        try check(c.napi_set_element(env.raw, self.raw, index, value.raw));
    }

    /// Returns the `.length` of a JavaScript `Array`.
    pub fn getArrayLength(self: Val, env: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_array_length(env.raw, self.raw, &result));
        return result;
    }

    /// Returns a Zig slice over the raw bytes of an `ArrayBuffer`.
    pub fn getArrayBufferData(self: Val, env: Env) ![]u8 {
        var data: ?*anyopaque = null;
        var len: usize = 0;
        try check(c.napi_get_arraybuffer_info(env.raw, self.raw, &data, &len));
        return if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{};
    }

    /// Returns a Zig slice over the raw bytes of a Node.js `Buffer`.
    pub fn getBufferData(self: Val, env: Env) ![]u8 {
        var data: ?*anyopaque = null;
        var len: usize = 0;
        try check(c.napi_get_buffer_info(env.raw, self.raw, &data, &len));
        return if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{};
    }

    /// Calls this value as a JavaScript function.
    ///
    /// `this` is the receiver (`this` inside the function).
    /// Pass a slice of `Val` as arguments.
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

/// Raw function call info.
///
/// Wraps `napi_callback_info` for extracting arguments and `this`.
/// Used by "raw mode" functions whose first parameter is `Env`.
pub const CallInfo = struct {
    /// the underlying raw `napi_callback_info` handle.
    raw: c.napi_callback_info,

    /// Extracts up to `max` arguments and returns the actual count passed.
    ///
    /// Args beyond what was actually passed are filled with `undefined`.
    pub fn getArgs(self: CallInfo, env: Env, comptime max: usize) !struct { args: [max]Val, len: usize } {
        var arg_count: usize = max;
        if (max > 0) {
            var argv: [max]c.napi_value = undefined;
            try check(c.napi_get_cb_info(env.raw, self.raw, &arg_count, &argv, null, null));
            const undef = try env.createUndefined();
            var args: [max]Val = undefined;
            inline for (0..max) |i| {
                args[i] = if (i < arg_count) .{ .raw = argv[i] } else undef;
            }
            return .{ .args = args, .len = arg_count };
        } else {
            try check(c.napi_get_cb_info(env.raw, self.raw, &arg_count, null, null, null));
            return .{ .args = .{}, .len = arg_count };
        }
    }

    /// Extracts up to `max` arguments from the call.
    ///
    /// If fewer than `max` arguments were actually passed, the missing
    /// positions are filled with JavaScript `undefined`.
    pub fn get(self: CallInfo, env: Env, comptime max: usize) ![max]Val {
        return (try self.getArgs(env, max)).args;
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

/// Error type returned by all Node-API wrapper functions.
pub const NapiError = error{napi_error};

/// Checks an `napi_status` and returns `error.napi_error` on failure.
pub fn check(status: c.napi_status) NapiError!void {
    if (status != .ok) return error.napi_error;
}
