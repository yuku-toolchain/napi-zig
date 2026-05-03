# CLI

The `napi` CLI is the dev-time and release-time tool for napi-zig projects. It is installed as a dev dependency by `npx napi-zig new` (or your manual `npm install -D napi-zig`) and invoked through `npx napi` or your package.json scripts.

## Commands

| Command                                         | Description                                     |
| ----------------------------------------------- | ----------------------------------------------- |
| `napi new [name]`                               | Scaffold a new project (prompts for missing).   |
| `napi build`                                    | Build for the current platform.                 |
| `napi build --release`                          | Cross-compile every platform.                   |
| `napi bump [version]`                           | Bump version, commit, tag, push.                |
| `napi publish`                                  | Publish all packages to npm (CI).               |
| `napi npm-init --repo <repo> --workflow <file>` | Initial publish + configure trusted publishing. |

## `napi new`

```sh
napi new [name] [--pm <pm>]
```

Scaffolds a new napi-zig project. Prompts interactively for anything not provided.

| Option      | Default     | Description                         |
| ----------- | ----------- | ----------------------------------- |
| `[name]`    | interactive | Project name (also the addon name). |
| `--pm <pm>` | detected    | `npm`, `yarn`, `pnpm`, or `bun`.    |

What it writes:

- `build.zig`, `build.zig.zon`
- `package.json`
- `src/lib.zig` (starter with two example functions)
- `test.mjs`
- `.github/workflows/publish.yml`
- A `.gitignore` and a `README.md`

After scaffolding, it runs `npm install` (or your detected PM), `zig fetch` for the napi-zig dependency, and an initial `napi build` so the binary is available immediately.

## `napi build`

```sh
napi build [--release]
```

Without `--release`, builds for the current platform in the optimization mode set by your `build.zig` (defaults to `Debug`). Produces:

```
zig-out/lib/
├── my-addon.node
└── my-addon.d.ts        (if .dts is set)
```

The CLI also drops a top-level `my-addon.js` re-exporter so the import path matches what users will see after publish.

With `--release`, cross-compiles every platform listed in `.npm.platforms` and lays out the full `npm/` package tree. See [Cross-compiling](/cross-compiling).

## `napi bump`

```sh
napi bump [version] [options]
```

Bumps the version in **every** `package.json` (main + per-platform bindings), creates an annotated tag, and pushes branch + tag.

| Option           | Default     | Description                                        |
| ---------------- | ----------- | -------------------------------------------------- |
| `[version]`      | interactive | `patch`, `minor`, `major`, or an exact version.    |
| `--preid <id>`   | `beta`      | Pre-release identifier (for `prepatch`, etc.).     |
| `--commit <msg>` | `%s`        | Commit message; `%s` is replaced with the version. |
| `--no-tag`       |             | Skip git tag.                                      |
| `--no-push`      |             | Skip git push.                                     |

The push triggers your tag-based CI workflow.

## `napi publish`

```sh
napi publish [options]
```

For each package in `npm/`, runs `npm publish --access public`. Designed to be run in CI after `napi build --release`.

| Option            | Default    | Description                      |
| ----------------- | ---------- | -------------------------------- |
| `--provenance`    | auto in CI | Generate provenance attestation. |
| `--no-provenance` |            | Skip provenance.                 |

Per-platform binding packages are published before the main package, so users who install during the publish window always get a working set.

## `napi npm-init`

```sh
napi npm-init --repo <owner/name> --workflow <file>
```

One-time setup: publishes initial `0.0.0` versions of every package and configures [npm trusted publishing](https://docs.npmjs.com/trusted-publishers) (OIDC). After this, your CI does not need an `NPM_TOKEN`.

| Option       | Required | Description                                    |
| ------------ | -------- | ---------------------------------------------- |
| `--repo`     | Yes      | GitHub repository as `owner/name`.             |
| `--workflow` | Yes      | The workflow filename in `.github/workflows/`. |

You only run this once per package. The CI pipeline takes over from here. See [Publishing](/publishing) for the full pipeline.
