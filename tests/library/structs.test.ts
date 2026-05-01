import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("struct in / out", () => {
  test("round-trips a Point", () => {
    expect(m.roundtripPoint({ x: 3, y: 4 })).toEqual({ x: 3, y: 4 });
  });

  test("snake_case fields exposed as camelCase", () => {
    expect(m.formatOptions({ filePath: "lib.zig", lineCount: 100 })).toBe("lib.zig:100:false");
  });

  test("default-valued field can be omitted", () => {
    expect(m.formatOptions({ filePath: "x", lineCount: 1 })).toBe("x:1:false");
  });

  test("default-valued field can be overridden", () => {
    expect(m.formatOptions({ filePath: "x", lineCount: 1, verbose: true })).toBe("x:1:true");
  });

  test("required field missing throws TypeError", () => {
    expect(() => m.formatOptions({ filePath: "x" })).toThrow(TypeError);
    expect(() => m.formatOptions({ lineCount: 1 })).toThrow(TypeError);
    expect(() => m.formatOptions({})).toThrow(TypeError);
  });

  test("nested struct", () => {
    expect(m.formatContainer({ name: "p", point: { x: 1, y: 2 } })).toBe("p@1,2");
  });
});

describe("FullStruct (mix of required, optional, default, nested)", () => {
  test("all fields present", () => {
    expect(
      m.formatFullStruct({
        name: "alice",
        age: 30,
        nickName: "ali",
        isAdmin: true,
      }),
    ).toBe("alice/30/ali/true");
  });

  test("optional ?T can be null", () => {
    expect(m.formatFullStruct({ name: "bob", age: 25, nickName: null })).toBe("bob/25/null/false");
  });

  test("optional ?T can be undefined", () => {
    expect(m.formatFullStruct({ name: "bob", age: 25, nickName: undefined })).toBe(
      "bob/25/null/false",
    );
  });

  test("optional ?T can be missing entirely", () => {
    expect(m.formatFullStruct({ name: "bob", age: 25 })).toBe("bob/25/null/false");
  });

  test("default field omitted", () => {
    expect(m.formatFullStruct({ name: "bob", age: 25, nickName: "b" })).toBe("bob/25/b/false");
  });

  test("required field missing still throws even with defaults present", () => {
    expect(() => m.formatFullStruct({ age: 25 })).toThrow(TypeError);
  });
});

describe("all-default struct", () => {
  test("accepts empty object", () => {
    expect(m.formatSettings({})).toBe("false/0");
  });

  test("accepts overrides", () => {
    expect(m.formatSettings({ debug: true, level: 3 })).toBe("true/3");
  });

  test("accepts partial override", () => {
    expect(m.formatSettings({ level: 5 })).toBe("false/5");
  });
});

describe("extra unknown JS keys are ignored", () => {
  test("unrelated property doesn't break conversion", () => {
    expect(m.formatOptions({ filePath: "x", lineCount: 1, extraJunk: 99 })).toBe("x:1:false");
  });
});
