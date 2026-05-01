// type-level smoke test. consumes the auto-generated .d.ts under strict
// tsgo and exercises a representative slice. run via:
//   tsgo --noEmit -p tests/dts

import type * as fx from "../fixture-lib/zig-out/lib/fixture";

declare const m: typeof fx;

// primitives
const _b: boolean = m.roundtripBool(true);
const _i: number = m.roundtripI32(42);
const _l: bigint = m.roundtripI64(123n);
const _s: string = m.roundtripString("hi");

// optional
const _o1: number | null = m.roundtripOptionalI32(null);
const _o2: number | null = m.roundtripOptionalI32();

// struct
const _opt: string = m.formatOptions({
  filePath: "x",
  lineCount: 1,
});
const _opt2: string = m.formatOptions({
  filePath: "x",
  lineCount: 1,
  verbose: true,
});

// enum union
type Level = Parameters<typeof m.roundtripLevel>[0];
const _lvl1: Level = "debug";
const _lvl2: Level = "errorLevel";

// class
const c = new m.Counter(0);
const _ci: number = c.increment();
const _ca: number = c.addN(5);

// namespace
const _sq: number = m.math.square(3);
const _deepest: number = m.math.inner.deeper.deepest(7);

// constants
const _v: string = m.stringValue;
const _max: number = m.u32Max;

void _b;
void _i;
void _l;
void _s;
void _o1;
void _o2;
void _opt;
void _opt2;
void _lvl1;
void _lvl2;
void _ci;
void _ca;
void _sq;
void _deepest;
void _v;
void _max;
