const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const convert = @import("convert.zig");
const val_mod = @import("val.zig");
const Val = val_mod.Val;
const Ref = val_mod.Ref;
const Deferred = val_mod.Deferred;

const check = err.check;

// Per-thread arena, reused across calls. Reset (not freed) between
// invocations so steady-state allocation cost is zero. The first call
// on a thread initializes the arena; subsequent calls just rewind it.
//
// If a single call drove the arena above the retain limit, the arena
// is fully freed and re-created — bounds long-tail growth without
// punishing the common case.
const RETAIN_LIMIT: usize = 1 << 20;

threadlocal var tls_arena: ?std.heap.ArenaAllocator = null;

pub fn borrowArena() *std.heap.ArenaAllocator {
    if (tls_arena == null) {
        tls_arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    }
    return &tls_arena.?;
}

pub fn releaseArena(a: *std.heap.ArenaAllocator) void {
    if (a.queryCapacity() > RETAIN_LIMIT) {
        a.deinit();
        a.* = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
    } else {
        _ = a.reset(.retain_capacity);
    }
}

/// The Node-API environment handle.
///
/// Carries a per-call allocator. The allocator is backed by a
/// thread-local arena that is reset (not freed) between invocations,
/// so calls that don't allocate pay nothing.
pub const Env = struct {
    handle: c.napi_env,
    arena: *std.heap.ArenaAllocator,

    /// The per-call allocator. Memory is freed automatically when
    /// the function returns.
    pub fn allocator(self: Env) std.mem.Allocator {
        return self.arena.allocator();
    }

    // ── Conversion entry point ─────────────────────────────────────────

    /// Convert any Zig value to a JS value. The Zig type is inferred.
    pub fn toJs(self: Env, value: anytype) !Val {
        return convert.toJs(@TypeOf(value), self, value);
    }

    // ── Primitives ────────────────────────────────────────────────────

    pub fn createBoolean(self: Env, value: bool) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_get_boolean(self.handle, value, &out));
        return .{ .handle = out };
    }

    pub fn createInt32(self: Env, value: i32) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_int32(self.handle, value, &out));
        return .{ .handle = out };
    }

    pub fn createUint32(self: Env, value: u32) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_uint32(self.handle, value, &out));
        return .{ .handle = out };
    }

    pub fn createInt64(self: Env, value: i64) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_int64(self.handle, value, &out));
        return .{ .handle = out };
    }

    pub fn createFloat64(self: Env, value: f64) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_double(self.handle, value, &out));
        return .{ .handle = out };
    }

    pub fn createBigintInt64(self: Env, value: i64) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_bigint_int64(self.handle, value, &out));
        return .{ .handle = out };
    }

    pub fn createBigintUint64(self: Env, value: u64) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_bigint_uint64(self.handle, value, &out));
        return .{ .handle = out };
    }

    // ── Strings ───────────────────────────────────────────────────────

    pub fn createString(self: Env, str: []const u8) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.handle, str.ptr, str.len, &out));
        return .{ .handle = out };
    }

    pub fn createStringZ(self: Env, str: [*:0]const u8) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.handle, str, c.NAPI_AUTO_LENGTH, &out));
        return .{ .handle = out };
    }

    // ── Singletons ────────────────────────────────────────────────────

    pub fn createNull(self: Env) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_get_null(self.handle, &out));
        return .{ .handle = out };
    }

    pub fn createUndefined(self: Env) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_get_undefined(self.handle, &out));
        return .{ .handle = out };
    }

    pub fn getGlobal(self: Env) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_get_global(self.handle, &out));
        return .{ .handle = out };
    }

    // ── Containers ────────────────────────────────────────────────────

    pub fn createObject(self: Env) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_object(self.handle, &out));
        return .{ .handle = out };
    }

    pub fn createArray(self: Env) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_array(self.handle, &out));
        return .{ .handle = out };
    }

    pub fn createArrayWithLength(self: Env, len: u32) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_array_with_length(self.handle, len, &out));
        return .{ .handle = out };
    }

    // ── Symbols / Dates / Externals ───────────────────────────────────

    pub fn createSymbol(self: Env, description: ?Val) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_symbol(self.handle, if (description) |d| d.handle else null, &out));
        return .{ .handle = out };
    }

    pub fn createDate(self: Env, time_ms: f64) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_date(self.handle, time_ms, &out));
        return .{ .handle = out };
    }

    /// Wraps an opaque Zig pointer in a JS `external` value, with an
    /// optional finalizer invoked when the value is GC'd.
    pub fn createExternal(self: Env, ptr: ?*anyopaque, finalize: ?c.napi_finalize, hint: ?*anyopaque) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_external(self.handle, ptr, finalize, hint, &out));
        return .{ .handle = out };
    }

    // ── Functions ─────────────────────────────────────────────────────

    pub fn createFunction(self: Env, name: ?[*:0]const u8, cb: c.napi_callback) !Val {
        return self.createFunctionWithData(name, cb, null);
    }

    pub fn createFunctionWithData(self: Env, name: ?[*:0]const u8, cb: c.napi_callback, data: ?*anyopaque) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_function(self.handle, name, if (name) |_| c.NAPI_AUTO_LENGTH else 0, cb, data, &out));
        return .{ .handle = out };
    }

    // ── Buffers ───────────────────────────────────────────────────────

    pub const ArrayBuffer = struct { val: Val, data: []u8 };

    pub fn createArrayBuffer(self: Env, len: usize) !ArrayBuffer {
        var data: ?*anyopaque = null;
        var out: c.napi_value = undefined;
        try check(c.napi_create_arraybuffer(self.handle, len, &data, &out));
        return .{
            .val = .{ .handle = out },
            .data = if (data) |p| @as([*]u8, @ptrCast(p))[0..len] else &.{},
        };
    }

    pub fn createExternalArrayBuffer(self: Env, data: [*]u8, len: usize, finalize: ?c.napi_finalize, hint: ?*anyopaque) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_external_arraybuffer(self.handle, data, len, finalize, hint, &out));
        return .{ .handle = out };
    }

    pub fn createBuffer(self: Env, len: usize) !ArrayBuffer {
        var data: ?*anyopaque = null;
        var out: c.napi_value = undefined;
        try check(c.napi_create_buffer(self.handle, len, &data, &out));
        return .{
            .val = .{ .handle = out },
            .data = if (data) |p| @as([*]u8, @ptrCast(p))[0..len] else &.{},
        };
    }

    pub fn createTypedArray(self: Env, typ: c.napi_typedarray_type, len: usize, ab: Val, offset: usize) !Val {
        var out: c.napi_value = undefined;
        try check(c.napi_create_typedarray(self.handle, typ, len, ab.handle, offset, &out));
        return .{ .handle = out };
    }

    // ── Exceptions ────────────────────────────────────────────────────

    pub fn throwValue(self: Env, value: Val) !void {
        try check(c.napi_throw(self.handle, value.handle));
    }

    pub fn throwError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_error(self.handle, null, msg);
    }

    pub fn throwTypeError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_type_error(self.handle, null, msg);
    }

    pub fn throwRangeError(self: Env, msg: [*:0]const u8) void {
        _ = c.napi_throw_range_error(self.handle, null, msg);
    }

    pub fn isExceptionPending(self: Env) bool {
        var result: bool = false;
        _ = c.napi_is_exception_pending(self.handle, &result);
        return result;
    }

    // ── References / Promises ─────────────────────────────────────────

    pub fn createReference(self: Env, value: Val) !Ref {
        var out: c.napi_ref = undefined;
        try check(c.napi_create_reference(self.handle, value.handle, 1, &out));
        return .{ .handle = out };
    }

    pub const Promise = struct {
        promise: Val,
        deferred: Deferred,
    };

    pub fn createPromise(self: Env) !Promise {
        var d: c.napi_deferred = undefined;
        var p: c.napi_value = undefined;
        try check(c.napi_create_promise(self.handle, &d, &p));
        return .{ .promise = .{ .handle = p }, .deferred = .{ .handle = d } };
    }

    // ── Workers ───────────────────────────────────────────────────────

    /// Run a worker on a background thread, returning a JS Promise.
    ///
    /// `Context` must be a struct with two methods:
    ///   - `pub fn compute(self: *@This()) void` runs on a worker thread.
    ///   - `pub fn resolve(self: *@This(), env: Env) !T` runs on the main
    ///     thread; its return value (or error) becomes the promise result.
    ///     `T` may be any convertible Zig type, `napi.Val`, or `void`.
    pub fn runWorker(self: Env, comptime name: [*:0]const u8, context: anytype) !Val {
        const T = @TypeOf(context);
        const State = WorkerState(T);

        const p = try self.createPromise();
        errdefer p.deferred.reject(self, self.createUndefined() catch unreachable) catch {};

        const state = try std.heap.smp_allocator.create(State);
        errdefer std.heap.smp_allocator.destroy(state);

        state.* = .{ .ctx = context, .deferred = p.deferred };

        var name_val: c.napi_value = undefined;
        try check(c.napi_create_string_utf8(self.handle, name, c.NAPI_AUTO_LENGTH, &name_val));

        var work: c.napi_async_work = undefined;
        try check(c.napi_create_async_work(self.handle, null, name_val, &State.execute, &State.complete, state, &work));
        errdefer _ = c.napi_delete_async_work(self.handle, work);

        state.work = work;
        try check(c.napi_queue_async_work(self.handle, work));

        return p.promise;
    }

    // ── Runtime info ──────────────────────────────────────────────────

    pub fn getVersion(self: Env) !u32 {
        var out: u32 = undefined;
        try check(c.napi_get_version(self.handle, &out));
        return out;
    }

    pub fn getNodeVersion(self: Env) !*const c.napi_node_version {
        var out: *const c.napi_node_version = undefined;
        try check(c.napi_get_node_version(self.handle, &out));
        return out;
    }
};

fn WorkerState(comptime T: type) type {
    const resolve_fn = @typeInfo(@TypeOf(@field(T, "resolve"))).@"fn";
    const ResolveReturn = resolve_fn.return_type.?;
    const is_error_union = @typeInfo(ResolveReturn) == .error_union;
    const Payload = if (is_error_union) @typeInfo(ResolveReturn).error_union.payload else ResolveReturn;

    return struct {
        ctx: T,
        deferred: Deferred,
        work: c.napi_async_work = undefined,

        const Self = @This();

        fn execute(_: c.napi_env, data: ?*anyopaque) callconv(.c) void {
            const state: *Self = @ptrCast(@alignCast(data));
            state.ctx.compute();
        }

        fn complete(raw_env: c.napi_env, _: c.napi_status, data: ?*anyopaque) callconv(.c) void {
            const state: *Self = @ptrCast(@alignCast(data));
            defer std.heap.smp_allocator.destroy(state);

            const arena = borrowArena();
            defer releaseArena(arena);
            const env: Env = .{ .handle = raw_env, .arena = arena };

            _ = c.napi_delete_async_work(raw_env, state.work);

            const raw = state.ctx.resolve(env);

            const value = if (is_error_union) raw catch |e| {
                env.throwError(@errorName(e));
                const undef = env.createUndefined() catch return;
                state.deferred.reject(env, undef) catch {};
                return;
            } else raw;

            const js_val = if (Payload == Val)
                value
            else if (Payload == void)
                env.createUndefined() catch return
            else
                convert.toJs(Payload, env, value) catch return;

            state.deferred.resolve(env, js_val) catch {};
        }
    };
}
