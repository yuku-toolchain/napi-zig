const c = @import("c.zig");
const Val = @import("val.zig").Val;
const check = @import("val.zig").check;

/// wraps napi_env. all napi operations go through this.
pub const Env = struct {
    raw: c.napi_env,

    // primitives

    pub fn boolean(self: Env, value: bool) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_boolean(self.raw, value, &result));
        return .{ .raw = result };
    }

    pub fn int32(self: Env, value: i32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_int32(self.raw, value, &result));
        return .{ .raw = result };
    }

    pub fn uint32(self: Env, value: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_uint32(self.raw, value, &result));
        return .{ .raw = result };
    }

    pub fn int64(self: Env, value: i64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_int64(self.raw, value, &result));
        return .{ .raw = result };
    }

    pub fn float64(self: Env, value: f64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_double(self.raw, value, &result));
        return .{ .raw = result };
    }

    pub fn string(self: Env, str: []const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.raw, str.ptr, str.len, &result));
        return .{ .raw = result };
    }

    pub fn stringZ(self: Env, str: [*:0]const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.raw, str, c.NAPI_AUTO_LENGTH, &result));
        return .{ .raw = result };
    }

    pub fn bigintI64(self: Env, value: i64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_bigint_int64(self.raw, value, &result));
        return .{ .raw = result };
    }

    pub fn bigintU64(self: Env, value: u64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_bigint_uint64(self.raw, value, &result));
        return .{ .raw = result };
    }

    pub fn @"null"(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_null(self.raw, &result));
        return .{ .raw = result };
    }

    pub fn @"undefined"(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_undefined(self.raw, &result));
        return .{ .raw = result };
    }

    pub fn global(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_global(self.raw, &result));
        return .{ .raw = result };
    }

    // containers

    pub fn object(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_object(self.raw, &result));
        return .{ .raw = result };
    }

    pub fn array(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_array(self.raw, &result));
        return .{ .raw = result };
    }

    pub fn arrayWithLength(self: Env, len: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_array_with_length(self.raw, len, &result));
        return .{ .raw = result };
    }

    // functions

    pub fn function(self: Env, name: ?[*:0]const u8, cb: c.napi_callback) !Val {
        return self.functionWithData(name, cb, null);
    }

    pub fn functionWithData(self: Env, name: ?[*:0]const u8, cb: c.napi_callback, data: ?*anyopaque) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_function(self.raw, name, if (name) |_| c.NAPI_AUTO_LENGTH else 0, cb, data, &result));
        return .{ .raw = result };
    }

    // buffers

    pub fn arrayBuffer(self: Env, len: usize) !struct { val: Val, data: []u8 } {
        var data: ?*anyopaque = null;
        var result: c.napi_value = undefined;
        try check(c.napi_create_arraybuffer(self.raw, len, &data, &result));
        return .{
            .val = .{ .raw = result },
            .data = if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{},
        };
    }

    pub fn externalArrayBuffer(self: Env, data: [*]u8, len: usize, finalize_cb: ?c.napi_finalize, hint: ?*anyopaque) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_external_arraybuffer(self.raw, data, len, finalize_cb, hint, &result));
        return .{ .raw = result };
    }

    pub fn buffer(self: Env, len: usize) !struct { val: Val, data: []u8 } {
        var data: ?*anyopaque = null;
        var result: c.napi_value = undefined;
        try check(c.napi_create_buffer(self.raw, len, &data, &result));
        return .{
            .val = .{ .raw = result },
            .data = if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{},
        };
    }

    pub fn typedArray(self: Env, typ: c.napi_typedarray_type, len: usize, ab: Val, offset: usize) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_typedarray(self.raw, typ, len, ab.raw, offset, &result));
        return .{ .raw = result };
    }

    // errors

    pub fn throw(self: Env, err: Val) !void {
        try check(c.napi_throw(self.raw, err.raw));
    }

    pub fn throwError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_error(self.raw, null, msg);
    }

    pub fn throwTypeError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_type_error(self.raw, null, msg);
    }

    pub fn throwRangeError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_range_error(self.raw, null, msg);
    }

    pub fn isExceptionPending(self: Env) bool {
        var result: bool = false;
        _ = c.napi_is_exception_pending(self.raw, &result);
        return result;
    }

    // references

    pub fn createRef(self: Env, value: Val) !c.napi_ref {
        var result: c.napi_ref = undefined;
        try check(c.napi_create_reference(self.raw, value.raw, 1, &result));
        return result;
    }

    pub fn deleteRef(self: Env, ref: c.napi_ref) !void {
        try check(c.napi_delete_reference(self.raw, ref));
    }

    pub fn getRefValue(self: Env, ref: c.napi_ref) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_reference_value(self.raw, ref, &result));
        return .{ .raw = result };
    }

    // version

    pub fn napiVersion(self: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_version(self.raw, &result));
        return result;
    }
};
