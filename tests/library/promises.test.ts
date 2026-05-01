import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("synchronous promises (createPromise + Deferred)", () => {
  test("resolves to the given value", async () => {
    await expect(m.resolveImmediately(42)).resolves.toBe(42);
  });

  test("rejects with an Error of the given message", async () => {
    await expect(m.rejectImmediately("boom")).rejects.toThrow("boom");
  });

  test("returned value is a real Promise", () => {
    const p = m.resolveImmediately(1);
    expect(p).toBeInstanceOf(Promise);
  });

  test("isPromise typeguard", () => {
    expect(m.isPromise(Promise.resolve(1))).toBe(true);
    expect(m.isPromise({})).toBe(false);
    expect(m.isPromise(null)).toBe(false);
  });
});
