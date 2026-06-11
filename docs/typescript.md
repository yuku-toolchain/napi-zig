# TypeScript declarations

The build can ship a `.d.ts` next to your `.node` binary so JavaScript users get full IntelliSense and type checking. There are three modes, controlled by the `.dts` field of `.npm`:

```zig
.npm = .{
    .scope = "@myscope",
    .dts = .{ .file = b.path("src/index.d.ts") },
},
```

| Mode                | Behavior                                             |
| ------------------- | ---------------------------------------------------- |
| `.{ .file = path }` | Copy a hand-written `.d.ts` into the package.        |
| `.auto`             | Generate a `.d.ts` from your Zig source at comptime. |
| `.none` (default)   | No declarations emitted.                             |

## Hand-written (`.file`)

**Recommended for libraries published to npm.** A hand-written `.d.ts` gives you the full TypeScript surface: overloads, conditional types, branded types, JSDoc comments, and the freedom to keep your public API stable independent of internal Zig refactors.

```zig
.dts = .{ .file = b.path("src/index.d.ts") },
```

```ts
// src/index.d.ts
declare const addon: {
  add(a: number, b: number): number;
  greet(name: string): string;
  parse<T = unknown>(input: string): T;
};

export default addon;
```

The build copies this file as-is to `index.d.ts` next to the `.node` binary, and into the published npm package. You write what your users should see; the bridge does not interfere.

## Auto-generated (`.auto`)

```zig
.dts = .auto,
```

The build runs a comptime walk of your module and emits a `.d.ts` from the Zig signatures. Useful for prototypes, internal addons, or as a **starting point** that you check into `src/index.d.ts` and then edit.

What you get:

- Every `pub fn` becomes a method.
- Every `pub const` (with a JS-mappable value) becomes a typed property.
- Nested namespaces become nested objects.
- Argument and return types come from the Zig signatures.
- Errors, optionals, enums, and structs are translated.

What is intentionally `unknown`:

- `napi.Val` becomes `unknown`. There is no JS type to infer from a passthrough.
- `napi.Callback` becomes `(...args: unknown[]) => unknown`.

These are escape hatches by design. Tighten the Zig signature and the generated type tightens with it. For example, `[]f64` generates `number[]` instead of `unknown[]`.

::: tip
A common workflow: start with `.auto`, run `napi-zig build`, copy the generated file out of `zig-out/lib/<name>.d.ts` into `src/index.d.ts`, edit it to taste, and switch the build to `.{ .file = ... }`.
:::

## None (`.none`)

```zig
.dts = .none,
```

No `.d.ts` is emitted. JavaScript users get no autocomplete or type checking for the addon. This is the default.

## Rule of thumb

If your addon will be installed by other people, hand-write your `.d.ts`. If it is internal, `.auto` is fine.

## Calling the generator yourself

The generator is also exposed as a public API: `napi.dts.generate(Module)` returns the comptime `.d.ts` string for `Module`. The build option `.auto` uses this internally; you do not normally call it directly.
