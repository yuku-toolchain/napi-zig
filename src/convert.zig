const std = @import("std");
const c = @import("c.zig");
const Env = @import("env.zig").Env;
const val_mod = @import("val.zig");
const Val = val_mod.Val;
const JsFn = val_mod.JsFn;
const check = val_mod.check;
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
// - JsFn        <- Function (validated, wrapped)
// - Val         <- passthrough
pub fn fromJs(comptime T: type, env: Env, value: Val) !T {
    return switch (@typeInfo(T)) {
        .bool => {
            var result: bool = undefined;
            try check(c.napi_get_value_bool(env.raw, value.raw, &result));
            return result;
        },
        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                0...32 => {
                    var result: i32 = undefined;
                    try check(c.napi_get_value_int32(env.raw, value.raw, &result));
                    return @intCast(result);
                },
                33...64 => {
                    var result: i64 = undefined;
                    try check(c.napi_get_value_int64(env.raw, value.raw, &result));
                    return @intCast(result);
                },
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
            .unsigned => switch (info.bits) {
                0...32 => {
                    var result: u32 = undefined;
                    try check(c.napi_get_value_uint32(env.raw, value.raw, &result));
                    return @intCast(result);
                },
                33...64 => {
                    var result: u64 = undefined;
                    var lossless: bool = undefined;
                    try check(c.napi_get_value_bigint_uint64(env.raw, value.raw, &result, &lossless));
                    return @intCast(result);
                },
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
        },
        .float => {
            var result: f64 = undefined;
            try check(c.napi_get_value_double(env.raw, value.raw, &result));
            return @floatCast(result);
        },
        .optional => |opt| {
            const vtype = try value.typeOf(env);
            if (vtype == .null or vtype == .undefined) return null;
            return try fromJs(opt.child, env, value);
        },
        .@"enum" => |info| {
            var buf: [256]u8 = undefined;
            var len: usize = 0;
            try check(c.napi_get_value_string_utf8(env.raw, value.raw, &buf, buf.len, &len));
            const str = buf[0..len];
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, str, comptime util.snakeToCamelSlice(field.name)) or
                    std.mem.eql(u8, str, field.name))
                    return @enumFromInt(field.value);
            }
            return @enumFromInt(info.fields[0].value);
        },
        .pointer => |info| {
            if (info.size == .slice and info.child == u8) {
                const alloc = env.arena.allocator();
                var slen: usize = 0;
                try check(c.napi_get_value_string_utf8(env.raw, value.raw, null, 0, &slen));
                const sbuf = try alloc.alloc(u8, slen + 1);
                var written: usize = 0;
                try check(c.napi_get_value_string_utf8(env.raw, value.raw, sbuf.ptr, sbuf.len, &written));
                return sbuf[0..written];
            }
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
            if (T == JsFn) {
                const vtype = try value.typeOf(env);
                if (vtype != .function) {
                    env.throwTypeError("expected a function");
                    return error.napi_error;
                }
                return .{ .val = value };
            }
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
