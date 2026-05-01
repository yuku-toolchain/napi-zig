import { beforeEach, describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("Counter (basic class)", () => {
  test("constructor stores initial value", () => {
    const c = new m.Counter(10);
    expect(c.get()).toBe(10);
  });

  test("methods mutate instance state", () => {
    const c = new m.Counter(0);
    expect(c.increment()).toBe(1);
    expect(c.increment()).toBe(2);
    expect(c.get()).toBe(2);
  });

  test("multiple instances have independent state", () => {
    const a = new m.Counter(5);
    const b = new m.Counter(100);
    a.increment();
    expect(a.get()).toBe(6);
    expect(b.get()).toBe(100);
  });

  test("snake_case method exposed as camelCase", () => {
    const c = new m.Counter(0);
    expect(c.addN(7)).toBe(7);
    expect(c.addN(3)).toBe(10);
    expect((c as any).add_n).toBeUndefined();
  });

  test("*const Self method", () => {
    const c = new m.Counter(42);
    expect(c.get()).toBe(42);
  });

  test("void-return method", () => {
    const c = new m.Counter(99);
    c.reset();
    expect(c.get()).toBe(0);
  });
});

describe("Greeter (init takes Env, methods take Env)", () => {
  test("constructor stores Env-allocated state", () => {
    const g = new m.Greeter("world");
    expect(g.greet()).toBe("Hello, world!");
  });

  test("multiple Greeters keep independent names", () => {
    const a = new m.Greeter("alice");
    const b = new m.Greeter("bob");
    expect(a.greet()).toBe("Hello, alice!");
    expect(b.greet()).toBe("Hello, bob!");
  });
});

describe("Plain (no deinit)", () => {
  test("class without deinit still works", () => {
    const p = new m.Plain(7);
    expect(p.get()).toBe(7);
  });
});

describe("Validating (init returns !T)", () => {
  test("happy path constructs", () => {
    const v = new m.Validating(5);
    expect(v.get()).toBe(5);
  });

  test("init error propagates as a thrown Error", () => {
    expect(() => new m.Validating(-1)).toThrow("NegativeNotAllowed");
  });
});

describe("constructor type errors", () => {
  test("wrong-arg-type throws TypeError", () => {
    expect(() => new m.Counter("nope")).toThrow(TypeError);
  });
});

describe("deinit fires on garbage collection", () => {
  beforeEach(async () => {
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    m.resetDeinitCount();
  });

  test("deinit runs once when an instance is collected", async () => {
    {
      const c = new m.Counter(0);
      c.increment();
    }
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    expect(m.deinitCount()).toBe(1);
  });

  test("deinit runs once per instance", async () => {
    {
      new m.Counter(0);
      new m.Counter(0);
      new m.Counter(0);
    }
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    expect(m.deinitCount()).toBe(3);
  });

  test("class without deinit doesn't increment the counter", async () => {
    {
      const p = new m.Plain(1);
      void p.get();
    }
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    expect(m.deinitCount()).toBe(0);
  });
});
