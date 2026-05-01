import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("constants", () => {
  test("bool true", () => {
    expect(m.boolTrue).toBe(true);
  });

  test("bool false", () => {
    expect(m.boolFalse).toBe(false);
  });

  test("positive i32", () => {
    expect(m.i32Value).toBe(42);
  });

  test("negative i32", () => {
    expect(m.i32Neg).toBe(-42);
  });

  test("i32 max", () => {
    expect(m.i32Max).toBe(2 ** 31 - 1);
  });

  test("u32 max", () => {
    expect(m.u32Max).toBe(2 ** 32 - 1);
  });

  test("f64 value", () => {
    expect(m.f64Pi).toBeCloseTo(3.14159265358979, 10);
  });

  test("string value", () => {
    expect(m.stringValue).toBe("constant string");
  });

  test("empty string", () => {
    expect(m.emptyString).toBe("");
  });

  test("snake_case constant exposed as camelCase", () => {
    expect(m.snakeCaseName).toBe(7);
    expect(m.snake_case_name).toBeUndefined();
  });

  test("comptime_int constant", () => {
    expect(m.comptimeIntValue).toBe(12345);
  });

  test("comptime_float constant", () => {
    expect(m.comptimeFloatValue).toBe(1.5);
  });

  test("sentinel-terminated string pointer", () => {
    expect(m.sentinelString).toBe("hello");
  });
});
