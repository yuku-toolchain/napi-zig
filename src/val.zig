const c = @import("c.zig");
const Env = @import("env.zig").Env;

/// wraps a raw napi_value handle.
pub const Val = struct {
    raw: c.napi_value,


    // extract primitives

    pub fn getBoolean(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_get_value_bool(env.raw, self.raw, &result));
        return result;
    }

    pub fn getInt32(self: Val, env: Env) !i32 {
        var result: i32 = undefined;
        try check(c.napi_get_value_int32(env.raw, self.raw, &result));
        return result;
    }

    pub fn getUInt32(self: Val, env: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_value_uint32(env.raw, self.raw, &result));
        return result;
    }

    pub fn getInt64(self: Val, env: Env) !i64 {
        var result: i64 = undefined;
        try check(c.napi_get_value_int64(env.raw, self.raw, &result));
        return result;
    }

    pub fn getF64(self: Val, env: Env) !f64 {
        var result: f64 = undefined;
        try check(c.napi_get_value_double(env.raw, self.raw, &result));
        return result;
    }

    pub fn getBigintInt64(self: Val, env: Env) !i64 {
        var result: i64 = undefined;
        var lossless: bool = undefined;
        try check(c.napi_get_value_bigint_int64(env.raw, self.raw, &result, &lossless));
        return result;
    }

    pub fn getBigintUInt64(self: Val, env: Env) !u64 {
        var result: u64 = undefined;
        var lossless: bool = undefined;
        try check(c.napi_get_value_bigint_uint64(env.raw, self.raw, &result, &lossless));
        return result;
    }

    // strings

    pub fn stringLen(self: Val, env: Env) !usize {
        var len: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, null, 0, &len));
        return len;
    }

    pub fn stringBuf(self: Val, env: Env, buf: []u8) ![]const u8 {
        var len: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, buf.ptr, buf.len, &len));
        return buf[0..len];
    }

    pub fn stringAlloc(self: Val, env: Env, allocator: @import("std").mem.Allocator) ![]u8 {
        const len = try self.stringLen(env);
        const buf = try allocator.alloc(u8, len + 1);
        var written: usize = 0;
        try check(c.napi_get_value_string_utf8(env.raw, self.raw, buf.ptr, buf.len, &written));
        return buf[0..written];
    }

    // type checking

    pub fn typeOf(self: Val, env: Env) !c.napi_valuetype {
        var result: c.napi_valuetype = undefined;
        try check(c.napi_typeof(env.raw, self.raw, &result));
        return result;
    }

    pub fn isArray(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_array(env.raw, self.raw, &result));
        return result;
    }

    pub fn isArrayBuffer(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_arraybuffer(env.raw, self.raw, &result));
        return result;
    }

    pub fn isBuffer(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_buffer(env.raw, self.raw, &result));
        return result;
    }

    pub fn isTypedArray(self: Val, env: Env) !bool {
        var result: bool = undefined;
        try check(c.napi_is_typedarray(env.raw, self.raw, &result));
        return result;
    }

    // object property access

    pub fn getProperty(self: Val, env: Env, key: Val) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_property(env.raw, self.raw, key.raw, &result));
        return .{ .raw = result };
    }

    pub fn getNamed(self: Val, env: Env, key: [:0]const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_named_property(env.raw, self.raw, key, &result));
        return .{ .raw = result };
    }

    pub fn setProperty(self: Val, env: Env, key: Val, value: Val) !void {
        try check(c.napi_set_property(env.raw, self.raw, key.raw, value.raw));
    }

    pub fn setNamed(self: Val, env: Env, key: [:0]const u8, value: Val) !void {
        try check(c.napi_set_named_property(env.raw, self.raw, key, value.raw));
    }

    pub fn hasNamed(self: Val, env: Env, key: [:0]const u8) !bool {
        var result: bool = undefined;
        try check(c.napi_has_named_property(env.raw, self.raw, key, &result));
        return result;
    }

    // array element access

    pub fn getElement(self: Val, env: Env, index: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_element(env.raw, self.raw, index, &result));
        return .{ .raw = result };
    }

    pub fn setElement(self: Val, env: Env, index: u32, value: Val) !void {
        try check(c.napi_set_element(env.raw, self.raw, index, value.raw));
    }

    pub fn arrayLen(self: Val, env: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_array_length(env.raw, self.raw, &result));
        return result;
    }

    // buffer data access

    pub fn arrayBufferData(self: Val, env: Env) ![]u8 {
        var data: ?*anyopaque = null;
        var len: usize = 0;
        try check(c.napi_get_arraybuffer_info(env.raw, self.raw, &data, &len));
        return if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{};
    }

    pub fn bufferData(self: Val, env: Env) ![]u8 {
        var data: ?*anyopaque = null;
        var len: usize = 0;
        try check(c.napi_get_buffer_info(env.raw, self.raw, &data, &len));
        return if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{};
    }
};

pub const NapiError = error{napi_error};

pub fn check(status: c.napi_status) NapiError!void {
    if (status != .ok) return error.napi_error;
}
