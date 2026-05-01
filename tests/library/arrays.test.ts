import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("slice arguments ([]const T)", () => {
  test("sums an i32 array", () => {
    expect(m.sumI32Slice([1, 2, 3, 4])).toBe(10);
  });

  test("empty array sums to 0", () => {
    expect(m.sumI32Slice([])).toBe(0);
  });

  test("large array", () => {
    const arr = Array.from({ length: 10_000 }, (_, i) => i);
    const expected = (10_000 * 9999) / 2;
    expect(m.sumI32Slice(arr)).toBe(expected);
  });

  test("throws TypeError on non-array", () => {
    expect(() => m.sumI32Slice("nope")).toThrow(TypeError);
    expect(() => m.sumI32Slice(42)).toThrow(TypeError);
  });

  test("throws TypeError on element type mismatch", () => {
    expect(() => m.sumI32Slice([1, "two", 3])).toThrow(TypeError);
  });
});

describe("fixed-size arrays ([N]T)", () => {
  test("round-trips a [3]i32", () => {
    expect(m.roundtripFixedArray([1, 2, 3])).toEqual([1, 2, 3]);
  });

  test("element-type errors propagate from inside the array", () => {
    expect(() => m.roundtripFixedArray([1, "two", 3])).toThrow(TypeError);
  });
});

describe("array return values", () => {
  test("returns []i32 of N", () => {
    expect(m.returnsArrayOfN(0)).toEqual([]);
    expect(m.returnsArrayOfN(1)).toEqual([0]);
    expect(m.returnsArrayOfN(5)).toEqual([0, 1, 2, 3, 4]);
  });

  test("returns empty array", () => {
    expect(m.returnsEmptyArray()).toEqual([]);
  });
});

describe("tuples (struct { S, T })", () => {
  test("tuple in: first element extracted", () => {
    expect(m.tupleFirst([42, "hello"])).toBe(42);
  });

  test("tuple in: second element extracted", () => {
    expect(m.tupleSecondLen([0, "hello"])).toBe(5);
  });

  test("tuple out becomes a JS array", () => {
    expect(m.returnsTuple()).toEqual([42, "hello"]);
  });
});
