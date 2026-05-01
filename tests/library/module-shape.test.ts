import { describe, expect, test } from "bun:test";
import { loadFixture } from "../helpers/addon";

const m = loadFixture();

describe("registerInto: underscore-prefixed exports are not registered", () => {
  test("`pub fn _hidden_fn` is callable from Zig but not exposed to JS", () => {
    // sanity: the wrapper that internally calls _hidden_fn returns its value
    expect(m.usesHidden()).toBe(777);

    // _hidden_fn (snake → camel = _HiddenFn / hiddenFn) is not exposed
    expect((m as any)._hidden_fn).toBeUndefined();
    expect((m as any)._HiddenFn).toBeUndefined();
    expect((m as any).hiddenFn).toBeUndefined();
  });

  test("module-level non-pub state (probes, refs) is invisible to JS", () => {
    // _stored_ref, _deinit_counter, _external_buf, _external_finalize_count,
    // _external_value all live at module scope. they're never exposed.
    expect((m as any)._storedRef).toBeUndefined();
    expect((m as any)._deinitCounter).toBeUndefined();
    expect((m as any)._externalValue).toBeUndefined();
  });
});

describe("empty struct {} round-trips both directions", () => {
  test("Zig fn taking an empty struct accepts {}", () => {
    expect(m.acceptEmpty({})).toBe(99);
  });

  test("Zig fn returning an empty struct produces {}", () => {
    expect(m.returnsEmptyStruct()).toEqual({});
  });
});
