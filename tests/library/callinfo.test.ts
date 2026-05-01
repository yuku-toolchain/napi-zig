import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("variadic via raw mode (Env, CallInfo)", () => {
  test("sums any number of numeric args", () => {
    expect(m.variadicSum()).toBe(0);
    expect(m.variadicSum(1)).toBe(1);
    expect(m.variadicSum(1, 2, 3)).toBe(6);
    expect(m.variadicSum(1.5, 2.5, 3.0)).toBe(7);
  });

  test("up to the declared max (16)", () => {
    const args = Array.from({ length: 16 }, (_, i) => i + 1);
    const expected = args.reduce((a, b) => a + b, 0);
    expect(m.variadicSum(...args)).toBe(expected);
  });
});

describe("argCount", () => {
  test("returns the number of args actually passed", () => {
    expect(m.rawArgCount()).toBe(0);
    expect(m.rawArgCount("a")).toBe(1);
    expect(m.rawArgCount("a", "b", "c")).toBe(3);
  });
});

describe("this binding via CallInfo.this", () => {
  test("reads a property off the this object", () => {
    const obj = { marker: "found" };
    expect(m.rawThisMarker.call(obj)).toBe("found");
  });

  test("works with a numeric marker", () => {
    expect(m.rawThisMarker.call({ marker: 42 })).toBe(42);
  });
});
