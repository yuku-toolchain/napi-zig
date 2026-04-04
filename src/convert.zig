// type mapping rules between Zig and JavaScript.

const std = @import("std");
const c = @import("c.zig");
const Env = @import("env.zig").Env;
const Val = @import("val.zig").Val;
const check = @import("val.zig").check;
const util = @import("util.zig");

/// convert a zig value to a js value.
pub fn toJs(comptime T: type, env: Env, value: T) !Val {
    return switch (@typeInfo(T)) {
        .bool => env.boolean(value),
        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                0...32 => env.int32(@intCast(value)),
                33...53 => env.float64(@floatFromInt(value)),
                54...64 => env.bigintI64(@intCast(value)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
            .unsigned => switch (info.bits) {
                0...32 => env.uint32(@intCast(value)),
                33...53 => env.float64(@floatFromInt(value)),
                54...64 => env.bigintU64(@intCast(value)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
        },
        .float => |info| switch (info.bits) {
            16, 32, 64 => env.float64(@floatCast(value)),
            else => @compileError("napi-zig: unsupported float width: " ++ @typeName(T)),
        },
        .optional => if (value) |v| toJs(@typeInfo(T).optional.child, env, v) else env.@"null"(),
        .@"enum" => env.string(@tagName(value)),
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) return env.string(value);
            if (info.size == .slice) {
                const arr = try env.arrayWithLength(@intCast(value.len));
                for (value, 0..) |item, i| {
                    try arr.setElement(env, @intCast(i), try toJs(info.child, env, item));
                }
                return arr;
            }
            @compileError("napi-zig: unsupported pointer type: " ++ @typeName(T));
        },
        .@"struct" => |info| {
            if (T == Val) return value;
            const obj = try env.object();
            inline for (info.fields) |field| {
                try obj.setNamed(env, comptime util.snakeToCamel(field.name), try toJs(field.type, env, @field(value, field.name)));
            }
            return obj;
        },
        .void => env.@"undefined"(),
        else => @compileError("napi-zig: unsupported type for toJs: " ++ @typeName(T)),
    };
}

/// convert a js value to a zig type.
pub fn fromJs(comptime T: type, env: Env, value: Val) !T {
    return switch (@typeInfo(T)) {
        .bool => value.boolean(env),
        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                0...32 => @intCast(try value.getI32(env)),
                33...64 => @intCast(try value.getI64(env)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
            .unsigned => switch (info.bits) {
                0...32 => @intCast(try value.getU32(env)),
                33...64 => @intCast(try value.getBigintU64(env)),
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
        },
        .float => @floatCast(try value.getF64(env)),
        .optional => |info| {
            const vtype = try value.typeOf(env);
            if (vtype == .null or vtype == .undefined) return null;
            return try fromJs(info.child, env, value);
        },
        .@"enum" => |info| {
            var buf: [256]u8 = undefined;
            const str = try value.stringBuf(env, &buf);
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
                const has = try value.hasNamed(env, js_key);
                if (has) {
                    const prop = try value.getNamed(env, js_key);
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
