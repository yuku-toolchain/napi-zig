import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("Range (zig-style iterator class)", () => {
  test("works with for..of", () => {
    const out: number[] = [];
    for (const n of new m.Range(4)) out.push(n);
    expect(out).toEqual([0, 1, 2, 3]);
  });

  test("works with spread", () => {
    expect([...new m.Range(3)]).toEqual([0, 1, 2]);
  });

  test("works with Array.from", () => {
    expect(Array.from(new m.Range(2))).toEqual([0, 1]);
  });

  test("empty iterator yields nothing", () => {
    expect([...new m.Range(0)]).toEqual([]);
  });

  test("native next() stays exposed and returns Item | null", () => {
    const r = new m.Range(1);
    expect(r.next()).toBe(0);
    expect(r.next()).toBeNull();
  });

  test("iteration state lives in the instance (zig semantics)", () => {
    const r = new m.Range(4);
    const first: number[] = [];
    for (const n of r) {
      first.push(n);
      if (n === 1) break;
    }
    expect(first).toEqual([0, 1]);
    // a second loop continues, it does not restart
    expect([...r]).toEqual([2, 3]);
  });

  test("the returned iterator is itself iterable", () => {
    const iter = new m.Range(3)[Symbol.iterator]();
    expect([...iter]).toEqual([0, 1, 2]);
  });

  test("iterator protocol shape: {value, done}", () => {
    const iter = new m.Range(1)[Symbol.iterator]();
    expect(iter.next()).toEqual({ value: 0, done: false });
    expect(iter.next()).toEqual({ done: true });
  });
});

describe("Words (next takes Env, returns error union)", () => {
  test("works with for..of", () => {
    const out: string[] = [];
    for (const w of new m.Words("hello brave new world")) out.push(w);
    expect(out).toEqual(["hello", "brave", "new", "world"]);
  });

  test("works with spread", () => {
    expect([...new m.Words("a b c")]).toEqual(["a", "b", "c"]);
  });
});

describe("non-iterator classes are unaffected", () => {
  test("Counter has no Symbol.iterator", () => {
    const c = new m.Counter(0);
    expect((c as any)[Symbol.iterator]).toBeUndefined();
  });
});
