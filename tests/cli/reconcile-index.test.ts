// reconcileIndex decides what happens to a package's index.js on each release build: seeded
// when missing, replaced only when it is exactly a seed from before load(), and otherwise kept,
// with a note when it still imports binding.js's old default export.

import { describe, expect, test } from "bun:test";
import { reconcileIndex } from "../../cli/src/build";

const seed =
  "import { load } from './binding.js';\n\nconst binding = load();\nexport const { add } = binding;\nexport default binding;\n";

describe("reconcileIndex", () => {
  test("seeds a missing index.js", () => {
    expect(reconcileIndex(null, seed)).toEqual({ content: seed, note: null });
  });

  test("replaces a seed from before load()", () => {
    const legacy =
      "import binding from './binding.js';\nexport const { add } = binding;\nexport default binding;\n";
    expect(reconcileIndex(legacy, seed)).toEqual({ content: seed, note: null });
  });

  test("replaces an export-less seed from before load()", () => {
    const legacy = "import binding from './binding.js';\nexport default binding;\n";
    expect(reconcileIndex(legacy, seed)).toEqual({ content: seed, note: null });
  });

  test("keeps an edited index.js that still uses the default export, with a note", () => {
    const edited =
      "import binding from './binding.js';\nexport default { ...binding, extra: 1 };\n";
    const update = reconcileIndex(edited, seed);
    expect(update.content).toBeNull();
    expect(update.note).toContain("load()");
  });

  test("keeps an index.js that already uses load() without a note", () => {
    const edited =
      "import { load } from './binding.js';\nexport default { ...load(), extra: 1 };\n";
    expect(reconcileIndex(edited, seed)).toEqual({ content: null, note: null });
  });
});
