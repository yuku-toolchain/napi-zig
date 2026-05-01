import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("ThreadsafeFn(void) — signal-only callbacks", () => {
  test("call from the same thread fires the callback once", async () => {
    let count = 0;
    const done = new Promise<void>((resolve) => {
      m.signalOnce(() => {
        count++;
        resolve();
      });
    });
    await done;
    expect(count).toBe(1);
  });

  test("call from a spawned Zig thread fires the callback", async () => {
    let count = 0;
    const done = new Promise<void>((resolve) => {
      m.signalOnceFromThread(() => {
        count++;
        resolve();
      });
    });
    await done;
    expect(count).toBe(1);
  });
});

describe("ThreadsafeFn(T) — payload callbacks across many threads", () => {
  test("each spawned thread delivers its id; all are received exactly once", async () => {
    const N = 8;
    const seen = new Set<number>();
    const done = new Promise<void>((resolve) => {
      let count = 0;
      m.fanOutWorkers((id: number) => {
        seen.add(id);
        count++;
        if (count === N) resolve();
      }, N);
    });
    await done;
    expect(seen.size).toBe(N);
    for (let i = 0; i < N; i++) {
      expect(seen.has(i)).toBe(true);
    }
  });

  test("scales to many threads without dropping calls", async () => {
    const N = 64;
    let count = 0;
    const done = new Promise<void>((resolve) => {
      m.fanOutWorkers(() => {
        count++;
        if (count === N) resolve();
      }, N);
    });
    await done;
    expect(count).toBe(N);
  });
});
