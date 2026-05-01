# example

A kitchen-sink napi-zig addon exercising every major capability:

- plain functions and env-injected functions
- struct args with defaults, enum args
- nested namespaces (`crypto.*`)
- classes (`Counter`)
- workers / Promises (`asyncFib`)
- raw mode for variadic args (`sum`)
- callbacks (`forEach`)

## Build and verify

From the repo root:

```sh
bun run test:example
```

Or by hand from this directory:

```sh
zig build
bun verify.ts
```

The auto-generated `showcase.d.ts` is dropped next to the `.node` binary in `zig-out/lib/`.
