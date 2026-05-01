import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("synchronous promises (createPromise + Deferred)", () => {
  test("resolves to the given value", async () => {
    expect(m.resolveImmediately(42)).resolves.toBe(42);
  });

  test("rejects with an Error of the given message", async () => {
    expect(m.rejectImmediately("boom")).rejects.toThrow("boom");
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

// Note: testing "Deferred is single-use" (a second resolve/reject on an
// already-consumed deferred) was attempted but removed — Bun 1.3 segfaults
// on the second napi_resolve_deferred call, where Node correctly returns
// an error status. The behavior is N-API-impl-specific and not safely
// observable from JS without crashing some runtimes.
