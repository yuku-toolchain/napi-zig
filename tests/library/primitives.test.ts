import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("bool", () => {
  test("round-trips true and false", () => {
    expect(m.roundtripBool(true)).toBe(true);
    expect(m.roundtripBool(false)).toBe(false);
  });

  test("throws TypeError on non-bool", () => {
    expect(() => m.roundtripBool("yes")).toThrow(TypeError);
    expect(() => m.roundtripBool(1)).toThrow(TypeError);
    expect(() => m.roundtripBool(null)).toThrow(TypeError);
  });
});

describe("signed integers", () => {
  test("i8 round-trips at boundaries", () => {
    expect(m.roundtripI8(0)).toBe(0);
    expect(m.roundtripI8(127)).toBe(127);
    expect(m.roundtripI8(-128)).toBe(-128);
  });

  test("i16 round-trips at boundaries", () => {
    expect(m.roundtripI16(0)).toBe(0);
    expect(m.roundtripI16(32767)).toBe(32767);
    expect(m.roundtripI16(-32768)).toBe(-32768);
  });

  test("i32 round-trips at boundaries", () => {
    expect(m.roundtripI32(0)).toBe(0);
    expect(m.roundtripI32(2 ** 31 - 1)).toBe(2 ** 31 - 1);
    expect(m.roundtripI32(-(2 ** 31))).toBe(-(2 ** 31));
  });

  test("i53 round-trips through f64", () => {
    // i53 range: -(2^52) .. (2^52 - 1)
    expect(m.roundtripI53(0)).toBe(0);
    expect(m.roundtripI53(2 ** 31)).toBe(2 ** 31);
    expect(m.roundtripI53(2 ** 52 - 1)).toBe(2 ** 52 - 1);
    expect(m.roundtripI53(-(2 ** 52))).toBe(-(2 ** 52));
  });

  test("i53 throws RangeError when value exceeds the type", () => {
    expect(() => m.roundtripI53(2 ** 52)).toThrow(RangeError);
    expect(() => m.roundtripI53(-(2 ** 52) - 1)).toThrow(RangeError);
  });

  test("i64 round-trips through BigInt", () => {
    expect(m.roundtripI64(0n)).toBe(0n);
    expect(m.roundtripI64(123n)).toBe(123n);
    expect(m.roundtripI64(9_223_372_036_854_775_807n)).toBe(9_223_372_036_854_775_807n);
    expect(m.roundtripI64(-9_223_372_036_854_775_808n)).toBe(-9_223_372_036_854_775_808n);
  });

  test("integer functions throw TypeError on wrong type", () => {
    expect(() => m.roundtripI32("hi")).toThrow(TypeError);
    expect(() => m.roundtripI32(true)).toThrow(TypeError);
    expect(() => m.roundtripI64(1)).toThrow(TypeError); // expects bigint
  });
});

describe("unsigned integers", () => {
  test("u8 round-trips", () => {
    expect(m.roundtripU8(0)).toBe(0);
    expect(m.roundtripU8(255)).toBe(255);
  });

  test("u16 round-trips", () => {
    expect(m.roundtripU16(0)).toBe(0);
    expect(m.roundtripU16(65535)).toBe(65535);
  });

  test("u32 round-trips", () => {
    expect(m.roundtripU32(0)).toBe(0);
    expect(m.roundtripU32(2 ** 32 - 1)).toBe(2 ** 32 - 1);
  });

  test("u53 round-trips through f64", () => {
    // u53 range: 0 .. (2^53 - 1) - i.e. up to MAX_SAFE_INTEGER
    expect(m.roundtripU53(0)).toBe(0);
    expect(m.roundtripU53(Number.MAX_SAFE_INTEGER)).toBe(Number.MAX_SAFE_INTEGER);
  });

  test("narrow signed types throw RangeError on overflow", () => {
    expect(() => m.roundtripI8(128)).toThrow(RangeError);
    expect(() => m.roundtripI8(-129)).toThrow(RangeError);
    expect(() => m.roundtripI16(32768)).toThrow(RangeError);
    expect(() => m.roundtripI16(-32769)).toThrow(RangeError);
  });

  test("narrow unsigned types throw RangeError on overflow", () => {
    expect(() => m.roundtripU8(256)).toThrow(RangeError);
    expect(() => m.roundtripU16(65536)).toThrow(RangeError);
  });

  test("u53 rejects negative input directly", () => {
    expect(() => m.roundtripU53(-1)).toThrow(RangeError);
  });

  test("u64 round-trips through BigInt", () => {
    expect(m.roundtripU64(0n)).toBe(0n);
    expect(m.roundtripU64(18_446_744_073_709_551_615n)).toBe(18_446_744_073_709_551_615n);
  });
});

describe("floats", () => {
  test("f32 round-trips with float32 precision", () => {
    expect(m.roundtripF32(0)).toBe(0);
    expect(m.roundtripF32(1.5)).toBe(1.5);
    expect(m.roundtripF32(-1.5)).toBe(-1.5);
    // 0.1 isn't exactly representable; round trip drops to f32 precision
    expect(m.roundtripF32(0.1)).toBeCloseTo(0.1, 6);
  });

  test("f64 round-trips losslessly", () => {
    expect(m.roundtripF64(0)).toBe(0);
    expect(m.roundtripF64(0.1)).toBe(0.1);
    expect(m.roundtripF64(Math.PI)).toBe(Math.PI);
    expect(m.roundtripF64(Number.MAX_VALUE)).toBe(Number.MAX_VALUE);
    expect(m.roundtripF64(Number.MIN_VALUE)).toBe(Number.MIN_VALUE);
  });

  test("f16 round-trips with float16 precision", () => {
    expect(m.roundtripF16(0)).toBe(0);
    expect(m.roundtripF16(1.5)).toBe(1.5);
  });

  test("special floats", () => {
    expect(m.roundtripF64(Infinity)).toBe(Infinity);
    expect(m.roundtripF64(-Infinity)).toBe(-Infinity);
    expect(Number.isNaN(m.roundtripF64(NaN))).toBe(true);
  });
});

describe("optional / null / undefined", () => {
  test("returns null for ?T null", () => {
    expect(m.returnsNull()).toBeNull();
  });

  test("returns inner value for ?T some", () => {
    expect(m.returnsSomeInt()).toBe(7);
  });

  test("?i32 round-trips a value", () => {
    expect(m.roundtripOptionalI32(42)).toBe(42);
  });

  test("?i32 round-trips null", () => {
    expect(m.roundtripOptionalI32(null)).toBeNull();
  });

  test("?i32 round-trips undefined as null", () => {
    expect(m.roundtripOptionalI32(undefined)).toBeNull();
  });
});

describe("void", () => {
  test("void return becomes undefined", () => {
    expect(m.returnsVoid()).toBeUndefined();
  });
});
