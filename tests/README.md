# tests/

Two suites:

- **`zig build test`** — comptime + unit tests in `src/`. Plain Zig, no JS runtime. Fast, runs first in CI.
- **`bun test`** — integration tests that load the fixture addons and exercise the live N-API surface. Plus the CLI tests in `tests/cli/`.

Plus standalone scripts that live outside the bun runner:

- **`tests/smoke.mjs`** — ABI smoke under Node or Deno. Run with `node` or `deno run --allow-all`.
- **`tests/installed-smoke.mjs`** — verifies a cross-compiled package laid out the way `npm install` would lay it out. Takes the package dir as argv[2].

## Layout

```
tests/
  fixture-lib/        # napi-zig consumer used by every library test
    build.zig         # builds zig-out/lib/fixture.{node,d.ts}
    src/lib.zig       # the test surface (every conversion path, classes, async, ...)
  fixture-cli/        # smaller consumer used by the CLI build tests
    build.zig         # has .npm config so `napi build --release` produces a full scaffold
    src/lib.zig       # one fn (add)
  helpers/
    addon.ts          # loadFixture(): build fixture-lib once, return the addon
    cli-fixture.ts    # stageCliFixture(): copy fixture-cli into a tempdir
    fs.ts             # tempDir, rmTemp, writeJsonTree, sha256
    withCwd.ts        # scoped chdir
  library/            # bun integration tests for the library surface
    primitives.test.ts, strings.test.ts, structs.test.ts, ...
    classes.test.ts (incl. GC observation via Bun.gc(true))
    workers.test.ts, threadsafe.test.ts, promises.test.ts
    dts.test.ts (snapshot-style checks of the auto-generated .d.ts)
    memory-soak.test.ts (RSS plateau check across 100k iterations)
    edge-shapes.test.ts (slice-of-string, nested optionals, callback in struct, ...)
  cli/                # CLI tests
    discover.test.ts       (pure unit: discoverPackages + updateVersions)
    build-dev.test.ts      (`napi build` flow against a staged fixture)
    build-release.test.ts  (`napi build --release` + idempotency)
  dts/                # type-level check on the generated .d.ts
    usage.ts          # imports types and exercises them
    tsconfig.json     # strict TS config consumed by tsgo
  smoke.mjs           # node/deno ABI smoke
  installed-smoke.mjs # cross-install smoke
```

## Running locally

```sh
zig build test          # comptime
bun test                # everything under tests/library + tests/cli
bun run type-check      # cli/ + tests/dts/usage.ts
node tests/smoke.mjs    # representative slice under host node
```

`bun test` builds `fixture-lib` on demand via `loadFixture()`. First run on a clean tree takes a few extra seconds; subsequent runs use Zig's cache.

## Adding a test

For a new conversion path or runtime feature:

1. Add the surface to `tests/fixture-lib/src/lib.zig`.
2. Write a `*.test.ts` in `tests/library/` and call into the fixture via `loadFixture()`.
3. If the change widens the public type surface, the auto-generated `.d.ts` will pick it up automatically; add a content check to `tests/library/dts.test.ts` if the shape is non-obvious.

For a new CLI command or flag:

1. Add unit tests against the pure functions in `cli/src/` under `tests/cli/`.
2. If the flow needs a real `zig build`, copy the pattern in `build-dev.test.ts` (stage fixture-cli into a tempdir, `withCwd`, run the CLI fn directly).

## CI notes

`.github/workflows/ci.yml` runs four phases:

- **test** — lint, type-check, comptime, integration, build (bun)
- **\*-abi** — runtime smoke per OS / runtime / Node version
- **cross-compile + cross-install** — what users actually get from `npm install`
- **done** — single aggregator job; require this one in branch protection

Repeated Zig setup is factored into `.github/actions/setup-zig`.
