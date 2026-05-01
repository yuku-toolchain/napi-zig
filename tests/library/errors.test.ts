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

describe("Env.throwValue (throw an arbitrary JS value)", () => {
  test("throwing a plain object surfaces it as the caught value", () => {
    const payload = { code: "E_BAD", details: [1, 2] };
    let caught: unknown;
    try {
      m.throwArbitraryValue(payload);
    } catch (e) {
      caught = e;
    }
    expect(caught).toBe(payload);
  });

  test("throwing a string", () => {
    let caught: unknown;
    try {
      m.throwArbitraryValue("string-as-thrown");
    } catch (e) {
      caught = e;
    }
    expect(caught).toBe("string-as-thrown");
  });

  test("throwing a number", () => {
    let caught: unknown;
    try {
      m.throwArbitraryValue(42);
    } catch (e) {
      caught = e;
    }
    expect(caught).toBe(42);
  });

  test("throwing a real Error instance preserves its identity", () => {
    const err = new RangeError("custom-range");
    let caught: unknown;
    try {
      m.throwArbitraryValue(err);
    } catch (e) {
      caught = e;
    }
    expect(caught).toBe(err);
    expect(caught).toBeInstanceOf(RangeError);
    expect((caught as Error).message).toBe("custom-range");
  });
});

describe("Env.isExceptionPending", () => {
  test("false during a normal call (no exception in flight)", () => {
    expect(m.isExceptionPendingNow()).toBe(false);
  });
});
