const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const convert = @import("convert.zig");
const env_mod = @import("env.zig");
const util = @import("util.zig");

const Env = env_mod.Env;
const check = err.check;

/// result of reading a js bigint into a fixed-width zig int. `lossless`
/// is false if the source bigint did not fit (sign or magnitude).
pub fn BigIntFit(comptime T: type) type {
    return struct {
        value: T,
        lossless: bool,
    };
}

/// opaque handle to a js value, valid only within the current call.
/// extern layout guarantees `[]const Val` is castable to `[*]const napi_value`.
pub const Val = extern struct {
    handle: c.napi_value,

    pub fn to(self: Val, env: Env, comptime T: type) !T {
        return convert.fromJs(T, env, self);
    }

    inline fn boolFn(self: Val, env: Env, comptime nf: anytype, args: anytype) !bool {
        var out: bool = undefined;
        try check(@call(.auto, nf, .{ env.handle, self.handle } ++ args ++ .{&out}));
        return out;
    }

    inline fn valFn(self: Val, env: Env, comptime nf: anytype, args: anytype) !Val {
        var out: c.napi_value = undefined;
        try check(@call(.auto, nf, .{ env.handle, self.handle } ++ args ++ .{&out}));
        return .{ .handle = out };
    }

    pub fn typeOf(self: Val, env: Env) !c.napi_valuetype {
        var out: c.napi_valuetype = undefined;
        try check(c.napi_typeof(env.handle, self.handle, &out));
        return out;
    }

    pub fn strictEquals(self: Val, env: Env, other: Val) !bool {
        return self.boolFn(env, c.napi_strict_equals, .{other.handle});
    }
    pub fn isArray(self: Val, env: Env) !bool {
        return self.boolFn(env, c.napi_is_array, .{});
    }
    pub fn isArrayBuffer(self: Val, env: Env) !bool {
        return self.boolFn(env, c.napi_is_arraybuffer, .{});
    }
    pub fn isBuffer(self: Val, env: Env) !bool {
        return self.boolFn(env, c.napi_is_buffer, .{});
    }
    pub fn isTypedArray(self: Val, env: Env) !bool {
        return self.boolFn(env, c.napi_is_typedarray, .{});
    }
    pub fn isDate(self: Val, env: Env) !bool {
        return self.boolFn(env, c.napi_is_date, .{});
    }
    pub fn isPromise(self: Val, env: Env) !bool {
        return self.boolFn(env, c.napi_is_promise, .{});
    }
    pub fn hasNamedProperty(self: Val, env: Env, key: [:0]const u8) !bool {
        return self.boolFn(env, c.napi_has_named_property, .{key.ptr});
    }

    pub fn getProperty(self: Val, env: Env, key: Val) !Val {
        return self.valFn(env, c.napi_get_property, .{key.handle});
    }
    pub fn getNamedProperty(self: Val, env: Env, key: [:0]const u8) !Val {
        return self.valFn(env, c.napi_get_named_property, .{key.ptr});
    }
    pub fn getElement(self: Val, env: Env, index: u32) !Val {
        return self.valFn(env, c.napi_get_element, .{index});
    }

    pub fn setProperty(self: Val, env: Env, key: Val, value: Val) !void {
        try check(c.napi_set_property(env.handle, self.handle, key.handle, value.handle));
    }

    pub fn setNamedProperty(self: Val, env: Env, key: [:0]const u8, value: Val) !void {
        try check(c.napi_set_named_property(env.handle, self.handle, key.ptr, value.handle));
    }

    pub fn setElement(self: Val, env: Env, index: u32, value: Val) !void {
        try check(c.napi_set_element(env.handle, self.handle, index, value.handle));
    }

    pub fn getArrayLength(self: Val, env: Env) !u32 {
        var out: u32 = undefined;
        try check(c.napi_get_array_length(env.handle, self.handle, &out));
        return out;
    }

    /// utf-8 byte length of a js string (excluding the null terminator).
    /// does not allocate. errors if the value is not a string.
    pub fn getStringLength(self: Val, env: Env) !usize {
        var out: usize = 0;
        try check(c.napi_get_value_string_utf8(env.handle, self.handle, null, 0, &out));
        return out;
    }

    /// read a bigint as i64. `result.lossless` is false if the source
    /// did not fit. errors only if the value is not a bigint.
    pub fn getBigIntI64(self: Val, env: Env) !BigIntFit(i64) {
        var out: BigIntFit(i64) = .{ .value = 0, .lossless = false };
        try check(c.napi_get_value_bigint_int64(env.handle, self.handle, &out.value, &out.lossless));
        return out;
    }

    /// read a bigint as u64. `result.lossless` is false if the source
    /// was negative or larger than u64::max. errors only if the value
    /// is not a bigint.
    pub fn getBigIntU64(self: Val, env: Env) !BigIntFit(u64) {
        var out: BigIntFit(u64) = .{ .value = 0, .lossless = false };
        try check(c.napi_get_value_bigint_uint64(env.handle, self.handle, &out.value, &out.lossless));
        return out;
    }

    pub fn getArrayBufferData(self: Val, env: Env) ![]u8 {
        return bufferInfo(env, self, c.napi_get_arraybuffer_info);
    }
    pub fn getBufferData(self: Val, env: Env) ![]u8 {
        return bufferInfo(env, self, c.napi_get_buffer_info);
    }

    pub fn getExternalData(self: Val, env: Env) !?*anyopaque {
        var out: ?*anyopaque = null;
        try check(c.napi_get_value_external(env.handle, self.handle, &out));
        return out;
    }

    pub fn getDateValue(self: Val, env: Env) !f64 {
        var out: f64 = undefined;
        try check(c.napi_get_date_value(env.handle, self.handle, &out));
        return out;
    }
};

fn bufferInfo(env: Env, val: Val, comptime nf: anytype) ![]u8 {
    var data: ?*anyopaque = null;
    var len: usize = 0;
    try check(nf(env.handle, val.handle, &data, &len));
    return if (data) |p| @as([*]u8, @ptrCast(p))[0..len] else &.{};
}

/// js function handle, validated as callable.
pub const Callback = struct {
    val: Val,

    /// call with `undefined` as `this`. args is a tuple or `[]const Val`.
    pub fn call(self: Callback, env: Env, args: anytype) !Val {
        return self.callWith(env, try env.createUndefined(), args);
    }

    /// call with a specific `this` binding.
    pub fn callWith(self: Callback, env: Env, this: Val, args: anytype) !Val {
        const T = @TypeOf(args);

        if (T == []const Val or T == []Val) {
            const argv: ?[*]const c.napi_value = if (args.len > 0) @ptrCast(args.ptr) else null;
            return self.invoke(env, this, argv, args.len);
        }

        const info = @typeInfo(T);
        if (info == .@"struct" and info.@"struct".is_tuple) {
            const fields = info.@"struct".fields;
            var argv: [fields.len]c.napi_value = undefined;
            inline for (fields, 0..) |f, i| {
                const v = @field(args, f.name);
                argv[i] = (if (@TypeOf(v) == Val) v else try env.toJs(v)).handle;
            }
            return self.invoke(env, this, if (fields.len > 0) &argv else null, fields.len);
        }

        @compileError("Callback args must be a tuple or []const Val, got " ++ @typeName(T));
    }

    fn invoke(self: Callback, env: Env, this: Val, argv: ?[*]const c.napi_value, argc: usize) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_call_function(env.handle, this.handle, self.val.handle, argc, argv, &out));
        return .{ .handle = out };
    }

    /// wrap as a thread-safe function. use `void` for signal-only callbacks.
    pub fn threadsafe(self: Callback, env: Env, comptime name: [*:0]const u8, comptime T: type) !ThreadsafeFn(T) {
        const name_val = try env.createString(std.mem.span(name));
        var out: c.napi_threadsafe_function = undefined;
        try check(c.napi_create_threadsafe_function(
            env.handle,
            self.val.handle,
            null,
            name_val.handle,
            0,
            1,
            null,
            null,
            null,
            if (T == void) null else &ThreadsafeFn(T).callJs,
            &out,
        ));
        return .{ .handle = out };
    }
};

/// thread-safe wrapper around a js function. T is the per-call payload.
pub fn ThreadsafeFn(comptime T: type) type {
    return struct {
        handle: c.napi_threadsafe_function,

        const Self = @This();
        pub const Mode = c.napi_threadsafe_function_call_mode;

        pub fn call(self: Self, value: T, mode: Mode) !void {
            if (T == void) return check(c.napi_call_threadsafe_function(self.handle, null, mode));

            const ptr = try util.default_allocator.create(T);
            errdefer util.default_allocator.destroy(ptr);
            ptr.* = value;
            try check(c.napi_call_threadsafe_function(self.handle, ptr, mode));
        }

        pub fn release(self: Self) !void {
            return check(c.napi_release_threadsafe_function(self.handle, .release));
        }
        pub fn abort(self: Self) !void {
            return check(c.napi_release_threadsafe_function(self.handle, .abort));
        }
        pub fn acquire(self: Self) !void {
            return check(c.napi_acquire_threadsafe_function(self.handle));
        }
        pub fn unref(self: Self, env: Env) !void {
            return check(c.napi_unref_threadsafe_function(env.handle, self.handle));
        }
        pub fn ref(self: Self, env: Env) !void {
            return check(c.napi_ref_threadsafe_function(env.handle, self.handle));
        }

        fn callJs(raw_env: c.napi_env, js_callback: c.napi_value, _: ?*anyopaque, data: ?*anyopaque) callconv(.c) void {
            const typed: *T = @ptrCast(@alignCast(data orelse return));
            defer util.default_allocator.destroy(typed);

            var arena = std.heap.ArenaAllocator.init(util.default_allocator);
            defer arena.deinit();
            const env: Env = .{ .handle = raw_env, .arena = &arena };

            const js_val = convert.toJs(T, env, typed.*) catch return;
            const undef = env.createUndefined() catch return;
            var out: c.napi_value = undefined;
            _ = c.napi_call_function(raw_env, undef.handle, js_callback, 1, @ptrCast(&js_val.handle), &out);
        }
    };
}

/// strong reference preventing gc of the wrapped js value.
pub const Ref = struct {
    handle: c.napi_ref,

    pub fn delete(self: Ref, env: Env) !void {
        try check(c.napi_delete_reference(env.handle, self.handle));
    }

    pub fn value(self: Ref, env: Env) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_get_reference_value(env.handle, self.handle, &out));
        return .{ .handle = out };
    }
};

/// single-use handle for resolving or rejecting a promise.
pub const Deferred = struct {
    handle: c.napi_deferred,

    pub fn resolve(self: Deferred, env: Env, value: Val) !void {
        try check(c.napi_resolve_deferred(env.handle, self.handle, value.handle));
    }

    pub fn reject(self: Deferred, env: Env, value: Val) !void {
        try check(c.napi_reject_deferred(env.handle, self.handle, value.handle));
    }
};

/// raw call info for variadic or dynamic-arity functions.
pub const CallInfo = struct {
    handle: c.napi_callback_info,

    /// extract up to `max` args. missing slots are filled with `undefined`.
    pub fn args(self: CallInfo, env: Env, comptime max: usize) ![max]Val {
        if (max == 0) return .{};

        var argc: usize = max;
        var argv: [max]c.napi_value = undefined;
        try check(c.napi_get_cb_info(env.handle, self.handle, &argc, &argv, null, null));

        var out: [max]Val = undefined;
        var undef: ?Val = null;
        inline for (0..max) |i| {
            if (i < argc) {
                out[i] = .{ .handle = argv[i] };
            } else {
                if (undef == null) undef = try env.createUndefined();
                out[i] = undef.?;
            }
        }
        return out;
    }

    /// number of args actually passed.
    pub fn argCount(self: CallInfo, env: Env) !usize {
        var n: usize = 0;
        try check(c.napi_get_cb_info(env.handle, self.handle, &n, null, null, null));
        return n;
    }

    /// the `this` binding of the call.
    pub fn this(self: CallInfo, env: Env) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_get_cb_info(env.handle, self.handle, null, null, &out, null));
        return .{ .handle = out };
    }
};
