import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("strings", () => {
  test("ASCII round-trips", () => {
    expect(m.roundtripString("hello")).toBe("hello");
  });

  test("empty string round-trips", () => {
    expect(m.roundtripString("")).toBe("");
    expect(m.returnsEmptyString()).toBe("");
  });

  test("UTF-8 multibyte round-trips byte-for-byte", () => {
    const s = "héllo 世界 🦀";
    expect(m.roundtripString(s)).toBe(s);
  });

  test("string length is byte length, not codepoint count", () => {
    expect(m.stringByteLength("hello")).toBe(5);
    expect(m.stringByteLength("")).toBe(0);
    expect(m.stringByteLength("é")).toBe(2);
    expect(m.stringByteLength("世")).toBe(3);
    expect(m.stringByteLength("🦀")).toBe(4);
  });

  test("concat", () => {
    expect(m.concatStrings("foo", "bar")).toBe("foobar");
    expect(m.concatStrings("", "x")).toBe("x");
    expect(m.concatStrings("x", "")).toBe("x");
    expect(m.concatStrings("", "")).toBe("");
  });

  test("large strings round-trip without truncation", () => {
    const big = "a".repeat(100_000);
    expect(m.roundtripString(big)).toBe(big);
    expect(m.returnsLargeString(100_000)).toBe(big);
  });

  test("string at near-arena-page-boundary sizes", () => {
    for (const n of [4095, 4096, 4097, 65535, 65536, 65537]) {
      const s = "x".repeat(n);
      expect(m.roundtripString(s)).toBe(s);
      expect(m.stringByteLength(s)).toBe(n);
    }
  });

  test("throws TypeError on non-string", () => {
    expect(() => m.roundtripString(123)).toThrow(TypeError);
    expect(() => m.roundtripString(true)).toThrow(TypeError);
    expect(() => m.roundtripString(null)).toThrow(TypeError);
  });
});
