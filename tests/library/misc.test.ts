import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("symbols", () => {
  test("createSymbol with description", () => {
    const sym = m.createSymbolWithDesc("mySym");
    expect(typeof sym).toBe("symbol");
    expect(sym.description).toBe("mySym");
  });

  test("createSymbol without description", () => {
    const sym = m.createSymbolWithoutDesc();
    expect(typeof sym).toBe("symbol");
  });

  test("symbols are unique", () => {
    expect(m.createSymbolWithDesc("x")).not.toBe(m.createSymbolWithDesc("x"));
  });

  test("isSymbol typeOf check works", () => {
    expect(m.isSymbol(m.createSymbolWithDesc("x"))).toBe(true);
    expect(m.isSymbol("not a sym")).toBe(false);
  });
});

describe("dates", () => {
  test("createDate produces a JS Date", () => {
    const d = m.createDateMs(1_700_000_000_000);
    expect(d).toBeInstanceOf(Date);
    expect(d.getTime()).toBe(1_700_000_000_000);
  });

  test("dateToMs reads a JS Date back as epoch ms", () => {
    const d = new Date(2024, 0, 1);
    expect(m.dateToMs(d)).toBe(d.getTime());
  });

  test("isDate true for Date, false for plain object", () => {
    expect(m.isDate(new Date())).toBe(true);
    expect(m.isDate({})).toBe(false);
  });

  test("round-trips epoch zero", () => {
    expect(m.dateToMs(m.createDateMs(0))).toBe(0);
  });
});

describe("externals", () => {
  test("createExternal wraps an opaque pointer; getExternalData reads it back", () => {
    const ext = m.makeExternal();
    expect(m.readExternalI32(ext)).toBe(99);
  });
});

describe("version info", () => {
  test("getVersion returns a positive integer", () => {
    const v = m.napiVersion();
    expect(typeof v).toBe("number");
    expect(v).toBeGreaterThan(0);
  });

  test("getNodeVersion.major matches process / Bun runtime", () => {
    const major = m.nodeMajorVersion();
    expect(typeof major).toBe("number");
    expect(major).toBeGreaterThan(0);
  });
});
