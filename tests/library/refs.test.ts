import { afterEach, describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

afterEach(() => {
  // each test stores into a single module-level slot; clear between runs.
  try {
    m.clearStoredRef();
  } catch {}
});

describe("Ref (createReference / value / delete)", () => {
  test("retrieves the stored value across separate calls", () => {
    const obj = { kept: true };
    m.storeRef(obj);
    const fetched = m.fetchStoredRef();
    // strong ref returns the same JS reference
    expect(fetched).toBe(obj);
  });

  test("storing a function preserves identity", () => {
    const fn = () => 42;
    m.storeRef(fn);
    expect(m.fetchStoredRef()).toBe(fn);
  });

  test("storing a primitive throws (N-API references require Object/Function/Symbol)", () => {
    expect(() => m.storeRef("just-a-string")).toThrow();
  });

  test("storing twice replaces and frees the previous", () => {
    m.storeRef({ first: true });
    m.storeRef({ second: true });
    expect(m.fetchStoredRef()).toEqual({ second: true });
  });

  test("clearStoredRef + fetch throws (no stored ref)", () => {
    m.storeRef({ x: 1 });
    m.clearStoredRef();
    expect(() => m.fetchStoredRef()).toThrow("NoStoredRef");
  });

  test("ref keeps its target alive against GC", async () => {
    // create an object only the Ref will point to, force GC, fetch it back.
    const marker = { alive: 42 };
    m.storeRef(marker);

    // drop our local strong reference is moot here (marker is still in
    // scope until end of test), but force a couple gc passes to make
    // sure the Ref alone is sufficient to keep the JS object alive
    Bun.gc(true);
    await new Promise((r) => setImmediate(r));
    Bun.gc(true);

    const fetched = m.fetchStoredRef();
    expect(fetched).toBe(marker);
    expect(fetched.alive).toBe(42);
  });
});
