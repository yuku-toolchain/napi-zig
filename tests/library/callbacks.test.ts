import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("Callback.call with tuple args", () => {
  test("forEach invokes the callback once per item with (item, index)", () => {
    const seen: [unknown, number][] = [];
    m.forEach([10, 20, 30], (item: unknown, i: number) => {
      seen.push([item, i]);
    });
    expect(seen).toEqual([
      [10, 0],
      [20, 1],
      [30, 2],
    ]);
  });

  test("empty array means callback never runs", () => {
    let ran = false;
    m.forEach([], () => {
      ran = true;
    });
    expect(ran).toBe(false);
  });

  test("callback return value is observed (applyTwice)", () => {
    expect(m.applyTwice((x: number) => x + 1, 5)).toBe(7);
    expect(m.applyTwice((x: number) => x * 2, 3)).toBe(12);
  });
});

describe("Callback.call with []const Val slice", () => {
  test("slice-arg form produces a JS call with the values", () => {
    const args: number[] = [];
    m.callbackWithSliceArgs((a: number, b: number, c: number) => {
      args.push(a, b, c);
    });
    expect(args).toEqual([1, 2, 3]);
  });
});

describe("callWith (this binding)", () => {
  test("`this` is bound to the value passed to callWith", () => {
    const obj = { name: "alice" };
    const result = m.callWithThis(obj, function (this: { name: string }) {
      return this.name;
    });
    expect(result).toBe("alice");
  });
});

describe("non-function arg throws TypeError", () => {
  test("forEach with a non-function callback", () => {
    expect(() => m.forEach([1, 2], "not a function")).toThrow(TypeError);
  });

  test("error message names what was expected", () => {
    let caught: Error | undefined;
    try {
      m.forEach([1, 2], 42);
    } catch (e) {
      caught = e as Error;
    }
    expect(caught?.message.toLowerCase()).toContain("function");
  });
});

describe("exceptions thrown inside the JS callback propagate to the caller", () => {
  test("callback throw surfaces as the original Error", () => {
    expect(() =>
      m.forEach([1, 2, 3], () => {
        throw new Error("boom");
      }),
    ).toThrow("boom");
  });

  test("callback throwing TypeError surfaces as TypeError", () => {
    expect(() =>
      m.forEach([1], () => {
        throw new TypeError("wrong");
      }),
    ).toThrow(TypeError);
  });

  test("forEach stops at the first throw (no further iterations)", () => {
    let calls = 0;
    expect(() =>
      m.forEach([1, 2, 3, 4], () => {
        calls++;
        if (calls === 2) throw new Error("stop");
      }),
    ).toThrow("stop");
    expect(calls).toBe(2);
  });
});
