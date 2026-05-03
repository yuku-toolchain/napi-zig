# Publishing to npm

Once you have run `napi build --release` and inspected the generated structure, the rest of the pipeline is one CLI command per release.

## First-time setup

`napi npm-init` publishes initial `0.0.0` versions of every package and sets each one up for [npm trusted publishing](https://docs.npmjs.com/trusted-publishers) (OIDC). After this, your CI does not need an `NPM_TOKEN`.

```sh
npm login
napi npm-init --repo myorg/myrepo --workflow publish.yml
```

`--repo` is `owner/name` of your GitHub repository. `--workflow` is the workflow filename in `.github/workflows/`. Both of these are stamped into the npm package's trusted-publisher record so npm knows which workflow is allowed to publish.

You only run this once per package. The CI pipeline takes over from here.

## Bump and tag

`napi bump` updates **every** `package.json` (the main package and every per-platform binding), creates an annotated git tag, and pushes branch + tag in one round-trip.

```sh
napi bump          # interactive picker
napi bump patch    # explicit
napi bump 1.2.3    # exact version
```

The push triggers your CI workflow on the new tag, which runs `napi publish`.

## CI publish workflow

This is the workflow `napi new` writes for you. With trusted publishing configured, no secrets are needed.

```yaml
# .github/workflows/publish.yml
name: Publish
on:
  push:
    tags: ["v*"]

permissions:
  contents: read
  id-token: write

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: mlugg/setup-zig@v2
        with: { version: master }
      - uses: actions/setup-node@v4
        with:
          node-version: 24
          registry-url: https://registry.npmjs.org
      - run: npm install
      - run: npx napi-zig build --release
      - run: npx napi-zig publish
```

`id-token: write` is what enables OIDC. The workflow runs on a single `ubuntu-latest` runner because Zig cross-compiles every target from one host; you do not need a matrix.

## What `napi publish` does

For each package in `npm/`:

1. Reads its `package.json`.
2. Runs `npm publish --access public`.
3. Attaches a [provenance attestation](https://docs.npmjs.com/generating-provenance-statements) (auto in CI).

The main package (`my-addon`) is published last, after every `binding-*` package, so users who install it during the small window between publishes always get a working set.

## Provenance

In CI, provenance is on by default. Override:

```sh
napi publish --no-provenance   # opt out
napi publish --provenance      # force on (rarely needed, default in CI)
```

Provenance proves the package was built from a specific commit on a specific workflow. It shows up in the npm registry as a verified badge.

## What users see

```sh
npm install my-addon
```

```js
import addon from "my-addon";
addon.add(2, 3);
```

There is no `postinstall` hook, no native build step on the user's machine, no `nan` or `node-gyp`. npm picks the right binding via `optionalDependencies` and the platform fields, and the user gets a single fast install.
