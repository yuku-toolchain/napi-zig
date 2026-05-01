import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("enums", () => {
  test("camelCase tag round-trip", () => {
    expect(m.roundtripLevel("debug")).toBe("debug");
    expect(m.roundtripLevel("info")).toBe("info");
    expect(m.roundtripLevel("warning")).toBe("warning");
  });

  test("snake_case tag exposed as camelCase on output", () => {
    expect(m.roundtripLevel("errorLevel")).toBe("errorLevel");
  });

  test("snake_case tag also accepted as input", () => {
    expect(m.roundtripLevel("error_level")).toBe("errorLevel");
  });

  test("Zig @tagName returns the snake_case form", () => {
    // verifies that even though JS sees camelCase, the underlying Zig enum
    // is the snake_case variant — i.e. fromJs hits the right tag.
    expect(m.levelTagName("errorLevel")).toBe("error_level");
    expect(m.levelTagName("info")).toBe("info");
  });

  test("invalid value throws TypeError naming the bad string", () => {
    let caught: Error | undefined;
    try {
      m.roundtripLevel("invalid");
    } catch (e) {
      caught = e as Error;
    }
    expect(caught).toBeInstanceOf(TypeError);
    expect(caught?.message).toContain("invalid");
    expect(caught?.message).toContain("Level");
  });

  test("non-string throws TypeError", () => {
    expect(() => m.roundtripLevel(0)).toThrow(TypeError);
    expect(() => m.roundtripLevel(null)).toThrow(TypeError);
  });
});
