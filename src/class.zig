// js class wrapping. init becomes the constructor, every pub fn taking
// *Self becomes a method, optional deinit runs on gc.

const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const env_mod = @import("env.zig");
const util = @import("util.zig");
const val_mod = @import("val.zig");
const bridge = @import("bridge.zig");
const convert = @import("convert.zig");

const Env = env_mod.Env;
const Val = val_mod.Val;
const check = err.check;

/// wrap a zig struct as a js class. T must declare `pub fn init(...) T`
/// (or `!T`). js_name is the constructor name visible to js.
pub fn class(comptime js_name: [*:0]const u8, comptime T: type) type {
    if (!@hasDecl(T, "init")) {
        @compileError("napi.class: '" ++ @typeName(T) ++ "' must declare `pub fn init(...)`");
    }
    return struct {
        pub const __napi_class_name = js_name;
        pub const __napi_class_inner = T;
    };
}

/// true if `T` is a wrapper produced by `napi.class`.
pub fn isClass(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "__napi_class_name");
}

/// define the js class on `target` under the given field name.
pub fn register(env: Env, target: Val, comptime field_name: []const u8, comptime Wrapper: type) !void {
    const T = Wrapper.__napi_class_inner;
    const methods = comptime collectMethods(T);
    const iterable = comptime isIterator(T);

    var properties: [methods.len + @intFromBool(iterable)]c.napi_property_descriptor = undefined;
    inline for (methods, 0..) |method_name, i| {
        properties[i] = .{
            .utf8name = comptime util.snakeToCamel(method_name).ptr,
            .method = MethodBridge(T, method_name).call,
            .attributes = c.napi_property_attributes.default_method,
        };
    }

    if (iterable) {
        properties[methods.len] = .{
            .name = (try wellKnownSymbolIterator(env)).handle,
            .method = IteratorBridge(T).symbolIterator,
            .attributes = c.napi_property_attributes.default_method,
        };
    }

    var class_val: c.napi_value = undefined;
    try check(c.napi_define_class(
        env.handle,
        Wrapper.__napi_class_name,
        c.NAPI_AUTO_LENGTH,
        ConstructorBridge(T).call,
        null,
        properties.len,
        if (properties.len > 0) &properties else null,
        &class_val,
    ));

    try target.setNamedProperty(env, comptime util.snakeToCamel(field_name), .{ .handle = class_val });
}

pub fn collectMethods(comptime T: type) []const []const u8 {
    comptime {
        var names: []const []const u8 = &.{};
        for (@typeInfo(T).@"struct".decls) |d| {
            if (d.name[0] == '_') continue;
            if (std.mem.eql(u8, d.name, "init") or std.mem.eql(u8, d.name, "deinit")) continue;
            if (!hasSelfReceiver(T, d.name)) continue;
            names = names ++ &[_][]const u8{d.name};
        }
        return names;
    }
}

fn hasSelfReceiver(comptime T: type, comptime name: []const u8) bool {
    const VT = @TypeOf(@field(T, name));
    if (@typeInfo(VT) != .@"fn") return false;
    const params = @typeInfo(VT).@"fn".params;
    if (params.len < 1) return false;
    const first = params[0].type orelse return false;
    return @typeInfo(first) == .pointer and @typeInfo(first).pointer.child == T;
}

/// true if `T` follows zig's iterator convention: `pub fn next(self: *Self) ?Item`
/// (Env may follow self; the return may be an error union). such classes get
/// `[Symbol.iterator]` so instances work with for..of, spread, and Array.from.
pub fn isIterator(comptime T: type) bool {
    if (!@hasDecl(T, "next")) return false;
    if (!hasSelfReceiver(T, "next")) return false;
    const info = @typeInfo(@TypeOf(@field(T, "next"))).@"fn";
    const inject_env = info.params.len > 1 and info.params[1].type.? == Env;
    if (info.params.len != @as(usize, if (inject_env) 2 else 1)) return false;
    const Return = info.return_type orelse return false;
    const Payload = switch (@typeInfo(Return)) {
        .error_union => |eu| eu.payload,
        else => Return,
    };
    return @typeInfo(Payload) == .optional;
}

/// the item type produced by an iterator class (the optional's child).
pub fn IteratorItem(comptime T: type) type {
    const Return = @typeInfo(@TypeOf(@field(T, "next"))).@"fn".return_type.?;
    const Payload = switch (@typeInfo(Return)) {
        .error_union => |eu| eu.payload,
        else => Return,
    };
    return @typeInfo(Payload).optional.child;
}

fn wellKnownSymbolIterator(env: Env) !Val {
    const global = try env.getGlobal();
    const symbol = try global.getNamedProperty(env, "Symbol");
    return symbol.getNamedProperty(env, "iterator");
}

fn ConstructorBridge(comptime T: type) type {
    const Init = @TypeOf(@field(T, "init"));
    const params = @typeInfo(Init).@"fn".params;
    const inject_env = params.len > 0 and params[0].type.? == Env;
    const js_start: usize = if (inject_env) 1 else 0;
    const Return = @typeInfo(Init).@"fn".return_type.?;
    const Payload = switch (@typeInfo(Return)) {
        .error_union => |eu| eu.payload,
        else => Return,
    };

    if (Payload != T) {
        @compileError("napi.class: '" ++ @typeName(T) ++ ".init' must return " ++ @typeName(T) ++ " or !" ++ @typeName(T));
    }

    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
            defer arena.deinit();
            const env: Env = .{ .handle = raw_env, .arena = &arena };

            var this_val: c.napi_value = undefined;
            var args: std.meta.ArgsTuple(Init) = undefined;
            if (inject_env) args[0] = env;
            if (!bridge.invoke(js_start, env, raw_info, &args, &this_val, "constructor")) return null;

            const raw = @call(.auto, @field(T, "init"), args);
            const value = if (@typeInfo(Return) == .error_union) (raw catch |e| {
                if (!env.isExceptionPending()) env.throwError(@errorName(e));
                return null;
            }) else raw;

            const instance = std.heap.smp_allocator.create(T) catch {
                env.throwError("napi-zig: out of memory");
                return null;
            };
            instance.* = value;

            if (c.napi_wrap(env.handle, this_val, instance, &finalize, null, null) != .ok) {
                std.heap.smp_allocator.destroy(instance);
                env.throwError("napi-zig: napi_wrap failed");
                return null;
            }
            return this_val;
        }

        fn finalize(_: c.napi_env, data: ?*anyopaque, _: ?*anyopaque) callconv(.c) void {
            const instance: *T = @ptrCast(@alignCast(data orelse return));
            if (@hasDecl(T, "deinit")) instance.deinit();
            std.heap.smp_allocator.destroy(instance);
        }
    };
}

fn MethodBridge(comptime T: type, comptime method_name: []const u8) type {
    const Method = @TypeOf(@field(T, method_name));
    const params = @typeInfo(Method).@"fn".params;
    // params[0] is *Self, params[1] may be Env.
    const inject_env = params.len > 1 and params[1].type.? == Env;
    const js_start: usize = if (inject_env) 2 else 1;

    return struct {
        fn call(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
            defer arena.deinit();
            const env: Env = .{ .handle = raw_env, .arena = &arena };

            var this_val: c.napi_value = undefined;
            var args: std.meta.ArgsTuple(Method) = undefined;
            if (inject_env) args[1] = env;
            if (!bridge.invoke(js_start, env, raw_info, &args, &this_val, "method '" ++ method_name ++ "'")) return null;

            var unwrapped: ?*anyopaque = null;
            if (c.napi_unwrap(env.handle, this_val, &unwrapped) != .ok) {
                env.throwError("napi-zig: napi_unwrap failed");
                return null;
            }
            args[0] = @ptrCast(@alignCast(unwrapped));

            return bridge.returnResult(env, @call(.auto, @field(T, method_name), args));
        }
    };
}

// js iterator protocol over a zig-style `next(self) ?Item`. `[Symbol.iterator]`
// returns a fresh `{ next() }` object that holds the instance through a
// property, so the wrapped object can't be gc'd while iteration is live. the
// iterator is itself iterable (its own [Symbol.iterator] returns this), which
// is what js generators do. note iteration state lives in the zig instance:
// two loops over the same instance continue where the previous one stopped.
fn IteratorBridge(comptime T: type) type {
    const Next = @TypeOf(@field(T, "next"));
    const params = @typeInfo(Next).@"fn".params;
    const inject_env = params.len > 1 and params[1].type.? == Env;

    return struct {
        fn symbolIterator(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
            defer arena.deinit();
            const env: Env = .{ .handle = raw_env, .arena = &arena };
            return make(env, raw_info) catch {
                if (!env.isExceptionPending()) env.throwError("napi-zig: [Symbol.iterator] failed");
                return null;
            };
        }

        fn make(env: Env, raw_info: c.napi_callback_info) !c.napi_value {
            var this_val: c.napi_value = undefined;
            try check(c.napi_get_cb_info(env.handle, raw_info, null, null, &this_val, null));

            const iter = try env.createObject();
            try iter.setNamedProperty(env, "__napi_target", .{ .handle = this_val });
            try iter.setNamedProperty(env, "next", try env.createFunction("next", step, null));
            try iter.setProperty(env, try wellKnownSymbolIterator(env), try env.createFunction(null, selfIterator, null));
            return iter.handle;
        }

        fn selfIterator(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            var this_val: c.napi_value = undefined;
            if (c.napi_get_cb_info(raw_env, raw_info, null, null, &this_val, null) != .ok) return null;
            return this_val;
        }

        fn step(raw_env: c.napi_env, raw_info: c.napi_callback_info) callconv(.c) ?c.napi_value {
            var arena = std.heap.ArenaAllocator.init(std.heap.smp_allocator);
            defer arena.deinit();
            const env: Env = .{ .handle = raw_env, .arena = &arena };

            var this_val: c.napi_value = undefined;
            if (c.napi_get_cb_info(env.handle, raw_info, null, null, &this_val, null) != .ok) {
                env.throwError("napi-zig: cb_info failed in iterator next");
                return null;
            }

            const iter: Val = .{ .handle = this_val };
            const target = iter.getNamedProperty(env, "__napi_target") catch {
                env.throwError("napi-zig: iterator detached from its instance");
                return null;
            };

            var unwrapped: ?*anyopaque = null;
            if (c.napi_unwrap(env.handle, target.handle, &unwrapped) != .ok) {
                env.throwError("napi-zig: napi_unwrap failed in iterator next");
                return null;
            }

            var args: std.meta.ArgsTuple(Next) = undefined;
            args[0] = @ptrCast(@alignCast(unwrapped));
            if (inject_env) args[1] = env;

            const raw = @call(.auto, @field(T, "next"), args);
            const maybe = if (@typeInfo(@TypeOf(raw)) == .error_union) (raw catch |e| {
                if (!env.isExceptionPending()) env.throwError(@errorName(e));
                return null;
            }) else raw;

            const result = env.createObject() catch return null;
            const done = env.createBoolean(maybe == null) catch return null;
            result.setNamedProperty(env, "done", done) catch return null;
            if (maybe) |item| {
                const value = convert.toJs(@TypeOf(item), env, item) catch return null;
                result.setNamedProperty(env, "value", value) catch return null;
            }
            return result.handle;
        }
    };
}

const testing = std.testing;

test "isClass detects class wrappers" {
    const Counter = class("Counter", struct {
        value: i32,
        pub fn init(v: i32) @This() {
            return .{ .value = v };
        }
        pub fn get(self: *@This()) i32 {
            return self.value;
        }
    });
    try testing.expect(comptime isClass(Counter));
    try testing.expect(comptime !isClass(struct {}));
    try testing.expect(comptime !isClass(i32));
}

test "collectMethods gathers self-receiving fns and skips init/deinit" {
    const T = struct {
        v: i32,
        pub fn init() @This() {
            return .{ .v = 0 };
        }
        pub fn deinit(_: *@This()) void {}
        pub fn a(_: *@This()) i32 {
            return 0;
        }
        pub fn b(_: *const @This()) i32 {
            return 0;
        }
        pub fn c(_: i32) void {} // no self, skipped
        pub fn _hidden(_: *@This()) void {}
    };
    const ms = comptime collectMethods(T);
    try testing.expectEqual(@as(usize, 2), ms.len);
    try testing.expectEqualStrings("a", ms[0]);
    try testing.expectEqualStrings("b", ms[1]);
}

test "isIterator detects zig-style next" {
    const Range = struct {
        i: u32,
        end: u32,
        pub fn init(end: u32) @This() {
            return .{ .i = 0, .end = end };
        }
        pub fn next(self: *@This()) ?u32 {
            if (self.i >= self.end) return null;
            defer self.i += 1;
            return self.i;
        }
    };
    try testing.expect(comptime isIterator(Range));
    try testing.expectEqual(u32, comptime IteratorItem(Range));
}

test "isIterator accepts Env injection and error unions" {
    const WithEnv = struct {
        pub fn init() @This() {
            return .{};
        }
        pub fn next(_: *@This(), _: Env) !?[]const u8 {
            return null;
        }
    };
    try testing.expect(comptime isIterator(WithEnv));
    try testing.expectEqual([]const u8, comptime IteratorItem(WithEnv));
}

test "isIterator rejects non-conforming next" {
    const NonOptional = struct {
        pub fn init() @This() {
            return .{};
        }
        pub fn next(_: *@This()) u32 {
            return 0;
        }
    };
    const TakesArgs = struct {
        pub fn init() @This() {
            return .{};
        }
        pub fn next(_: *@This(), _: u32) ?u32 {
            return null;
        }
    };
    const NoNext = struct {
        pub fn init() @This() {
            return .{};
        }
    };
    try testing.expect(comptime !isIterator(NonOptional));
    try testing.expect(comptime !isIterator(TakesArgs));
    try testing.expect(comptime !isIterator(NoNext));
}

test "class wrapper exposes inner type" {
    const Inner = struct {
        v: i32,
        pub fn init() @This() {
            return .{ .v = 0 };
        }
    };
    const Wrapped = class("Inner", Inner);
    try testing.expectEqual(Inner, Wrapped.__napi_class_inner);
}
