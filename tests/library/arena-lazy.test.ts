import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("the per-call arena is lazy", () => {
  test("a primitive parameter does not touch the arena", () => {
    expect(m.arenaIsEmptyWithI32(0)).toBe(true);
    expect(m.arenaIsEmptyWithI32(42)).toBe(true);
    expect(m.arenaIsEmptyWithI32(-1)).toBe(true);
  });

  test("a napi.Val parameter does not touch the arena", () => {
    expect(m.arenaIsEmptyWithVal("hello")).toBe(true);
    expect(m.arenaIsEmptyWithVal("a".repeat(10_000))).toBe(true);
    expect(m.arenaIsEmptyWithVal({ key: "value" })).toBe(true);
    expect(m.arenaIsEmptyWithVal([1, 2, 3])).toBe(true);
    expect(m.arenaIsEmptyWithVal(null)).toBe(true);
  });

  test("a []const u8 parameter triggers an arena alloc", () => {
    expect(m.arenaIsEmptyWithSlice("hello")).toBe(false);
    expect(m.arenaIsEmptyWithSlice("")).toBe(false);
    expect(m.arenaIsEmptyWithSlice("a".repeat(10_000))).toBe(false);
  });

  test("Val.getStringLength returns the UTF-8 byte length without allocating", () => {
    expect(Number(m.stringLengthZeroAlloc("hello"))).toBe(5);
    expect(Number(m.stringLengthZeroAlloc(""))).toBe(0);
    expect(Number(m.stringLengthZeroAlloc("a".repeat(10_000)))).toBe(10_000);
    expect(Number(m.stringLengthZeroAlloc("héllo"))).toBe(6); // é is 2 UTF-8 bytes
  });
});
