import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("struct with custom toJs / fromJs", () => {
  test("toJs replaces field-by-field with the user method (returns string)", () => {
    expect(m.roundtripCustomPoint("3,4")).toBe("3,4");
  });

  test("fromJs parses the input via the user method", () => {
    expect(m.roundtripCustomPoint("100,-7")).toBe("100,-7");
  });

  test("user fromJs can fail", () => {
    expect(() => m.roundtripCustomPoint("nodelimiter")).toThrow();
  });
});

describe("union with custom toJs / fromJs", () => {
  test("rgb variant returns an object", () => {
    expect(m.rgbColor()).toEqual({ r: 255, g: 128, b: 0 });
  });

  test("hex variant returns a string", () => {
    expect(m.hexColor()).toBe("ff8000");
  });

  test("dispatching on input shape: object → rgb", () => {
    expect(m.colorBrightness({ r: 1, g: 2, b: 3 })).toBe(6);
    expect(m.colorBrightness({ r: 255, g: 255, b: 255 })).toBe(255 * 3);
  });

  test("dispatching on input shape: string → hex", () => {
    expect(m.colorBrightness("ff8000")).toBe(6);
    expect(m.colorBrightness("000")).toBe(3);
  });
});
