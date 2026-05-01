// end-to-end verification of the showcase addon. exits non-zero on regression.

const m = require("./zig-out/lib/showcase.node");

let failed = 0;
const eq = (label: string, actual: unknown, expected: unknown): void => {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  console.log(`${ok ? "✓" : "✗"} ${label}: ${JSON.stringify(actual)}`);
  if (!ok) {
    console.log(`  expected: ${JSON.stringify(expected)}`);
    failed++;
  }
};

eq("version", m.version, "0.1.0");
eq("maxBuffer", m.maxBuffer, 1 << 20);

eq("add(2, 3)", m.add(2, 3), 5);
eq("double(2.5)", m.double(2.5), 5);

eq("greet", m.greet("world"), "Hello, world!");
eq("parse", m.parse("hi"), "HI");

eq(
  "compile",
  m.compile({ filePath: "main.zig", lineCount: 100 }),
  "main.zig: 100 lines (verbose=false)",
);
eq(
  "compile verbose",
  m.compile({ filePath: "main.zig", lineCount: 100, verbose: true }),
  "main.zig: 100 lines (verbose=true)",
);

eq("log", m.log("warning", "disk full"), "[warning] disk full");
eq("log camelCase", m.log("errorLevel", "boom"), "[error_level] boom");

eq(
  "crypto.hash",
  m.crypto.hash("hi"),
  "8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4",
);
eq(
  "crypto.verify",
  m.crypto.verify("8f434346648f6b96df89dda901c5176b10a6d83961dd3c1ac88b59b2dc327aa4", "hi"),
  true,
);

const c = new m.Counter(10);
eq("Counter init+get", c.get(), 10);
eq("Counter increment", c.increment(), 11);
eq("Counter addN", c.addN(5), 16);
c.reset();
eq("Counter reset", c.get(), 0);

eq("sum variadic", m.sum(1, 2, 3, 4, 5), 15);

const collected: [number, number][] = [];
m.forEach([10, 20, 30], (item: number, i: number) => collected.push([i, item]));
eq("forEach", collected, [
  [0, 10],
  [1, 20],
  [2, 30],
]);

const fib = await m.asyncFib(30);
eq("asyncFib(30)", fib, 832040);

if (failed > 0) {
  console.log(`\n${failed} check(s) failed`);
  process.exit(1);
}
console.log("\nall checks passed");

export {};
