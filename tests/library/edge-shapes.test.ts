import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("slice of strings []const []const u8", () => {
  test("string array passed in is iterable in Zig", () => {
    expect(m.joinStrings(["a", "b", "c"], "-")).toBe("a-b-c");
  });

  test("empty array", () => {
    expect(m.joinStrings([], "-")).toBe("");
  });

  test("single element", () => {
    expect(m.joinStrings(["only"], "-")).toBe("only");
  });

  test("UTF-8 elements survive", () => {
    expect(m.joinStrings(["héllo", "世界"], " ")).toBe("héllo 世界");
  });

  test("string array returned from Zig", () => {
    expect(m.returnsStringArray()).toEqual(["alpha", "beta", "gamma"]);
  });

  test("non-string element throws TypeError", () => {
    expect(() => m.joinStrings(["a", 1 as any, "c"], "-")).toThrow(TypeError);
  });
});

describe("slice of structs []Point", () => {
  test("array of objects converts each element", () => {
    expect(
      m.sumPointXs([
        { x: 1, y: 0 },
        { x: 2, y: 0 },
        { x: 10, y: 0 },
      ]),
    ).toBe(13);
  });

  test("empty struct array", () => {
    expect(m.sumPointXs([])).toBe(0);
  });

  test("missing struct field inside array element throws TypeError", () => {
    expect(() => m.sumPointXs([{ x: 1, y: 2 }, { x: 3 } as any])).toThrow(TypeError);
  });

  test("array of structs returned from Zig", () => {
    expect(m.returnsPointArray()).toEqual([
      { x: 1, y: 2 },
      { x: 3, y: 4 },
    ]);
  });
});

describe("slice of optionals []const ?i32", () => {
  test("nulls are accepted as elements", () => {
    expect(m.sumOptionalI32Slice([1, null, 2, null, 3])).toBe(6);
  });

  test("undefined elements treated as null", () => {
    expect(m.sumOptionalI32Slice([1, undefined as any, 2])).toBe(3);
  });

  test("all-null array", () => {
    expect(m.sumOptionalI32Slice([null, null, null])).toBe(0);
  });
});

describe("nested optional inside struct (?{ a: ?i32, b: ?[]const u8 })", () => {
  test("inner present with all values", () => {
    expect(m.formatOuter({ name: "n", inner: { a: 1, b: "x" } })).toBe("n/1/x");
  });

  test("inner present with nested null fields", () => {
    expect(m.formatOuter({ name: "n", inner: { a: null, b: null } })).toBe("n/null/null");
  });

  test("inner absent (null)", () => {
    expect(m.formatOuter({ name: "n", inner: null })).toBe("n/null");
  });

  test("inner absent (missing)", () => {
    expect(m.formatOuter({ name: "n" })).toBe("n/null");
  });

  test("inner field a missing entirely", () => {
    expect(m.formatOuter({ name: "n", inner: { b: "y" } })).toBe("n/null/y");
  });
});

describe("optional return values", () => {
  test("?i32 returns inner value or null", () => {
    expect(m.maybeI32(true)).toBe(42);
    expect(m.maybeI32(false)).toBeNull();
  });

  test("?[]const u8 returns inner string or null", () => {
    expect(m.maybeString(true)).toBe("hello");
    expect(m.maybeString(false)).toBeNull();
  });

  test("?Val returns the inner Val passthrough or null", () => {
    expect(m.maybeVal(true)).toBe(42);
    expect(m.maybeVal(false)).toBeNull();
  });
});

describe("Callback as a struct field", () => {
  test("each callback fires with the right args", () => {
    const data: number[] = [];
    let doneCalled = false;
    m.fireHandlers(
      {
        onData: (v: number) => data.push(v),
        onDone: () => {
          doneCalled = true;
        },
      },
      7,
    );
    expect(data).toEqual([7]);
    expect(doneCalled).toBe(true);
  });

  test("non-function field throws TypeError", () => {
    expect(() => m.fireHandlers({ onData: "nope", onDone: () => {} }, 1)).toThrow(TypeError);
  });

  test("missing field (no defaults) throws TypeError", () => {
    expect(() => m.fireHandlers({ onData: () => {} } as any, 1)).toThrow(TypeError);
  });
});

describe("nested slice [][]i32", () => {
  test("recursively converts inner arrays", () => {
    expect(m.nestedSliceSum([[1, 2, 3], [10, 20], [], [100]])).toBe(136);
  });

  test("empty outer array", () => {
    expect(m.nestedSliceSum([])).toBe(0);
  });
});

describe("enum as a struct field", () => {
  test("camelCase enum value accepted in struct field", () => {
    expect(m.formatWithEnum({ name: "n", level: "warning" })).toBe("n/warning");
    expect(m.formatWithEnum({ name: "n", level: "errorLevel" })).toBe("n/error_level");
  });

  test("invalid enum value in struct field throws TypeError", () => {
    expect(() => m.formatWithEnum({ name: "n", level: "nope" })).toThrow(TypeError);
  });
});

describe("array of enums []Level", () => {
  test("camelCase tags accepted in array elements", () => {
    expect(m.sumLevels(["debug", "info", "warning", "errorLevel"])).toBe(0 + 1 + 2 + 3);
  });

  test("array of enums returned from Zig uses camelCase", () => {
    expect(m.returnsLevelArray()).toEqual(["info", "warning", "errorLevel"]);
  });

  test("invalid tag inside array throws TypeError", () => {
    expect(() => m.sumLevels(["debug", "bogus"])).toThrow(TypeError);
  });
});

describe("tuple as a struct field", () => {
  test("inline tuple field accepts a JS array", () => {
    expect(m.formatWithTuple({ name: "n", point: [3, 4] })).toBe("n/3,4");
  });

  test("wrong tuple element type throws TypeError", () => {
    expect(() => m.formatWithTuple({ name: "n", point: [3, "four"] as any })).toThrow(TypeError);
  });
});

describe("tuple of structs", () => {
  test("PointPair (struct{Point, Point}) accepts an array of two objects", () => {
    expect(
      m.pointPairSum([
        { x: 1, y: 2 },
        { x: 10, y: 20 },
      ]),
    ).toBe(33);
  });
});

describe("BigInt overflow handling", () => {
  test("BigInt above i64 max throws (does not silently wrap)", () => {
    const tooBig = (1n << 63n) + 1n;
    expect(() => m.roundtripI64(tooBig)).toThrow(RangeError);
  });

  test("BigInt below i64 min throws (does not silently wrap)", () => {
    const tooSmall = -(1n << 63n) - 1n;
    expect(() => m.roundtripI64(tooSmall)).toThrow(RangeError);
  });

  test("negative BigInt to u64 throws (does not silently wrap)", () => {
    expect(() => m.roundtripU64(-1n)).toThrow(RangeError);
  });

  test("BigInt above u64 max throws", () => {
    const tooBig = (1n << 64n) + 1n;
    expect(() => m.roundtripU64(tooBig)).toThrow(RangeError);
  });
});
