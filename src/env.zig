const c = @import("c.zig");
const Val = @import("val.zig").Val;
const check = @import("val.zig").check;

/// The Node-API environment handle.
///
/// Wraps `napi_env` and exposes methods for creating JavaScript
/// values, throwing exceptions, managing references, and scheduling async work.
pub const Env = struct {
    /// the underlying raw `napi_env` handle from Node.js.
    raw: c.napi_env,

    /// Creates a JavaScript `Boolean` value.
    pub fn createBoolean(self: Env, value: bool) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_boolean(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `Number` from a signed 32-bit integer.
    pub fn createInt32(self: Env, value: i32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_int32(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `Number` from an unsigned 32-bit integer.
    pub fn createUint32(self: Env, value: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_uint32(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `Number` from a signed 64-bit integer.
    ///
    /// Note: JavaScript numbers are IEEE-754 doubles and can only represent
    /// integers exactly up to 2^53. For values outside that range, use
    /// `createBigintInt64` instead.
    pub fn createInt64(self: Env, value: i64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_int64(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `Number` from a 64-bit float (double).
    pub fn createFloat64(self: Env, value: f64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_double(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `String` from a UTF-8 byte slice.
    pub fn createString(self: Env, str: []const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.raw, str.ptr, str.len, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `String` from a null-terminated UTF-8 string.
    pub fn createStringZ(self: Env, str: [*:0]const u8) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.raw, str, c.NAPI_AUTO_LENGTH, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `BigInt` from a signed 64-bit integer.
    pub fn createBigintInt64(self: Env, value: i64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_bigint_int64(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `BigInt` from an unsigned 64-bit integer.
    pub fn createBigintUint64(self: Env, value: u64) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_bigint_uint64(self.raw, value, &result));
        return .{ .raw = result };
    }

    /// Returns the JavaScript `null` value.
    pub fn createNull(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_null(self.raw, &result));
        return .{ .raw = result };
    }

    /// Returns the JavaScript `undefined` value.
    pub fn createUndefined(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_undefined(self.raw, &result));
        return .{ .raw = result };
    }

    /// Returns the JavaScript `global` object (equivalent to `globalThis`).
    pub fn getGlobal(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_global(self.raw, &result));
        return .{ .raw = result };
    }

    /// Creates an empty JavaScript plain object (`{}`).
    pub fn createObject(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_object(self.raw, &result));
        return .{ .raw = result };
    }

    /// Creates an empty JavaScript `Array`.
    pub fn createArray(self: Env) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_array(self.raw, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript `Array` pre-allocated to the given length.
    pub fn createArrayWithLength(self: Env, len: u32) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_array_with_length(self.raw, len, &result));
        return .{ .raw = result };
    }

    /// Creates a JavaScript function backed by a native callback.
    ///
    /// `name` is used for `Function.name` in JS (pass `null` for anonymous).
    pub fn createFunction(self: Env, name: ?[*:0]const u8, cb: c.napi_callback) !Val {
        return self.createFunctionWithData(name, cb, null);
    }

    /// Creates a JavaScript function backed by a native callback, with an
    /// opaque data pointer that will be passed to every invocation.
    pub fn createFunctionWithData(self: Env, name: ?[*:0]const u8, cb: c.napi_callback, data: ?*anyopaque) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_function(self.raw, name, if (name) |_| c.NAPI_AUTO_LENGTH else 0, cb, data, &result));
        return .{ .raw = result };
    }

    /// Creates a new JavaScript `ArrayBuffer` of the given byte length.
    ///
    /// Returns both the JS value and a Zig slice pointing to the backing memory
    /// so you can write into the buffer directly.
    pub fn createArrayBuffer(self: Env, len: usize) !struct { val: Val, data: []u8 } {
        var data: ?*anyopaque = null;
        var result: c.napi_value = undefined;
        try check(c.napi_create_arraybuffer(self.raw, len, &data, &result));
        return .{
            .val = .{ .raw = result },
            .data = if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{},
        };
    }

    /// Creates a JavaScript `ArrayBuffer` backed by externally-owned memory.
    ///
    /// The caller is responsible for the lifetime of `data`. Provide a
    /// `finalize_cb` to be notified when the JS engine is done with the buffer.
    pub fn createExternalArrayBuffer(self: Env, data: [*]u8, len: usize, finalize_cb: ?c.napi_finalize, hint: ?*anyopaque) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_external_arraybuffer(self.raw, data, len, finalize_cb, hint, &result));
        return .{ .raw = result };
    }

    /// Creates a new Node.js `Buffer` of the given byte length.
    ///
    /// Returns both the JS value and a Zig slice pointing to the backing memory.
    pub fn createBuffer(self: Env, len: usize) !struct { val: Val, data: []u8 } {
        var data: ?*anyopaque = null;
        var result: c.napi_value = undefined;
        try check(c.napi_create_buffer(self.raw, len, &data, &result));
        return .{
            .val = .{ .raw = result },
            .data = if (data) |ptr| @as([*]u8, @ptrCast(ptr))[0..len] else &.{},
        };
    }

    /// Creates a JavaScript `TypedArray` view over an existing `ArrayBuffer`.
    ///
    /// `typ` selects the element type (e.g. `napi_uint8_array`).
    /// `len` is the number of *elements* (not bytes).
    /// `offset` is the byte offset into the backing `ArrayBuffer`.
    pub fn createTypedArray(self: Env, typ: c.napi_typedarray_type, len: usize, ab: Val, offset: usize) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_create_typedarray(self.raw, typ, len, ab.raw, offset, &result));
        return .{ .raw = result };
    }

    /// Throws an existing JavaScript value as an exception.
    ///
    /// Use this when you already have an `Error` object (or any JS value) to throw.
    /// For convenience helpers that create-and-throw in one step, see
    /// `throwError`, `throwTypeError`, and `throwRangeError`.
    pub fn throwValue(self: Env, err: Val) !void {
        try check(c.napi_throw(self.raw, err.raw));
    }

    /// Creates and throws a JavaScript `Error` with the given message.
    pub fn throwError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_error(self.raw, null, msg);
    }

    /// Creates and throws a JavaScript `TypeError` with the given message.
    pub fn throwTypeError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_type_error(self.raw, null, msg);
    }

    /// Creates and throws a JavaScript `RangeError` with the given message.
    pub fn throwRangeError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_range_error(self.raw, null, msg);
    }

    /// Returns `true` if a JavaScript exception is pending (has been thrown
    /// but not yet caught by the engine).
    pub fn isExceptionPending(self: Env) bool {
        var result: bool = false;
        _ = c.napi_is_exception_pending(self.raw, &result);
        return result;
    }

    /// Creates a strong reference to a JavaScript value so it is not
    /// garbage-collected. The initial reference count is 1.
    ///
    /// You must call `deleteReference` when the reference is no longer needed.
    pub fn createReference(self: Env, value: Val) !c.napi_ref {
        var result: c.napi_ref = undefined;
        try check(c.napi_create_reference(self.raw, value.raw, 1, &result));
        return result;
    }

    /// Deletes a reference previously created with `createReference`.
    pub fn deleteReference(self: Env, ref: c.napi_ref) !void {
        try check(c.napi_delete_reference(self.raw, ref));
    }

    /// Retrieves the JavaScript value held by a reference.
    ///
    /// If the reference has been invalidated (ref-count dropped to 0 and the
    /// value was GC'd), the returned `Val` may wrap a null handle.
    pub fn getReferenceValue(self: Env, ref: c.napi_ref) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_get_reference_value(self.raw, ref, &result));
        return .{ .raw = result };
    }

    /// Returns the highest Node-API version supported by this Node.js runtime.
    pub fn getVersion(self: Env) !u32 {
        var result: u32 = undefined;
        try check(c.napi_get_version(self.raw, &result));
        return result;
    }

    /// Creates a new JavaScript `Promise` together with its deferred handle.
    ///
    /// Resolve or reject the promise by calling `resolveDeferred` /
    /// `rejectDeferred` with the returned `deferred` handle.
    pub fn createPromise(self: Env) !struct { promise: Val, deferred: c.napi_deferred } {
        var deferred: c.napi_deferred = undefined;
        var promise: c.napi_value = undefined;
        try check(c.napi_create_promise(self.raw, &deferred, &promise));
        return .{ .promise = .{ .raw = promise }, .deferred = deferred };
    }

    /// Resolves a deferred promise with the given value.
    ///
    /// The `deferred` handle is consumed and must not be reused.
    pub fn resolveDeferred(self: Env, deferred: c.napi_deferred, value: Val) !void {
        try check(c.napi_resolve_deferred(self.raw, deferred, value.raw));
    }

    /// Rejects a deferred promise with the given value (typically an `Error`).
    ///
    /// The `deferred` handle is consumed and must not be reused.
    pub fn rejectDeferred(self: Env, deferred: c.napi_deferred, value: Val) !void {
        try check(c.napi_reject_deferred(self.raw, deferred, value.raw));
    }

    /// Creates an async work item that executes `execute` on a worker thread,
    /// then calls `complete` back on the main JS thread.
    ///
    /// `name` is a human-readable label used by `async_hooks`.
    /// `data` is an opaque pointer forwarded to both callbacks.
    pub fn createAsyncWork(
        self: Env,
        name: [*:0]const u8,
        execute: c.napi_async_execute_callback,
        complete: c.napi_async_complete_callback,
        data: ?*anyopaque,
    ) !c.napi_async_work {
        var name_val: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.raw, name, @import("c.zig").NAPI_AUTO_LENGTH, &name_val));
        var work: c.napi_async_work = undefined;
        try check(c.napi_create_async_work(self.raw, null, name_val, execute, complete, data, &work));
        return work;
    }

    /// Schedules a previously created async work item for execution.
    pub fn queueAsyncWork(self: Env, work: c.napi_async_work) !void {
        try check(c.napi_queue_async_work(self.raw, work));
    }

    /// Frees the resources associated with an async work item.
    ///
    /// Must be called after the work has completed or been cancelled.
    pub fn deleteAsyncWork(self: Env, work: c.napi_async_work) !void {
        try check(c.napi_delete_async_work(self.raw, work));
    }
};
