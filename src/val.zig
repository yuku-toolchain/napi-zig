const c = @import("c.zig");
const convert = @import("convert.zig");
const Env = @import("env.zig").Env;
const std = @import("std");

/// A JavaScript value handle, wrapping a raw `napi_value`.
///
/// Convert to Zig types with `to(env, T)`. Access properties with
/// `get*`/`set*`. Inspect with `typeOf`/`is*`.
pub const Val = struct {
    raw: c.napi_value,

    /// Converts this JS value to any supported Zig type.
    ///
    /// Supports bool, integers, floats, optionals, enums, `[]const u8`,
    /// `[]T`, structs, `Callback`, and `Val` (passthrough). Slices and
    /// strings are allocated on `env.arena`.
    pub fn to(self: Val, env: Env, comptime T: type) !T {
        return convert.fromJs(T, env, self);
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
};

/// A JS callback function handle.
///
/// Validated on conversion from JS, throws TypeError if the value is
/// not a function. Use `call` to invoke, `callWith` for a specific
/// `this` binding, or `threadsafe` to call from background threads.
pub const Callback = struct {
    val: Val,

    /// Calls the function with `undefined` as `this`.
    pub fn call(self: Callback, env: Env, args: []const Val) !Val {
        const undef = try env.createUndefined();
        return self.invoke(env, undef, args);
    }

    /// Calls the function with a specific `this` binding.
    pub fn callWith(self: Callback, env: Env, this: Val, args: []const Val) !Val {
        return self.invoke(env, this, args);
    }

    fn invoke(self: Callback, env: Env, this: Val, args: []const Val) !Val {
        var result: c.napi_value = undefined;
        try check(c.napi_call_function(
            env.raw,
            this.raw,
            self.val.raw,
            args.len,
            if (args.len > 0) @ptrCast(args.ptr) else null,
            &result,
        ));
        return .{ .raw = result };
    }

    /// Creates a threadsafe version of this function that can be called
    /// from any thread. Pass the data type the callback will receive,
    /// or `void` for no data. Call `release()` when done.
    pub fn threadsafe(self: Callback, env: Env, comptime name: [*:0]const u8, comptime T: type) !ThreadsafeFn(T) {
        var name_val: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(env.raw, name, c.NAPI_AUTO_LENGTH, &name_val));
        var result: c.napi_threadsafe_function = undefined;
        try check(c.napi_create_threadsafe_function(
            env.raw,
            self.val.raw,
            null,
            name_val,
            0,
            1,
            null,
            null,
            null,
            if (T == void) null else &ThreadsafeFn(T).callJs,
            &result,
        ));
        return .{ .raw = result };
    }
};

/// A thread-safe wrapper around a JS function, parameterized by the
/// data type passed to the callback. Use `void` for no data.
///
/// Created via `Callback.threadsafe(env, name, T)`. Must be released when done.
pub fn ThreadsafeFn(comptime T: type) type {
    return struct {
        raw: c.napi_threadsafe_function,

        const Self = @This();
        pub const CallMode = c.napi_threadsafe_function_call_mode;

        /// Queues a call to the JS function from any thread.
        /// The value is converted to JS and passed as the callback argument.
        pub fn call(self: Self, value: T, mode: CallMode) !void {
            if (T == void) {
                try check(c.napi_call_threadsafe_function(self.raw, null, mode));
            } else {
                const ptr = try std.heap.smp_allocator.create(T);
                ptr.* = value;
                if (c.napi_call_threadsafe_function(self.raw, ptr, mode) != .ok) {
                    std.heap.smp_allocator.destroy(ptr);
                    return error.napi_error;
                }
            }
        }

        /// Releases the function. Must be called when done.
        pub fn release(self: Self) !void {
            try check(c.napi_release_threadsafe_function(self.raw, .release));
        }

        /// Aborts the function, rejecting any pending calls.
        pub fn abort(self: Self) !void {
            try check(c.napi_release_threadsafe_function(self.raw, .abort));
        }

        /// Indicates a new thread will use this function.
        pub fn acquire(self: Self) !void {
            try check(c.napi_acquire_threadsafe_function(self.raw));
        }

        /// Prevents this function from keeping the event loop alive.
        pub fn unref(self: Self, env: Env) !void {
            try check(c.napi_unref_threadsafe_function(env.raw, self.raw));
        }

        /// Allows this function to keep the event loop alive (default).
        pub fn ref(self: Self, env: Env) !void {
            try check(c.napi_ref_threadsafe_function(env.raw, self.raw));
        }

        // called on the main thread by Node.js to convert data and invoke the JS callback.
        fn callJs(raw_env: c.napi_env, js_callback: c.napi_value, _: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
            const typed: *T = @ptrCast(@alignCast(data orelse return));
            defer std.heap.smp_allocator.destroy(typed);

            var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
            defer arena.deinit();
            const env: Env = .{ .raw = raw_env, .arena = &arena };

            const js_val = convert.toJs(T, env, typed.*) catch return;
            const undef = env.createUndefined() catch return;
            var result: c.napi_value = undefined;
            _ = c.napi_call_function(raw_env, undef.raw, js_callback, 1, @ptrCast(&js_val.raw), &result);
        }
    };
}

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

    /// Resolves the promise with the given JS value.
    pub fn resolve(self: Deferred, env: Env, value: Val) !void {
        try check(c.napi_resolve_deferred(env.raw, self.raw, value.raw));
    }

    /// Rejects the promise with the given JS value.
    pub fn reject(self: Deferred, env: Env, value: Val) !void {
        try check(c.napi_reject_deferred(env.raw, self.raw, value.raw));
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

const testing = @import("std").testing;

test "check returns void on ok status" {
    try check(.ok);
}

test "check returns error on invalid_arg" {
    try testing.expectError(error.napi_error, check(.invalid_arg));
}

test "check returns error on pending_exception" {
    try testing.expectError(error.napi_error, check(.pending_exception));
}

test "check returns error on generic_failure" {
    try testing.expectError(error.napi_error, check(.generic_failure));
}

test "check returns error on all non ok statuses" {
    const statuses = [_]c.napi_status{
        .object_expected,
        .string_expected,
        .function_expected,
        .number_expected,
        .boolean_expected,
        .array_expected,
        .cancelled,
        .queue_full,
        .closing,
        .would_deadlock,
    };
    for (statuses) |status| {
        try testing.expectError(error.napi_error, check(status));
    }
}
