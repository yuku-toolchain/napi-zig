import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

const I64_MAX = (1n << 63n) - 1n;
const I64_MIN = -(1n << 63n);
const U64_MAX = (1n << 64n) - 1n;

describe("Val.getBigIntI64", () => {
  test("fitting values are lossless", () => {
    expect(m.readBigIntI64(0n)).toEqual({ value: 0n, lossless: true });
    expect(m.readBigIntI64(42n)).toEqual({ value: 42n, lossless: true });
    expect(m.readBigIntI64(-1n)).toEqual({ value: -1n, lossless: true });
    expect(m.readBigIntI64(I64_MAX)).toEqual({ value: I64_MAX, lossless: true });
    expect(m.readBigIntI64(I64_MIN)).toEqual({ value: I64_MIN, lossless: true });
  });

  test("values larger than i64.max report lossless = false", () => {
    const r = m.readBigIntI64(I64_MAX + 1n);
    expect(r.lossless).toBe(false);
  });

  test("values smaller than i64.min report lossless = false", () => {
    const r = m.readBigIntI64(I64_MIN - 1n);
    expect(r.lossless).toBe(false);
  });
});

describe("Val.getBigIntU64", () => {
  test("fitting non-negative values are lossless", () => {
    expect(m.readBigIntU64(0n)).toEqual({ value: 0n, lossless: true });
    expect(m.readBigIntU64(42n)).toEqual({ value: 42n, lossless: true });
    expect(m.readBigIntU64(U64_MAX)).toEqual({ value: U64_MAX, lossless: true });
  });

  test("negative values report lossless = false", () => {
    const r = m.readBigIntU64(-1n);
    expect(r.lossless).toBe(false);
  });

  test("values larger than u64.max report lossless = false", () => {
    const r = m.readBigIntU64(U64_MAX + 1n);
    expect(r.lossless).toBe(false);
  });
});
