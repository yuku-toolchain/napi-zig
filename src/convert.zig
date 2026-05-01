const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const util = @import("util.zig");
const Env = @import("env.zig").Env;
const val_mod = @import("val.zig");
const Val = val_mod.Val;
const Callback = val_mod.Callback;

const check = err.check;

/// zig to js. structs may opt out of field-by-field with a `toJs` method.
pub fn toJs(comptime T: type, env: Env, value: T) !Val {
    return switch (@typeInfo(T)) {
        .void => env.createUndefined(),
        .bool => env.createBoolean(value),
        .comptime_int => env.createFloat64(@floatFromInt(value)),
        .comptime_float => env.createFloat64(value),

        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                0...32 => env.createInt32(@intCast(value)),
                33...53 => env.createFloat64(@floatFromInt(value)),
                54...64 => env.createBigintInt64(@intCast(value)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
            .unsigned => switch (info.bits) {
                0...32 => env.createUint32(@intCast(value)),
                33...53 => env.createFloat64(@floatFromInt(value)),
                54...64 => env.createBigintUint64(@intCast(value)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
        },

        .float => |info| switch (info.bits) {
            16, 32, 64 => env.createFloat64(@floatCast(value)),
            else => @compileError("napi-zig: unsupported float width: " ++ @typeName(T)),
        },

        .optional => |opt| if (value) |v| toJs(opt.child, env, v) else env.createNull(),

        .@"enum" => env.createString(@tagName(value)),

        .pointer => |info| {
            if (info.size == .slice and info.child == u8) return env.createString(value);
            if (info.size == .slice) return arrayFromSlice(info.child, env, value);
            if (info.size == .one) {
                const child = @typeInfo(info.child);
                if (child == .array and child.array.child == u8) {
                    const slice: []const u8 = value;
                    return env.createString(slice);
                }
            }
            @compileError("napi-zig: unsupported pointer type for toJs: " ++ @typeName(T));
        },

        .array => |info| arrayFromSlice(info.child, env, &value),

        .@"struct" => |info| {
            if (T == Val) return value;
            if (@hasDecl(T, "toJs")) return value.toJs(env);
            if (info.is_tuple) {
                const arr = try env.createArrayWithLength(@intCast(info.fields.len));
                inline for (info.fields, 0..) |field, i| {
                    try arr.setElement(env, @intCast(i), try toJs(field.type, env, @field(value, field.name)));
                }
                return arr;
            }
            const obj = try env.createObject();
            inline for (info.fields) |field| {
                try obj.setNamedProperty(env, comptime util.snakeToCamel(field.name), try toJs(field.type, env, @field(value, field.name)));
            }
            return obj;
        },

        .@"union" => {
            if (@hasDecl(T, "toJs")) return value.toJs(env);
            @compileError("napi-zig: union requires a `pub fn toJs(self, env) !Val` method: " ++ @typeName(T));
        },

        else => @compileError("napi-zig: unsupported type for toJs: " ++ @typeName(T)),
    };
}

fn arrayFromSlice(comptime Child: type, env: Env, items: []const Child) !Val {
    const arr = try env.createArrayWithLength(@intCast(items.len));
    for (items, 0..) |item, i| {
        try arr.setElement(env, @intCast(i), try toJs(Child, env, item));
    }
    return arr;
}

/// js to zig. mirror of toJs. allocations come from env.allocator().
pub fn fromJs(comptime T: type, env: Env, value: Val) !T {
    return switch (@typeInfo(T)) {
        .bool => extract(bool, env, value, c.napi_get_value_bool, "expected boolean"),

        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                0...32 => @intCast(try extract(i32, env, value, c.napi_get_value_int32, "expected number")),
                33...64 => @intCast(try extract(i64, env, value, c.napi_get_value_int64, "expected number")),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
            .unsigned => switch (info.bits) {
                0...32 => @intCast(try extract(u32, env, value, c.napi_get_value_uint32, "expected number")),
                33...64 => blk: {
                    var out: u64 = undefined;
                    var lossless: bool = undefined;
                    try expect(env, value, c.napi_get_value_bigint_uint64(env.handle, value.handle, &out, &lossless), "expected bigint");
                    break :blk @intCast(out);
                },
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
        },

        .float => @floatCast(try extract(f64, env, value, c.napi_get_value_double, "expected number")),

        .optional => |opt| switch (try value.typeOf(env)) {
            .null, .undefined => null,
            else => try fromJs(opt.child, env, value),
        },

        .@"enum" => |info| {
            var stack: [128]u8 = undefined;
            var n: usize = 0;
            try expect(env, value, c.napi_get_value_string_utf8(env.handle, value.handle, &stack, stack.len, &n), "expected string");
            const str = stack[0..n];
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, str, comptime util.snakeToCamel(field.name)) or std.mem.eql(u8, str, field.name)) {
                    return @enumFromInt(field.value);
                }
            }
            var ebuf: [192]u8 = undefined;
            const msg = std.fmt.bufPrintZ(&ebuf, "invalid enum value for " ++ @typeName(T) ++ ": '{s}'", .{str}) catch "invalid enum value";
            env.throwTypeError(msg);
            return err.Error.InvalidArg;
        },

        .pointer => |info| {
            if (info.size == .slice and info.child == u8) return readString(env, value);
            if (info.size == .slice) {
                var len: u32 = undefined;
                try expect(env, value, c.napi_get_array_length(env.handle, value.handle, &len), "expected array");
                const slice = try env.allocator().alloc(info.child, len);
                for (slice, 0..) |*item, i| {
                    item.* = try fromJs(info.child, env, try value.getElement(env, @intCast(i)));
                }
                return slice;
            }
            @compileError("napi-zig: unsupported pointer type for fromJs: " ++ @typeName(T));
        },

        .array => |info| {
            var out: T = undefined;
            for (0..info.len) |i| {
                out[i] = try fromJs(info.child, env, try value.getElement(env, @intCast(i)));
            }
            return out;
        },

        .@"struct" => |info| {
            if (T == Val) return value;
            if (T == Callback) return readCallback(env, value);
            if (@hasDecl(T, "fromJs")) return T.fromJs(env, value);
            if (info.is_tuple) {
                var out: T = undefined;
                inline for (info.fields, 0..) |field, i| {
                    @field(out, field.name) = try fromJs(field.type, env, try value.getElement(env, @intCast(i)));
                }
                return out;
            }

            // undefined means "missing"; default-valued fields can be omitted.
            var out: T = undefined;
            inline for (info.fields) |field| {
                const key = comptime util.snakeToCamel(field.name);
                const prop = try value.getNamedProperty(env, key);
                if (try prop.typeOf(env) == .undefined) {
                    if (field.defaultValue()) |dflt| {
                        @field(out, field.name) = dflt;
                    } else {
                        env.throwTypeError("missing required field: " ++ key);
                        return err.Error.InvalidArg;
                    }
                } else {
                    @field(out, field.name) = try fromJs(field.type, env, prop);
                }
            }
            return out;
        },

        .@"union" => {
            if (@hasDecl(T, "fromJs")) return T.fromJs(env, value);
            @compileError("napi-zig: union requires a `pub fn fromJs(env, val) !@This()` method: " ++ @typeName(T));
        },

        else => @compileError("napi-zig: unsupported type for fromJs: " ++ @typeName(T)),
    };
}

inline fn extract(comptime T: type, env: Env, value: Val, comptime nf: anytype, comptime label: [*:0]const u8) !T {
    var out: T = undefined;
    try expect(env, value, nf(env.handle, value.handle, &out), label);
    return out;
}

fn readCallback(env: Env, value: Val) !Callback {
    if (try value.typeOf(env) != .function) {
        var buf: [128]u8 = undefined;
        const msg = std.fmt.bufPrintZ(&buf, "expected function, got {s}", .{jsTypeName(env, value)}) catch "expected function";
        env.throwTypeError(msg);
        return err.Error.FunctionExpected;
    }
    return .{ .val = value };
}

// probe length, then read. napi_get_value_string_utf8 doesn't distinguish
// "fit exactly" from "truncated", so a stack fast path can't be correct.
fn readString(env: Env, value: Val) ![]const u8 {
    var len: usize = 0;
    try expect(env, value, c.napi_get_value_string_utf8(env.handle, value.handle, null, 0, &len), "expected string");
    const buf = try env.allocator().alloc(u8, len + 1);
    var written: usize = 0;
    try check(c.napi_get_value_string_utf8(env.handle, value.handle, buf.ptr, buf.len, &written));
    return buf[0..written];
}

fn expect(env: Env, value: Val, status: c.napi_status, comptime expected: [*:0]const u8) !void {
    if (status == .ok) return;
    var buf: [128]u8 = undefined;
    const dyn = std.fmt.bufPrintZ(&buf, "{s}, got {s}", .{ expected, jsTypeName(env, value) });
    env.throwTypeError(if (dyn) |s| s.ptr else |_| expected);
    return check(status);
}

fn jsTypeName(env: Env, value: Val) [*:0]const u8 {
    var vt: c.napi_valuetype = undefined;
    if (c.napi_typeof(env.handle, value.handle, &vt) != .ok) return "unknown";
    return switch (vt) {
        .undefined => "undefined",
        .null => "null",
        .boolean => "boolean",
        .number => "number",
        .string => "string",
        .symbol => "symbol",
        .object => "object",
        .function => "function",
        .external => "external",
        .bigint => "bigint",
    };
}
