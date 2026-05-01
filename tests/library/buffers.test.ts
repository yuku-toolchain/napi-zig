import { beforeEach, describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("Buffer (Node.js Buffer)", () => {
  test("createBuffer fills bytes that JS can read", () => {
    const buf = m.createFilledBuffer(8, 0xab);
    expect(Buffer.isBuffer(buf)).toBe(true);
    expect(buf.length).toBe(8);
    for (let i = 0; i < 8; i++) {
      expect(buf[i]).toBe(0xab);
    }
  });

  test("zero-length buffer", () => {
    const buf = m.createFilledBuffer(0, 0);
    expect(Buffer.isBuffer(buf)).toBe(true);
    expect(buf.length).toBe(0);
  });

  test("Zig reads JS-allocated Buffer bytes", () => {
    const buf = Buffer.from([1, 2, 3, 4, 5]);
    expect(m.bufferSum(buf)).toBe(15);
  });

  test("Zig writes into JS-allocated Buffer", () => {
    const buf = Buffer.alloc(4);
    expect(m.writeIntoBuffer(buf, 0xcc)).toBe(4);
    expect([...buf]).toEqual([0xcc, 0xcc, 0xcc, 0xcc]);
  });

  test("isBuffer true for Buffer, false for ArrayBuffer", () => {
    expect(m.isBuffer(Buffer.alloc(4))).toBe(true);
    expect(m.isBuffer(new ArrayBuffer(4))).toBe(false);
  });
});

describe("ArrayBuffer", () => {
  test("createArrayBuffer fills bytes JS can read via Uint8Array view", () => {
    const ab = m.createFilledArrayBuffer(8, 0x42);
    expect(ab).toBeInstanceOf(ArrayBuffer);
    expect(ab.byteLength).toBe(8);
    const view = new Uint8Array(ab);
    for (let i = 0; i < 8; i++) {
      expect(view[i]).toBe(0x42);
    }
  });

  test("zero-length ArrayBuffer", () => {
    const ab = m.createFilledArrayBuffer(0, 0);
    expect(ab).toBeInstanceOf(ArrayBuffer);
    expect(ab.byteLength).toBe(0);
  });

  test("Zig reads JS-created ArrayBuffer bytes", () => {
    const ab = new ArrayBuffer(3);
    new Uint8Array(ab).set([10, 20, 30]);
    expect(m.arrayBufferSum(ab)).toBe(60);
  });

  test("isArrayBuffer true for ArrayBuffer, false for Buffer", () => {
    expect(m.isArrayBuffer(new ArrayBuffer(4))).toBe(true);
    expect(m.isArrayBuffer(Buffer.alloc(4))).toBe(false);
  });
});

describe("external ArrayBuffer with finalize", () => {
  beforeEach(() => {
    m.resetExternalFinalizeCount();
  });

  test("external ArrayBuffer is readable by JS", () => {
    const ab = m.createExternalArrayBuffer(0x55);
    expect(ab.byteLength).toBe(16);
    const view = new Uint8Array(ab);
    for (let i = 0; i < 16; i++) {
      expect(view[i]).toBe(0x55);
    }
  });

  test("finalize callback fires on GC", async () => {
    {
      const ab = m.createExternalArrayBuffer(0x11);
      void ab;
    }
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    expect(m.externalFinalizeCount()).toBeGreaterThanOrEqual(1);
  });
});
