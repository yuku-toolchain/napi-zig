import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("Val.typeOf", () => {
  test("undefined", () => {
    expect(m.valTypeOf(undefined)).toBe("undefined");
  });
  test("null", () => {
    expect(m.valTypeOf(null)).toBe("null");
  });
  test("boolean", () => {
    expect(m.valTypeOf(true)).toBe("boolean");
    expect(m.valTypeOf(false)).toBe("boolean");
  });
  test("number", () => {
    expect(m.valTypeOf(42)).toBe("number");
    expect(m.valTypeOf(0.5)).toBe("number");
    expect(m.valTypeOf(NaN)).toBe("number");
  });
  test("string", () => {
    expect(m.valTypeOf("hi")).toBe("string");
    expect(m.valTypeOf("")).toBe("string");
  });
  test("symbol", () => {
    expect(m.valTypeOf(Symbol("x"))).toBe("symbol");
  });
  test("object", () => {
    expect(m.valTypeOf({})).toBe("object");
    expect(m.valTypeOf([])).toBe("object");
    expect(m.valTypeOf(new Date())).toBe("object");
    expect(m.valTypeOf(Buffer.alloc(1))).toBe("object");
  });
  test("function", () => {
    expect(m.valTypeOf(() => 0)).toBe("function");
    expect(m.valTypeOf(function f() {})).toBe("function");
  });
  test("bigint", () => {
    expect(m.valTypeOf(0n)).toBe("bigint");
    expect(m.valTypeOf(123n)).toBe("bigint");
  });
});

describe("Val.strictEquals", () => {
  test("same primitive", () => {
    expect(m.valStrictEquals(42, 42)).toBe(true);
    expect(m.valStrictEquals("hi", "hi")).toBe(true);
    expect(m.valStrictEquals(true, true)).toBe(true);
  });
  test("different primitive", () => {
    expect(m.valStrictEquals(42, 43)).toBe(false);
    expect(m.valStrictEquals(42, "42")).toBe(false);
  });
  test("NaN !== NaN (JS rule)", () => {
    expect(m.valStrictEquals(NaN, NaN)).toBe(false);
  });
  test("same object reference", () => {
    const o = {};
    expect(m.valStrictEquals(o, o)).toBe(true);
  });
  test("different object references with same shape", () => {
    expect(m.valStrictEquals({}, {})).toBe(false);
  });
  test("null vs undefined", () => {
    expect(m.valStrictEquals(null, null)).toBe(true);
    expect(m.valStrictEquals(undefined, undefined)).toBe(true);
    expect(m.valStrictEquals(null, undefined)).toBe(false);
  });
});

describe("Val.getProperty / setProperty (key is a Val)", () => {
  test("read property by Val key", () => {
    const obj = { foo: 1, bar: "two" };
    expect(m.valGetProperty(obj, "foo")).toBe(1);
    expect(m.valGetProperty(obj, "bar")).toBe("two");
  });

  test("set property by Val key (mutates)", () => {
    const obj: Record<string, unknown> = {};
    m.valSetProperty(obj, "x", 99);
    expect(obj.x).toBe(99);
  });

  test("symbol key", () => {
    const sym = Symbol("k");
    const obj: Record<symbol, unknown> = {};
    m.valSetProperty(obj, sym, "set-via-symbol");
    expect(obj[sym]).toBe("set-via-symbol");
  });

  test("missing key returns undefined", () => {
    expect(m.valGetProperty({}, "nope")).toBeUndefined();
  });
});

describe("Val.hasNamedProperty", () => {
  test("true when present", () => {
    expect(m.valHasNamedProperty({ a: 1 }, "a")).toBe(true);
  });
  test("false when absent", () => {
    expect(m.valHasNamedProperty({ a: 1 }, "b")).toBe(false);
  });
  test("inherited prototype property is reported", () => {
    expect(m.valHasNamedProperty({}, "toString")).toBe(true);
  });
});

describe("Val.getElement / setElement / getArrayLength", () => {
  test("getArrayLength on a JS array", () => {
    expect(m.valGetArrayLength([1, 2, 3])).toBe(3);
    expect(m.valGetArrayLength([])).toBe(0);
  });

  test("getElement reads by index", () => {
    expect(m.valGetElement([10, 20, 30], 1)).toBe(20);
  });

  test("getElement out-of-bounds returns undefined", () => {
    expect(m.valGetElement([1], 99)).toBeUndefined();
  });

  test("setElement mutates", () => {
    const arr = [0, 0, 0];
    m.valSetElement(arr, 1, 42);
    expect(arr).toEqual([0, 42, 0]);
  });

  test("setElement past length grows the array (JS semantics)", () => {
    const arr: unknown[] = [];
    m.valSetElement(arr, 5, "z");
    expect(arr.length).toBe(6);
    expect(arr[5]).toBe("z");
  });
});

describe("Env.createObject / createArrayWithLength + populate", () => {
  test("buildObjectFromKeys returns a populated object", () => {
    expect(m.buildObjectFromKeys(["a", "b", "c"], [1, 2, 3])).toEqual({
      a: 1,
      b: 2,
      c: 3,
    });
  });

  test("buildArrayFromInts returns a populated array", () => {
    expect(m.buildArrayFromInts([5, 6, 7])).toEqual([5, 6, 7]);
  });

  test("buildArrayFromInts of empty list", () => {
    expect(m.buildArrayFromInts([])).toEqual([]);
  });
});

describe("Env.getGlobal", () => {
  test("returns globalThis (the same reference)", () => {
    expect(m.valStrictEquals(m.getGlobalThis(), globalThis)).toBe(true);
  });

  test("globalThis has known properties", () => {
    const g = m.getGlobalThis();
    expect(typeof g.Math).toBe("object");
    expect(typeof g.JSON).toBe("object");
  });
});
