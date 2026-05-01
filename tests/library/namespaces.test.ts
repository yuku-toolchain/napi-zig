import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("namespaces", () => {
  test("function inside a namespace is callable", () => {
    expect(m.math.square(4)).toBe(16);
    expect(m.math.cube(3)).toBe(27);
  });

  test("nested namespaces (depth 2)", () => {
    expect(m.math.inner.deep(5)).toBe(1005);
  });

  test("nested namespaces (depth 3)", () => {
    expect(m.math.inner.deeper.deepest(7)).toBe(1_000_007);
  });

  test("snake_case namespace exposed as camelCase", () => {
    expect(m.constantsNs).toBeDefined();
    expect(m.constants_ns).toBeUndefined();
  });

  test("namespace can hold constants", () => {
    expect(m.constantsNs.pi).toBeCloseTo(3.14159);
    expect(m.constantsNs.e).toBeCloseTo(2.71828);
    expect(m.constantsNs.greeting).toBe("hello from namespace");
  });
});
