import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

const ITERS = 100_000;

function settle() {
  Bun.gc(true);
}

describe("memory soak", () => {
  test("allocating string fn does not leak across 100k calls", () => {
    for (let i = 0; i < 1_000; i++) m.roundtripString("warmup");
    settle();

    for (let i = 0; i < ITERS; i++) m.roundtripString("x".repeat(100));
    settle();
    const afterBatch1 = process.memoryUsage().rss;

    for (let i = 0; i < ITERS; i++) m.roundtripString("x".repeat(100));
    settle();
    const afterBatch2 = process.memoryUsage().rss;

    expect(afterBatch2 - afterBatch1).toBeLessThan(20 * 1024 * 1024);
  }, 60_000);

  test("non-allocating fn (add) does not grow RSS at all", () => {
    for (let i = 0; i < 1_000; i++) m.roundtripI32(i);
    settle();
    const baseline = process.memoryUsage().rss;

    for (let i = 0; i < ITERS; i++) m.roundtripI32(i);
    settle();
    const after = process.memoryUsage().rss;

    expect(after - baseline).toBeLessThan(10 * 1024 * 1024);
  }, 60_000);

  test("struct conversion path doesn't leak", () => {
    const opts = { filePath: "x", lineCount: 1, verbose: false };
    for (let i = 0; i < 1_000; i++) m.formatOptions(opts);
    settle();
    const baseline = process.memoryUsage().rss;

    for (let i = 0; i < ITERS; i++) m.formatOptions(opts);
    settle();
    const after = process.memoryUsage().rss;

    expect(after - baseline).toBeLessThan(40 * 1024 * 1024);
  }, 60_000);
});
