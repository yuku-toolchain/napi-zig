import { beforeEach, describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("defer inside an exported function", () => {
  test("runs in LIFO order", () => {
    expect(m.deferLifoOrder()).toBe("CBA");
  });

  beforeEach(() => m.resetDeferCounter());

  test("fires on every return path", () => {
    expect(m.deferRunsOnEveryReturnPath(0)).toBe(-1);
    expect(m.deferRunsOnEveryReturnPath(1)).toBe(1);
    expect(m.deferRunsOnEveryReturnPath(2)).toBe(99);
    expect(m.deferCounter()).toBe(3);
  });

  test("releases a long-lived smp_allocator allocation across many calls", () => {
    for (let i = 0; i < 1_000; i++) m.deferReleasesSmpAllocation(1024);
    Bun.gc(true);
    const baseline = process.memoryUsage().rss;

    for (let i = 0; i < 100_000; i++) m.deferReleasesSmpAllocation(1024);
    Bun.gc(true);
    const after = process.memoryUsage().rss;

    expect(after - baseline).toBeLessThan(20 * 1024 * 1024);
  }, 60_000);
});

describe("returning a long-lived allocation via env.toJs + defer free", () => {
  test("the returned string content matches what was written before free", () => {
    expect(m.returnSliceWithDeferredFree(5, "x".charCodeAt(0))).toBe("xxxxx");
    expect(m.returnSliceWithDeferredFree(0, "x".charCodeAt(0))).toBe("");
    expect(m.returnSliceWithDeferredFree(64, "A".charCodeAt(0))).toBe("A".repeat(64));
  });

  test("does not leak across many calls", () => {
    for (let i = 0; i < 1_000; i++) m.returnSliceWithDeferredFree(128, 0x41);
    Bun.gc(true);
    const baseline = process.memoryUsage().rss;

    for (let i = 0; i < 100_000; i++) m.returnSliceWithDeferredFree(128, 0x41);
    Bun.gc(true);
    const after = process.memoryUsage().rss;

    expect(after - baseline).toBeLessThan(20 * 1024 * 1024);
  }, 60_000);
});

describe("DebugAllocator inside an exported function", () => {
  test("alloc + free + deinit reports Check.ok", () => {
    expect(m.debugAllocatorRoundTrip(64)).toBe(0);
    expect(m.debugAllocatorRoundTrip(4096)).toBe(0);
    expect(m.debugAllocatorRoundTrip(1)).toBe(0);
  });

  test("repeated round-trips do not leak", () => {
    for (let i = 0; i < 1_000; i++) m.debugAllocatorRoundTrip(256);
    Bun.gc(true);
    const baseline = process.memoryUsage().rss;

    for (let i = 0; i < 50_000; i++) m.debugAllocatorRoundTrip(256);
    Bun.gc(true);
    const after = process.memoryUsage().rss;

    expect(after - baseline).toBeLessThan(20 * 1024 * 1024);
  }, 60_000);
});
