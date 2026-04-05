const std = @import("std");
const Env = @import("env.zig").Env;
const Val = @import("val.zig").Val;
const util = @import("util.zig");

// converts a Zig value to a JS value.
//
// - bool            -> Boolean
// - comptime_int    -> Number (f64)
// - integers        -> Number (up to 53 bits) or BigInt (54-64 bits)
// - comptime_float  -> Number (f64)
// - floats          -> Number
// - ?T              -> inner value or null
// - enums           -> String (tag name)
// - *const [N:0]u8  -> String (string literals)
// - []const u8      -> String (UTF-8)
// - []T             -> Array
// - structs         -> Object (field names converted to camelCase)
// - Val             -> passthrough
// - void            -> undefined
pub fn toJs(comptime T: type, env: Env, value: T) !Val {
    return switch (@typeInfo(T)) {
        .comptime_int => env.createFloat64(@floatFromInt(value)),
        .comptime_float => env.createFloat64(value),
        .bool => env.createBoolean(value),
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
        .optional => if (value) |v| toJs(@typeInfo(T).optional.child, env, v) else env.createNull(),
        .@"enum" => env.createString(@tagName(value)),
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) return env.createString(value);
            if (info.size == .slice) {
                const arr = try env.createArrayWithLength(@intCast(value.len));
                for (value, 0..) |item, i| {
                    try arr.setElement(env, @intCast(i), try toJs(info.child, env, item));
                }
                return arr;
            }
            if (info.size == .one) {
                const child = @typeInfo(info.child);
                if (child == .array and child.array.child == u8) {
                    const slice: []const u8 = value;
                    return env.createString(slice);
                }
            }
            @compileError("napi-zig: unsupported pointer type: " ++ @typeName(T));
        },
        .@"struct" => |info| {
            if (T == Val) return value;
            const obj = try env.createObject();
            inline for (info.fields) |field| {
                try obj.setNamedProperty(env, comptime util.snakeToCamel(field.name), try toJs(field.type, env, @field(value, field.name)));
            }
            return obj;
        },
        .void => env.createUndefined(),
        else => @compileError("napi-zig: unsupported type for toJs: " ++ @typeName(T)),
    };
}

// converts a JS value to a Zig type. called by Val.to(env, T).
//
// - bool        <- Boolean
// - integers    <- Number (up to 32 bits) or BigInt (33-64 unsigned)
// - floats      <- Number
// - ?T          <- null/undefined -> null, otherwise inner type
// - enums       <- String (accepts camelCase or exact Zig field name)
// - []const u8  <- String (allocated on env.arena)
// - []T         <- Array  (allocated on env.arena)
// - structs     <- Object (camelCase field matching, defaults respected)
// - Val         <- passthrough
pub fn fromJs(comptime T: type, env: Env, value: Val) !T {
    return switch (@typeInfo(T)) {
        .bool => value.toBool(env),
        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                0...32 => @intCast(try value.toInt32(env)),
                33...64 => @intCast(try value.toInt64(env)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
            .unsigned => switch (info.bits) {
                0...32 => @intCast(try value.toUint32(env)),
                33...64 => @intCast(try value.toBigintUint64(env)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
        },
        .float => @floatCast(try value.toFloat64(env)),
        .optional => |info| {
            const vtype = try value.typeOf(env);
            if (vtype == .null or vtype == .undefined) return null;
            return try fromJs(info.child, env, value);
        },
        .@"enum" => |info| {
            var buf: [256]u8 = undefined;
            const str = try value.toStringBuf(env, &buf);
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, str, comptime util.snakeToCamelSlice(field.name)) or
                    std.mem.eql(u8, str, field.name))
                    return @enumFromInt(field.value);
            }
            return @enumFromInt(info.fields[0].value);
        },
        .pointer => |info| {
            if (info.size == .slice and info.child == u8)
                return value.toStringAlloc(env, env.arena.allocator());
            if (info.size == .slice) {
                const len = try value.getArrayLength(env);
                const slice = try env.arena.allocator().alloc(info.child, len);
                for (slice, 0..) |*item, i| {
                    item.* = try fromJs(info.child, env, try value.getElement(env, @intCast(i)));
                }
                return slice;
            }
            @compileError("napi-zig: unsupported pointer type for fromJs: " ++ @typeName(T));
        },
        .@"struct" => |info| {
            if (T == Val) return value;
            var result: T = undefined;
            inline for (info.fields) |field| {
                const js_key = comptime util.snakeToCamel(field.name);
                const has = try value.hasNamedProperty(env, js_key);
                if (has) {
                    const prop = try value.getNamedProperty(env, js_key);
                    if (field.default_value_ptr != null and (try prop.typeOf(env)) == .undefined) {
                        @field(result, field.name) = field.defaultValue().?;
                    } else {
                        @field(result, field.name) = try fromJs(field.type, env, prop);
                    }
                } else if (field.default_value_ptr != null) {
                    @field(result, field.name) = field.defaultValue().?;
                } else {
                    env.throwTypeError("missing required field: " ++ js_key);
                    return error.napi_error;
                }
            }
            return result;
        },
        else => @compileError("napi-zig: unsupported type for fromJs: " ++ @typeName(T)),
    };
}
