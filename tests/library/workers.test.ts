import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("runWorker (background async work)", () => {
  test("resolves with a number computed on the worker thread", async () => {
    expect(await m.asyncFib(10)).toBe(55);
    expect(await m.asyncFib(20)).toBe(6765);
  });

  test("returned value is a Promise", () => {
    const p = m.asyncFib(0);
    expect(p).toBeInstanceOf(Promise);
  });

  test("void resolve becomes undefined", async () => {
    expect(await m.asyncVoid()).toBeUndefined();
  });

  test("error returned from resolve becomes a Promise rejection with the error name", async () => {
    let caught: Error | undefined;
    try {
      await m.asyncError();
    } catch (e) {
      caught = e as Error;
    }
    expect(caught).toBeInstanceOf(Error);
    expect(caught?.message).toBe("WorkerFailed");
  });

  test("can resolve with a struct (auto-converted to object)", async () => {
    expect(await m.asyncStruct()).toEqual({ x: 3, y: 4 });
  });

  test("can resolve with a Val passthrough", async () => {
    expect(await m.asyncVal()).toBe(99);
  });

  test("can resolve with a string built on the resolve thread", async () => {
    expect(await m.asyncString()).toBe("from worker");
  });
});

describe("multiple workers run concurrently", () => {
  test("Promise.all over identical inputs", async () => {
    const results = await Promise.all([m.asyncFib(15), m.asyncFib(15), m.asyncFib(15)]);
    expect(results).toEqual([610, 610, 610]);
  });

  test("Promise.all over different inputs preserves order", async () => {
    const inputs = [5, 10, 15, 20];
    const expected = [5, 55, 610, 6765];
    const results = await Promise.all(inputs.map((n) => m.asyncFib(n)));
    expect(results).toEqual(expected);
  });

  test("many workers complete without losing values", async () => {
    const N = 32;
    const results = await Promise.all(Array.from({ length: N }, (_, i) => m.asyncFib(i % 10)));
    expect(results).toHaveLength(N);
    for (const v of results) {
      expect(typeof v).toBe("number");
    }
  });
});
