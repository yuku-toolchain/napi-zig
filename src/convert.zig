const std = @import("std");
const c = @import("c.zig");
const err = @import("error.zig");
const util = @import("util.zig");
const Env = @import("env.zig").Env;
const val_mod = @import("val.zig");
const Val = val_mod.Val;
const Callback = val_mod.Callback;

const check = err.check;

// Zig → JS
//
// Type mapping:
//   bool / void / ?T               → Boolean / undefined / null-or-T
//   integers up to i32/u32         → Number
//   integers up to i53/u53         → Number (via f64)
//   integers i54..i64 / u54..u64   → BigInt
//   f16 / f32 / f64                → Number
//   enum                           → String (tag name, snake → camel)
//   []const u8                     → String
//   []T / [N]T                     → Array
//   tuple struct                   → Array
//   struct with `toJs(env)` method → custom
//   plain struct                   → Object (snake_case fields → camelCase)
//   union                          → must define `toJs(env)` method
//   Val                            → passthrough
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
            @compileError("napi-zig: unsupported pointer type for toJs: " ++ @typeName(T));
        },

        .array => |info| {
            const arr = try env.createArrayWithLength(@intCast(info.len));
            for (0..info.len) |i| {
                try arr.setElement(env, @intCast(i), try toJs(info.child, env, value[i]));
            }
            return arr;
        },

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
            // Plain struct → object. One create + N set_named_property calls.
            // (`napi_define_properties` would batch but requires per-call
            // descriptor allocation — net loss for small N.)
            const obj = try env.createObject();
            inline for (info.fields) |field| {
                const key = comptime util.snakeToCamel(field.name);
                try obj.setNamedProperty(env, key, try toJs(field.type, env, @field(value, field.name)));
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

// JS → Zig
//
// Type mapping mirrors `toJs`. Missing struct fields use Zig defaults
// when present, otherwise throw `TypeError`. Unknown enum strings
// throw `TypeError`. All allocations come from `env.allocator()`.
pub fn fromJs(comptime T: type, env: Env, value: Val) !T {
    return switch (@typeInfo(T)) {
        .bool => {
            var out: bool = undefined;
            try expect(env, value, c.napi_get_value_bool(env.handle, value.handle, &out), "expected boolean");
            return out;
        },

        .int => |info| switch (info.signedness) {
            .signed => switch (info.bits) {
                0...32 => {
                    var out: i32 = undefined;
                    try expect(env, value, c.napi_get_value_int32(env.handle, value.handle, &out), "expected number");
                    return @intCast(out);
                },
                33...64 => {
                    var out: i64 = undefined;
                    try expect(env, value, c.napi_get_value_int64(env.handle, value.handle, &out), "expected number");
                    return @intCast(out);
                },
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
            .unsigned => switch (info.bits) {
                0...32 => {
                    var out: u32 = undefined;
                    try expect(env, value, c.napi_get_value_uint32(env.handle, value.handle, &out), "expected number");
                    return @intCast(out);
                },
                33...64 => {
                    var out: u64 = undefined;
                    var lossless: bool = undefined;
                    try expect(env, value, c.napi_get_value_bigint_uint64(env.handle, value.handle, &out, &lossless), "expected bigint");
                    return @intCast(out);
                },
                else => @compileError("napi-zig: integer too wide: " ++ @typeName(T)),
            },
        },

        .float => {
            var out: f64 = undefined;
            try expect(env, value, c.napi_get_value_double(env.handle, value.handle, &out), "expected number");
            return @floatCast(out);
        },

        .optional => |opt| {
            const vt = try value.typeOf(env);
            if (vt == .null or vt == .undefined) return null;
            return try fromJs(opt.child, env, value);
        },

        .@"enum" => |info| {
            // small stack buffer covers virtually all enum names
            var stack: [128]u8 = undefined;
            var n: usize = 0;
            try expect(env, value, c.napi_get_value_string_utf8(env.handle, value.handle, &stack, stack.len, &n), "expected string");
            const str = stack[0..n];
            inline for (info.fields) |field| {
                if (std.mem.eql(u8, str, comptime util.snakeToCamelSlice(field.name)) or
                    std.mem.eql(u8, str, field.name))
                {
                    return @enumFromInt(field.value);
                }
            }
            var ebuf: [192]u8 = undefined;
            const msg = std.fmt.bufPrintZ(&ebuf, "invalid enum value for " ++ @typeName(T) ++ ": '{s}'", .{str}) catch "invalid enum value";
            env.throwTypeError(msg);
            return err.Error.InvalidArg;
        },

        .pointer => |info| {
            if (info.size == .slice and info.child == u8) {
                return readString(env, value);
            }
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
            if (T == Callback) {
                const vt = try value.typeOf(env);
                if (vt != .function) {
                    var buf: [128]u8 = undefined;
                    const msg = std.fmt.bufPrintZ(&buf, "expected function, got {s}", .{jsTypeName(env, value)}) catch "expected function";
                    env.throwTypeError(msg);
                    return err.Error.FunctionExpected;
                }
                return .{ .val = value };
            }
            if (@hasDecl(T, "fromJs")) return T.fromJs(env, value);
            if (info.is_tuple) {
                var out: T = undefined;
                inline for (info.fields, 0..) |field, i| {
                    @field(out, field.name) = try fromJs(field.type, env, try value.getElement(env, @intCast(i)));
                }
                return out;
            }
            // Plain struct: one get_named_property per field, treat
            // undefined as "missing" for fields with defaults.
            var out: T = undefined;
            inline for (info.fields) |field| {
                const key = comptime util.snakeToCamel(field.name);
                const prop = try value.getNamedProperty(env, key);
                const vt = try prop.typeOf(env);
                if (vt == .undefined) {
                    if (field.default_value_ptr) |_| {
                        @field(out, field.name) = field.defaultValue().?;
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

// Reads a JS string into an arena-allocated UTF-8 slice.
// Two N-API calls (probe + read). Stack-buffer fast path for short
// strings would be a perf win if napi_get_value_string_utf8 reported
// truncation distinctly from "fit exactly", but it doesn't, so we
// keep this correct and simple.
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
    if (std.fmt.bufPrintZ(&buf, "{s}, got {s}", .{ expected, jsTypeName(env, value) })) |msg| {
        env.throwTypeError(msg.ptr);
    } else |_| {
        env.throwTypeError(expected);
    }
    return err.check(status);
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
