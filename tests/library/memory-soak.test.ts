// Memory soak. Calls allocating fns many times in two batches and checks
// RSS doesn't grow unboundedly between batches. Catches leaks where the
// per-call arena fails to release pages back to smp_allocator's pool.
//
// Two-batch pattern instead of absolute threshold: the first batch warms
// up the allocator's freelist, the second batch should plateau. A stable
// delta between batches is the strong signal; an absolute number isn't,
// because RSS is noisy and includes V8 / runtime growth unrelated to us.

import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

const ITERS = 100_000;

function settle() {
  Bun.gc(true);
}

describe("memory soak", () => {
  test(
    "allocating string fn does not leak across 100k calls",
    () => {
      // warm up
      for (let i = 0; i < 1_000; i++) m.roundtripString("warmup");
      settle();
      const baseline = process.memoryUsage().rss;

      for (let i = 0; i < ITERS; i++) m.roundtripString("x".repeat(100));
      settle();
      const afterBatch1 = process.memoryUsage().rss;

      for (let i = 0; i < ITERS; i++) m.roundtripString("x".repeat(100));
      settle();
      const afterBatch2 = process.memoryUsage().rss;

      const batch1Growth = afterBatch1 - baseline;
      const batch2Growth = afterBatch2 - afterBatch1;
      const ratio = batch1Growth === 0 ? 0 : batch2Growth / batch1Growth;

      // batch 2 should be much smaller than batch 1 (warm-up pays the
      // first-allocation cost; steady-state should plateau). allow some
      // slack — RSS is noisy. failure here = real linear growth.
      expect(batch2Growth).toBeLessThan(20 * 1024 * 1024); // <20MiB drift
      expect(ratio).toBeLessThan(0.5); // batch 2 < half of batch 1
    },
    60_000,
  );

  test(
    "non-allocating fn (add) does not grow RSS at all",
    () => {
      for (let i = 0; i < 1_000; i++) m.roundtripI32(i);
      settle();
      const baseline = process.memoryUsage().rss;

      for (let i = 0; i < ITERS; i++) m.roundtripI32(i);
      settle();
      const after = process.memoryUsage().rss;

      // README claims `add(i32, i32)`-like calls "never go near the
      // allocator." that should hold here too.
      expect(after - baseline).toBeLessThan(10 * 1024 * 1024); // <10MiB
    },
    60_000,
  );

  test(
    "struct conversion path doesn't leak",
    () => {
      const opts = { filePath: "x", lineCount: 1, verbose: false };
      for (let i = 0; i < 1_000; i++) m.formatOptions(opts);
      settle();
      const baseline = process.memoryUsage().rss;

      for (let i = 0; i < ITERS; i++) m.formatOptions(opts);
      settle();
      const after = process.memoryUsage().rss;

      expect(after - baseline).toBeLessThan(40 * 1024 * 1024);
    },
    60_000,
  );
});
