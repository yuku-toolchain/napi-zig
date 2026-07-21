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

describe("Uint8Array arguments for []const u8", () => {
  const enc = new TextEncoder();

  test("encoded bytes round-trip like the equivalent string", () => {
    expect(m.roundtripString(enc.encode("hello"))).toBe("hello");
    expect(m.roundtripString(enc.encode(""))).toBe("");
    expect(m.roundtripString(enc.encode("héllo 世界 🦀"))).toBe("héllo 世界 🦀");
  });

  test("node Buffers are Uint8Arrays and work too", () => {
    expect(m.roundtripString(Buffer.from("hello", "utf8"))).toBe("hello");
  });

  test("byte length matches the typed array length", () => {
    expect(m.stringByteLength(enc.encode("é"))).toBe(2);
    expect(m.stringByteLength(new Uint8Array(1000))).toBe(1000);
  });

  test("subarray views respect byte offset and length", () => {
    const bytes = enc.encode("xxhelloxx");
    expect(m.roundtripString(bytes.subarray(2, 7))).toBe("hello");
  });

  test("mixes with string arguments", () => {
    expect(m.concatStrings(enc.encode("foo"), "bar")).toBe("foobar");
  });

  test("throws TypeError on non-u8 typed arrays", () => {
    expect(() => m.roundtripString(new Int32Array(4))).toThrow(TypeError);
    expect(() => m.roundtripString(new Float64Array(4))).toThrow(TypeError);
  });

  test("large payloads round-trip", () => {
    const big = "a".repeat(1_000_000);
    expect(m.roundtripString(enc.encode(big))).toBe(big);
  });
});

describe("strings above the single-pass conversion threshold", () => {
  // > 2^20 utf-16 units falls back to the exact two-pass conversion
  test("multibyte content round-trips through the exact path", () => {
    const n = (1 << 20) + 5;
    const big = "é".repeat(n);
    expect(m.stringByteLength(big)).toBe(n * 2);
    expect(m.roundtripString(big)).toBe(big);
  });
});
