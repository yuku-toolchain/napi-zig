import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("Env.createTypedArray", () => {
  test("Uint8Array filled with a byte value", () => {
    const arr = m.makeUint8Array(8, 0x55);
    expect(arr).toBeInstanceOf(Uint8Array);
    expect(arr.length).toBe(8);
    for (const b of arr) expect(b).toBe(0x55);
  });

  test("zero-length Uint8Array", () => {
    const arr = m.makeUint8Array(0, 0);
    expect(arr).toBeInstanceOf(Uint8Array);
    expect(arr.length).toBe(0);
  });

  test("Int32Array with sequential values", () => {
    const arr = m.makeInt32Array(4);
    expect(arr).toBeInstanceOf(Int32Array);
    expect([...arr]).toEqual([0, 1, 2, 3]);
  });

  test("Float64Array with fractional values", () => {
    const arr = m.makeFloat64Array(4);
    expect(arr).toBeInstanceOf(Float64Array);
    expect([...arr]).toEqual([0, 0.5, 1.0, 1.5]);
  });

  test("BigInt64Array preserves bigint precision", () => {
    const arr = m.makeBigInt64Array(3);
    expect(arr).toBeInstanceOf(BigInt64Array);
    expect([...arr]).toEqual([0n, 1_000_000_000_000n, 2_000_000_000_000n]);
  });

  test("isTypedArray distinguishes typed arrays from plain arrays", () => {
    expect(m.isTypedArray(m.makeUint8Array(2, 0))).toBe(true);
    expect(m.isTypedArray(new Int32Array(4))).toBe(true);
    expect(m.isTypedArray([1, 2, 3])).toBe(false);
    expect(m.isTypedArray(Buffer.alloc(4))).toBe(true);
    expect(m.isTypedArray(new ArrayBuffer(4))).toBe(false);
  });

  test("typed arrays share their underlying ArrayBuffer", () => {
    const arr = m.makeUint8Array(4, 1);
    expect(arr.buffer).toBeInstanceOf(ArrayBuffer);
    expect(arr.buffer.byteLength).toBe(4);
  });
});
