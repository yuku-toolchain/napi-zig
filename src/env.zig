const std = @import("std");
const c = @import("c.zig");
const convert = @import("convert.zig");
const val_mod = @import("val.zig");
const Val = val_mod.Val;
const Ref = val_mod.Ref;
const Deferred = val_mod.Deferred;
const check = val_mod.check;

/// The Node-API environment handle, wrapping `napi_env`.
///
/// Provides methods for creating JS values, throwing exceptions,
/// and managing references. The `arena` is a per-call allocator,
/// freed automatically when the function returns.
pub const Env = struct {
    raw: c.napi_env,

    /// Per-call arena, freed when the function returns.
    arena: *std.heap.ArenaAllocator,

    /// Converts a Zig value to a JS value. Type is inferred.
    pub fn toJs(self: Env, value: anytype) !Val {
        return convert.toJs(@TypeOf(value), self, value);
    }

    /// bool -> JS Boolean.
    pub fn createBoolean(self: Env, value: bool) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_boolean(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// i32 -> JS Number.
    pub fn createInt32(self: Env, value: i32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_int32(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// u32 -> JS Number.
    pub fn createUint32(self: Env, value: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_uint32(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// i64 -> JS Number. Exact only up to 2^53, use `createBigintInt64` beyond.
    pub fn createInt64(self: Env, value: i64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_int64(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// f64 -> JS Number.
    pub fn createFloat64(self: Env, value: f64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_double(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// UTF-8 slice -> JS String.
    pub fn createString(self: Env, str: []const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.raw, str.ptr, str.len, &result));
        return .{ .raw = result };
    }

    /// Null-terminated UTF-8 -> JS String.
    pub fn createStringZ(self: Env, str: [*:0]const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.raw, str, c.NAPI_AUTO_LENGTH, &result));
        return .{ .raw = result };
    }

    /// i64 -> JS BigInt.
    pub fn createBigintInt64(self: Env, value: i64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_bigint_int64(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// u64 -> JS BigInt.
    pub fn createBigintUint64(self: Env, value: u64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_bigint_uint64(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// Returns JS `null`.
    pub fn createNull(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_null(self.raw, &result));
        return .{ .raw = result };
    }

    /// Returns JS `undefined`.
    pub fn createUndefined(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_undefined(self.raw, &result));
        return .{ .raw = result };
    }

    /// Returns JS `globalThis`.
    pub fn getGlobal(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_global(self.raw, &result));
        return .{ .raw = result };
    }

    /// Creates an empty JS object (`{}`).
    pub fn createObject(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_object(self.raw, &result));
        return .{ .raw = result };
    }

    /// Creates an empty JS Array.
    pub fn createArray(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_array(self.raw, &result));
        return .{ .raw = result };
    }

    /// Creates a JS Array pre-allocated to `len` elements.
    pub fn createArrayWithLength(self: Env, len: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_array_with_length(self.raw, len, &result));
        return .{ .raw = result };
    }

    /// Creates a JS function backed by a native callback.
    pub fn createFunction(self: Env, name: ?[*:0]const u8, cb: c.napi_callback) !Val {
        return self.createFunctionWithData(name, cb, null);
    }

    /// Creates a JS function with an opaque data pointer passed to every call.
    pub fn createFunctionWithData(self: Env, name: ?[*:0]const u8, cb: c.napi_callback, data: ?*anyopaque) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_function(self.raw, name, if (name) |_| c.NAPI_AUTO_LENGTH else 0, cb, data, &result));
        return .{ .raw = result };
    }

    /// Creates an ArrayBuffer. Returns JS value + writable Zig slice.
    pub fn createArrayBuffer(self: Env, len: usize) !struct { val: Val, data: []u8 } {
        var data: ?*anyopaque = null;
        var result: c.napi_value = undefined;
        try check(c.napi_create_arraybuffer(self.raw, len, &data, &result));
        return .{
            .val = .{ .raw = result },
            .data = if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{},
        };
    }

    /// Creates an ArrayBuffer backed by externally-owned memory.
    pub fn createExternalArrayBuffer(self: Env, data: [*]u8, len: usize, finalize_cb: ?c.napi_finalize, hint: ?*anyopaque) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_external_arraybuffer(self.raw, data, len, finalize_cb, hint, &result));
        return .{ .raw = result };
    }

    /// Creates a Node.js Buffer. Returns JS value + writable Zig slice.
    pub fn createBuffer(self: Env, len: usize) !struct { val: Val, data: []u8 } {
        var data: ?*anyopaque = null;
        var result: c.napi_value = undefined;
        try check(c.napi_create_buffer(self.raw, len, &data, &result));
        return .{
            .val = .{ .raw = result },
            .data = if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{},
        };
    }

    /// Creates a TypedArray view over an ArrayBuffer.
    pub fn createTypedArray(self: Env, typ: c.napi_typedarray_type, len: usize, ab: Val, offset: usize) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_typedarray(self.raw, typ, len, ab.raw, offset, &result));
        return .{ .raw = result };
    }

    /// Throws an existing JS value as an exception.
    pub fn throwValue(self: Env, err: Val) !void {
        try check(c.napi_throw(self.raw, err.raw));
    }

    /// Throws a JS Error.
    pub fn throwError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_error(self.raw, null, msg);
    }

    /// Throws a JS TypeError.
    pub fn throwTypeError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_type_error(self.raw, null, msg);
    }

    /// Throws a JS RangeError.
    pub fn throwRangeError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_range_error(self.raw, null, msg);
    }

    /// Returns `true` if a JS exception is pending.
    pub fn isExceptionPending(self: Env) bool {
        var result: bool = false;
        _ = c.napi_is_exception_pending(self.raw, &result);
        return result;
    }

    /// Creates a strong reference preventing GC. Call `ref.delete(env)` to release.
    pub fn createReference(self: Env, value: Val) !Ref {
        var result: c.napi_ref = undefined;
        try check(c.napi_create_reference(self.raw, value.raw, 1, &result));
        return .{ .raw = result };
    }

    const Promise = struct {
        promise: Val,
        deferred: Deferred,
    };

    /// Creates a Promise + Deferred pair. Use `deferred.resolve`/`reject`.
    pub fn createPromise(self: Env) !Promise {
        var deferred: c.napi_deferred = undefined;
        var promise: c.napi_value = undefined;
        try check(c.napi_create_promise(self.raw, &deferred, &promise));
        return .{ .promise = .{ .raw = promise }, .deferred = .{ .raw = deferred } };
    }

    /// Creates an async work item. Runs `execute` on a worker thread,
    /// then `complete` on the main JS thread.
    pub fn createAsyncWork(
        self: Env,
        name: [*:0]const u8,
        execute: c.napi_async_execute_callback,
        complete: c.napi_async_complete_callback,
        data: ?*anyopaque,
    ) !c.napi_async_work {
        var name_val: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.raw, name, c.NAPI_AUTO_LENGTH, &name_val));
        var work: c.napi_async_work = undefined;
        try check(c.napi_create_async_work(self.raw, null, name_val, execute, complete, data, &work));
        return work;
    }

    /// Queues an async work item for execution.
    pub fn queueAsyncWork(self: Env, work: c.napi_async_work) !void {
        try check(c.napi_queue_async_work(self.raw, work));
    }

    /// Frees an async work item. Call after the work completes.
    pub fn deleteAsyncWork(self: Env, work: c.napi_async_work) !void {
        try check(c.napi_delete_async_work(self.raw, work));
    }

    /// Returns the highest Node-API version supported by this runtime.
    pub fn getVersion(self: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_version(self.raw, &result));
        return result;
    }
};
