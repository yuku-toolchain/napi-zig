const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const convert = @import("convert.zig");
const val_mod = @import("val.zig");
const Val = val_mod.Val;
const Ref = val_mod.Ref;
const Deferred = val_mod.Deferred;

const check = err.check;

// the call arena is per thread and reused across native calls: it is
// reset (retaining up to `arena_retain_limit` of capacity) when the
// outermost call on the thread returns, so repeated calls stop paying
// the backing allocator for every string or slice conversion. nested
// native calls (js re-entered during a call) share the arena and only
// the outermost `CallScope.deinit` resets it. an env cleanup hook
// frees the retained memory when the environment shuts down (worker
// threads would otherwise leak their retained capacity on exit).
const arena_retain_limit = 1 << 20;

threadlocal var call_arena: std.heap.ArenaAllocator = undefined;
threadlocal var call_arena_ready: bool = false;
threadlocal var call_depth: u32 = 0;

fn freeCallArena(_: ?*anyopaque) callconv(.c) void {
    if (!call_arena_ready) return;
    call_arena.deinit();
    call_arena_ready = false;
}

/// one native call: `const scope = callScope(raw_env); defer scope.deinit();`.
/// `scope.env` carries the thread's reused arena.
pub const CallScope = struct {
    env: Env,

    pub fn deinit(_: CallScope) void {
        call_depth -= 1;
        if (call_depth == 0) {
            _ = call_arena.reset(.{ .retain_with_limit = arena_retain_limit });
        }
    }
};

pub fn callScope(raw_env: c.napi_env) CallScope {
    if (!call_arena_ready) {
        call_arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
        call_arena_ready = true;
        // arg distinguishes registrations per thread; the hook itself
        // only touches threadlocals of the env's own thread.
        _ = c.napi_add_env_cleanup_hook(raw_env, &freeCallArena, @ptrCast(&call_arena));
    }
    call_depth += 1;
    return .{ .env = .{ .handle = raw_env, .arena = &call_arena } };
}

/// node-api environment handle. carries a per-call arena allocator.
pub const Env = struct {
    handle: c.napi_env,
    arena: *std.heap.ArenaAllocator,

    pub fn allocator(self: Env) std.mem.Allocator {
        return self.arena.allocator();
    }

    pub fn toJs(self: Env, value: anytype) !Val {
        return convert.toJs(@TypeOf(value), self, value);
    }

    /// uniform shape for napi_create_*/napi_get_* calls that produce a Val.
    inline fn make(self: Env, comptime nf: anytype, args: anytype) !Val {
        var out: c.napi_value = undefined;
        try check(@call(.auto, nf, .{self.handle} ++ args ++ .{&out}));
        return .{ .handle = out };
    }

    pub fn createBoolean(self: Env, v: bool) !Val {
        return self.make(c.napi_get_boolean, .{v});
    }
    pub fn createInt32(self: Env, v: i32) !Val {
        return self.make(c.napi_create_int32, .{v});
    }
    pub fn createUint32(self: Env, v: u32) !Val {
        return self.make(c.napi_create_uint32, .{v});
    }
    pub fn createInt64(self: Env, v: i64) !Val {
        return self.make(c.napi_create_int64, .{v});
    }
    pub fn createFloat64(self: Env, v: f64) !Val {
        return self.make(c.napi_create_double, .{v});
    }
    pub fn createBigintInt64(self: Env, v: i64) !Val {
        return self.make(c.napi_create_bigint_int64, .{v});
    }
    pub fn createBigintUint64(self: Env, v: u64) !Val {
        return self.make(c.napi_create_bigint_uint64, .{v});
    }
    pub fn createString(self: Env, s: []const u8) !Val {
        return self.make(c.napi_create_string_utf8, .{ s.ptr, s.len });
    }
    pub fn createNull(self: Env) !Val {
        return self.make(c.napi_get_null, .{});
    }
    pub fn createUndefined(self: Env) !Val {
        return self.make(c.napi_get_undefined, .{});
    }
    pub fn createObject(self: Env) !Val {
        return self.make(c.napi_create_object, .{});
    }
    pub fn createArray(self: Env) !Val {
        return self.make(c.napi_create_array, .{});
    }
    pub fn createArrayWithLength(self: Env, len: u32) !Val {
        return self.make(c.napi_create_array_with_length, .{len});
    }
    pub fn createDate(self: Env, time_ms: f64) !Val {
        return self.make(c.napi_create_date, .{time_ms});
    }
    pub fn getGlobal(self: Env) !Val {
        return self.make(c.napi_get_global, .{});
    }

    pub fn createSymbol(self: Env, description: ?Val) !Val {
        return self.make(c.napi_create_symbol, .{if (description) |d| d.handle else null});
    }

    pub fn createExternal(self: Env, ptr: ?*anyopaque, finalize: ?c.napi_finalize, hint: ?*anyopaque) !Val {
        return self.make(c.napi_create_external, .{ ptr, finalize, hint });
    }

    pub fn createExternalArrayBuffer(self: Env, data: [*]u8, len: usize, finalize: ?c.napi_finalize, hint: ?*anyopaque) !Val {
        return self.make(c.napi_create_external_arraybuffer, .{ data, len, finalize, hint });
    }

    pub fn createTypedArray(self: Env, typ: c.napi_typedarray_type, len: usize, ab: Val, offset: usize) !Val {
        return self.make(c.napi_create_typedarray, .{ typ, len, ab.handle, offset });
    }

    pub fn createFunction(self: Env, name: ?[*:0]const u8, cb: c.napi_callback, data: ?*anyopaque) !Val {
        return self.make(c.napi_create_function, .{ name, c.NAPI_AUTO_LENGTH, cb, data });
    }

    pub const ArrayBuffer = struct { val: Val, data: []u8 };

    pub fn createArrayBuffer(self: Env, len: usize) !ArrayBuffer {
        return makeBuffer(self, c.napi_create_arraybuffer, len);
    }

    pub fn createBuffer(self: Env, len: usize) !ArrayBuffer {
        return makeBuffer(self, c.napi_create_buffer, len);
    }

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

    /// build a js error value without throwing. used to reject promises
    /// from contexts where throw doesn't propagate (workers, threadsafe).
    pub fn createError(self: Env, message: []const u8) !Val {
        const msg = try self.createString(message);
        return self.make(c.napi_create_error, .{ null, msg.handle });
    }

    pub fn isExceptionPending(self: Env) bool {
        var result: bool = false;
        _ = c.napi_is_exception_pending(self.handle, &result);
        return result;
    }

    pub fn createReference(self: Env, value: Val) !Ref {
        var out: c.napi_ref = undefined;
        try check(c.napi_create_reference(self.handle, value.handle, 1, &out));
        return .{ .handle = out };
    }

    pub const Promise = struct { promise: Val, deferred: Deferred };

    pub fn createPromise(self: Env) !Promise {
        var d: c.napi_deferred = undefined;
        var p: c.napi_value = undefined;
        try check(c.napi_create_promise(self.handle, &d, &p));
        return .{ .promise = .{ .handle = p }, .deferred = .{ .handle = d } };
    }

    /// run a worker on a background thread, return a js promise.
    /// context must declare `compute(*Self) void` (worker thread) and
    /// `resolve(*Self, Env) !T` (main thread, value becomes promise).
    pub fn runWorker(self: Env, comptime name: [*:0]const u8, context: anytype) !Val {
        const State = WorkerState(@TypeOf(context));

        const p = try self.createPromise();
        errdefer rejectWith(self, p.deferred, "napi-zig: failed to start worker");

        const state = try std.heap.smp_allocator.create(State);
        errdefer std.heap.smp_allocator.destroy(state);
        state.* = .{ .ctx = context, .deferred = p.deferred };

        const name_val = try self.createString(std.mem.span(name));
        try check(c.napi_create_async_work(self.handle, null, name_val.handle, &State.execute, &State.complete, state, &state.work));
        errdefer _ = c.napi_delete_async_work(self.handle, state.work);
        try check(c.napi_queue_async_work(self.handle, state.work));

        return p.promise;
    }

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

var empty_buffer: [0]u8 = .{};

fn makeBuffer(self: Env, comptime nf: anytype, len: usize) !Env.ArrayBuffer {
    var data: ?*anyopaque = null;
    var out: c.napi_value = undefined;
    try check(nf(self.handle, len, &data, &out));
    const ptr: [*]u8 = if (data) |p| @ptrCast(p) else &empty_buffer;
    return .{ .val = .{ .handle = out }, .data = ptr[0..len] };
}

fn WorkerState(comptime T: type) type {
    const Resolve = @TypeOf(@field(T, "resolve"));
    const ResolveReturn = @typeInfo(Resolve).@"fn".return_type.?;
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

            const scope = callScope(raw_env);
            defer scope.deinit();
            const env = scope.env;

            _ = c.napi_delete_async_work(raw_env, state.work);

            const raw = state.ctx.resolve(env);
            const value = if (is_error_union) (raw catch |e| {
                rejectWith(env, state.deferred, @errorName(e));
                return;
            }) else raw;

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

fn rejectWith(env: Env, deferred: Deferred, message: []const u8) void {
    const reason = env.createError(message) catch return;
    deferred.reject(env, reason) catch {};
}
