# tests/

Two suites:

- `zig build test`: comptime + unit tests in `src/`. plain zig, no js runtime. fast, runs first in ci.
- `bun test`: integration tests that load the fixture addons and exercise the live n-api surface. plus the cli tests in `tests/cli/`.

Plus standalone scripts that live outside the bun runner:

- `tests/smoke.mjs`: abi smoke under node or deno. run with `node` or `deno run --allow-all`.
- `tests/installed-smoke.mjs`: verifies a cross-compiled package laid out the way `npm install` would lay it out. takes the package dir as argv[2].

## Layout

```
tests/
  fixture-lib/        napi-zig consumer used by every library test
    build.zig         builds zig-out/lib/fixture.{node,d.ts}
    src/lib.zig       the test surface
  fixture-cli/        smaller consumer used by the cli build tests
    build.zig         has .npm config so `napi build --release` produces a full scaffold
    src/lib.zig       one fn (add)
  helpers/
    addon.ts          loadFixture, builds fixture-lib once, returns the addon
    cli-fixture.ts    stageCliFixture, copies fixture-cli into a tempdir
    fs.ts             tempDir, rmTemp, writeJsonTree, sha256
    withCwd.ts        scoped chdir
  library/            bun integration tests for the library surface
  cli/                cli tests (discover, build-dev, build-release)
  dts/                type-level check on the generated .d.ts
    usage.ts          imports types and exercises them
    tsconfig.json     strict ts config consumed by tsgo
  smoke.mjs           node/deno abi smoke
  installed-smoke.mjs cross-install smoke
```

## Running locally

```sh
zig build test          # comptime
bun test                # everything under tests/library + tests/cli
bun run type-check      # cli/ + tests/dts/usage.ts
node tests/smoke.mjs    # representative slice under host node
```

`bun test` builds `fixture-lib` on demand via `loadFixture()`. first run on a clean tree takes a few extra seconds. subsequent runs reuse zig's cache.

## Adding a test

For a new conversion path or runtime feature:

1. add the surface to `tests/fixture-lib/src/lib.zig`.
2. write a `*.test.ts` in `tests/library/` and call into the fixture via `loadFixture()`.
3. if the change widens the public type surface, the auto-generated `.d.ts` will pick it up. add a content check to `tests/library/dts.test.ts` if the shape is non-obvious.

For a new CLI command or flag:

1. add unit tests against the pure functions in `cli/src/` under `tests/cli/`.
2. if the flow needs a real `zig build`, copy the pattern in `build-dev.test.ts`. stage fixture-cli into a tempdir, use `withCwd`, run the cli fn directly.

## CI notes

`.github/workflows/ci.yml` runs four phases:

- `test`: lint, type-check, comptime, integration, build (bun)
- `*-abi`: runtime smoke per os, runtime, node version
- `cross-compile + cross-install`: what users get from `npm install`
- `done`: single aggregator job, require this one in branch protection

Repeated zig setup is factored into `.github/actions/setup-zig`.
