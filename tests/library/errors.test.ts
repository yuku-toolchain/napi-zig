import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("Zig error → JS Error", () => {
  test("returning error.X throws an Error with message = error name", () => {
    let caught: Error | undefined;
    try {
      m.throwIfTrue(true);
    } catch (e) {
      caught = e as Error;
    }
    expect(caught).toBeInstanceOf(Error);
    expect(caught?.message).toBe("RequestedFailure");
  });

  test("happy path returns the value", () => {
    expect(m.throwIfTrue(false)).toBe(1);
  });

  test("DivisionByZero throws with that message", () => {
    expect(m.divideF64(10, 2)).toBe(5);
    expect(() => m.divideF64(1, 0)).toThrow("DivisionByZero");
  });
});

describe("type-conversion errors", () => {
  test("wrong-type arg throws TypeError, not Error", () => {
    let caught: Error | undefined;
    try {
      m.throwIfTrue("not a bool");
    } catch (e) {
      caught = e as Error;
    }
    expect(caught).toBeInstanceOf(TypeError);
  });

  test("TypeError messages name the actual type received", () => {
    let caught: Error | undefined;
    try {
      m.roundtripI32("hello");
    } catch (e) {
      caught = e as Error;
    }
    expect(caught?.message).toContain("number");
    expect(caught?.message).toContain("string");
  });
});

describe("explicit env.throw* + return error", () => {
  test("throwTypeError surfaces as a TypeError with the exact message", () => {
    let caught: Error | undefined;
    try {
      m.throwTypeErrorExplicit();
    } catch (e) {
      caught = e as Error;
    }
    expect(caught).toBeInstanceOf(TypeError);
    expect(caught?.message).toBe("explicit type error");
  });

  test("throwRangeError surfaces as a RangeError", () => {
    let caught: Error | undefined;
    try {
      m.throwRangeErrorExplicit();
    } catch (e) {
      caught = e as Error;
    }
    expect(caught).toBeInstanceOf(RangeError);
    expect(caught?.message).toBe("explicit range error");
  });

  test("throwError surfaces as a generic Error", () => {
    let caught: Error | undefined;
    try {
      m.throwGenericErrorExplicit();
    } catch (e) {
      caught = e as Error;
    }
    expect(caught).toBeInstanceOf(Error);
    expect(caught).not.toBeInstanceOf(TypeError);
    expect(caught).not.toBeInstanceOf(RangeError);
    expect(caught?.message).toBe("explicit generic error");
  });
});
