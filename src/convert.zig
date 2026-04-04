/// Bidirectional type mapping between Zig values and JavaScript values.
///
/// `toJs` and `fromJs` handle automatic conversion of Zig primitives, optionals,
/// enums, slices, and structs to/from their JavaScript equivalents. These are
/// used by the module registration in `module.zig` and can also be called directly.

const std = @import("std");
const c = @import("c.zig");
const Env = @import("env.zig").Env;
const Val = @import("val.zig").Val;
const check = @import("val.zig").check;
const util = @import("util.zig");

/// Converts a Zig value to a JavaScript value.
///
/// Supported types:
/// - `bool`            -> JS `Boolean`
/// - `comptime_int`    -> JS `Number` (f64)
/// - integers          -> JS `Number` (up to 53 bits) or `BigInt` (54-64 bits)
/// - `comptime_float`  -> JS `Number` (f64)
/// - floats            -> JS `Number`
/// - `?T`              -> the inner value, or JS `null`
/// - enums             -> JS `String` (the tag name)
/// - `*const [N:0]u8`  -> JS `String` (string literals)
/// - `[]const u8`      -> JS `String` (UTF-8)
/// - `[]T`             -> JS `Array`
/// - structs           -> JS `Object` (field names converted to camelCase)
/// - `Val`             -> passed through as-is
/// - `void`            -> JS `undefined`
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
            // String slices: []const u8
            if (info.size == .slice and info.child == u8) return env.createString(value);
            // Generic slices: []T -> JS Array
            if (info.size == .slice) {
                const arr = try env.createArrayWithLength(@intCast(value.len));
                for (value, 0..) |item, i| {
                    try arr.setElement(env, @intCast(i), try toJs(info.child, env, item));
                }
                return arr;
            }
            // String literal pointers: *const [N:0]u8, *const [N]u8
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

/// Converts a JavaScript value to a Zig type.
///
/// Supported types:
/// - `bool`        <- JS `Boolean`
/// - integers      <- JS `Number` (up to 32 bits) or `BigInt` (33-64 unsigned)
/// - floats        <- JS `Number`
/// - `?T`          <- JS `null`/`undefined` -> Zig `null`, otherwise inner type
/// - enums         <- JS `String` (accepts camelCase or exact Zig field name)
/// - structs       <- JS `Object` (field names matched as camelCase; missing
///                    fields use defaults or produce a `TypeError`)
/// - `Val`         <- passed through as-is
pub fn fromJs(comptime T: type, env: Env, value: Val) !T {
    return switch (@typeInfo(T)) {
        .bool => value.getBoolean(env),
        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                0...32 => @intCast(try value.getInt32(env)),
                33...64 => @intCast(try value.getInt64(env)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
            .unsigned => switch (info.bits) {
                0...32 => @intCast(try value.getUint32(env)),
                33...64 => @intCast(try value.getBigintUint64(env)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
        },
        .float => @floatCast(try value.getFloat64(env)),
        .optional => |info| {
            const vtype = try value.typeOf(env);
            if (vtype == .null or vtype == .undefined) return null;
            return try fromJs(info.child, env, value);
        },
        .@"enum" => |info| {
            var buf: [256]u8 = undefined;
            const str = try value.getStringIntoBuf(env, &buf);
            inline for (info.fields) |field| {
                // accept camelCase (JS convention) or exact zig name
                if (std.mem.eql(u8, str, comptime util.snakeToCamelSlice(field.name)) or
                    std.mem.eql(u8, str, field.name))
                    return @enumFromInt(field.value);
            }
            return @enumFromInt(info.fields[0].value);
        },
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) {
                @compileError("napi-zig: cannot convert JS string to []const u8 without allocator. Use raw mode.");
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
