const std = @import("std");
const napi = @import("napi-zig");

comptime {
    napi.module(@This());
}

pub const version: []const u8 = "wasm-fixture-1";

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}

pub fn greet(env: napi.Env, name: []const u8) ![]const u8 {
    return std.fmt.allocPrint(env.allocator(), "hello, {s}", .{name});
}

pub fn sumSlice(arr: []const i32) i32 {
    var total: i32 = 0;
    for (arr) |x| total += x;
    return total;
}

// synchronous promise: works on every emnapi target
pub fn promiseAdd(env: napi.Env, a: i32, b: i32) !napi.Val {
    const p = try env.createPromise();
    try p.deferred.resolve(env, try env.toJs(a + b));
    return p.promise;
}

// async work via napi_create_async_work. emnapi runs the compute step on a
// pool worker on web targets that support pthreads, or inline on the main
// thread under plain wasm32-wasi.
const FibWork = struct {
    input: i32,
    result: i32 = 0,

    pub fn compute(self: *FibWork) void {
        self.result = fib(self.input);
    }

    pub fn resolve(self: *FibWork, _: napi.Env) !i32 {
        return self.result;
    }

    fn fib(n: i32) i32 {
        if (n <= 1) return n;
        return fib(n - 1) + fib(n - 2);
    }
};

pub fn asyncFib(env: napi.Env, n: i32) !napi.Val {
    return env.runWorker("fib", FibWork{ .input = n });
}

// threadsafe fn called from the same (main) thread. real cross-thread calls
// require std.Thread, which wasm32-wasi without threads does not provide.
pub fn signalOnce(env: napi.Env, cb: napi.Callback) !void {
    const tsfn = try cb.threadsafe(env, "tick", void);
    try tsfn.call({}, .blocking);
    try tsfn.release();
}
