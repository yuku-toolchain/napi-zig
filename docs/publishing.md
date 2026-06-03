# Publishing to npm

This is the end-to-end pipeline: per-platform binaries published as scoped sub-packages, a single meta package users install, and trusted publishing so CI never needs an `NPM_TOKEN`.

## How distribution works

Your addon ships as **one main package** plus **one binding sub-package per platform**:

```
my-addon                            <-- users install this
@my-addon/binding-darwin-arm64      <-- npm picks this on Apple Silicon
@my-addon/binding-darwin-x64        <-- npm picks this on Intel macs
@my-addon/binding-linux-x64-gnu     <-- ...
@my-addon/binding-linux-x64-musl
... (one per platform)
```

The main package's `optionalDependencies` lists every binding. npm uses each binding's `os`, `cpu`, and `libc` fields to install **only the one** that matches the user's machine. There is no `postinstall` hook and no native build step on the consumer's side. A user runs `npm install my-addon` and gets a single fast download.

The `@my-addon` part is your **npm scope**: the `@something` prefix on each binding's package name. It must refer to either:

- **Your npm username.** Every npm account has a personal scope at `@<your-username>`. It exists automatically.
- **An organization you own** on npm. Create one at [npmjs.com/org/create](https://www.npmjs.com/org/create) before you publish.

The recommended pattern is to make the scope name match the package name (`@my-addon` for `my-addon`); that is also the default if you scaffolded with `napi new`. Matching scope to package name makes binding ownership obvious to consumers. You can use any scope you own.

The scope is set in `build.zig`, in the `.scope` field inside the `.npm` block:

```zig
.npm = .{
    .scope = "@my-addon",
    // ...
},
```

If you change the scope later, the next `napi build --release` will migrate `npm/` cleanly. See [Cross-compiling](/cross-compiling).

## First-time setup, in order

Each step below assumes the previous one is done. **Do them in this order.**

### 1. Decide your scope

Open `build.zig` and review the `.scope` field. Set it to a username or org you own (or keep the default `@<package-name>` if you scaffolded). If the scope is an org, **create that org now** at [npmjs.com/org/create](https://www.npmjs.com/org/create). The recommended pattern is for the scope name to match the package name.

### 2. Update npm to a recent version

Trusted publishing requires `npm >= 11.10`.

```sh
npm install -g npm@latest
```

### 3. Cross-compile

```sh
napi build --release
```

This produces the `npm/` tree that gets published. Every per-platform binary is built. See [Cross-compiling](/cross-compiling) for what this lays out.

### 4. Log in to npm

```sh
npm login
```

The next step needs to publish initial `0.0.0` versions; that requires being logged in.

### 5. Push your code to GitHub

The publish workflow lives in `.github/workflows/publish.yml`. `napi new` writes it for you; if you set up by hand, copy the YAML from [The CI workflow](#the-ci-workflow) below into that path. The workflow runs on tag push, so it must be on the default branch before you tag a release. If your repo is local-only, push it now:

```sh
git init
git add -A
git commit -m "initial commit"
git remote add origin git@github.com:<owner>/<name>.git
git branch -M main
git push -u origin main
```

### 6. One-time publish + OIDC trust

```sh
napi npm-init --repo <owner>/<name> --workflow publish.yml
```

This:

1. **Verifies the scope exists** and is accessible to the logged-in account. If not, it stops with a clear error and instructions.
2. Publishes initial `0.0.0` versions of every package (main + every per-platform binding).
3. Configures [npm trusted publishing](https://docs.npmjs.com/trusted-publishers) for each one, stamping `<owner>/<name>` and `publish.yml` into the trusted-publisher record.

`--repo` is `owner/name` of your GitHub repository. `--workflow` is the workflow filename in `.github/workflows/`.

`napi npm-init` is idempotent: it skips any package that already exists on npm and only sets up new ones. After the first run the CI pipeline takes over for releases. You only need to run `napi npm-init` again if you later add another addon to `build.zig` (see [Multiple addons in one repo](#multiple-addons-in-one-repo) below).

## The release loop

Once setup is done, every release is a single command:

```sh
napi bump
```

`napi bump` updates the version in **every** `package.json` (main + per-platform bindings + any [extra packages](#extra-packages-in-npm)), commits, creates an annotated git tag, and pushes branch + tag in one round-trip. The push triggers the publish workflow on GitHub Actions, which runs `napi publish`.

Without arguments, `napi bump` shows an interactive picker (patch / minor / major / prerelease / conventional / explicit). You can also pass an explicit type or version:

```sh
napi bump          # interactive picker
napi bump patch    # 1.2.3 → 1.2.4
napi bump minor    # 1.2.3 → 1.3.0
napi bump major    # 1.2.3 → 2.0.0
napi bump 1.5.0    # exact version
```

`napi bump` requires:

- A clean working tree (no uncommitted changes).
- The current branch tracks a remote (so `git push --follow-tags` has somewhere to go).
- The publish workflow already on the default branch.

If any of those is missing, fix it first. `napi bump` is what triggers the publish on the remote, so without a remote there is nothing to publish.

## The CI workflow

Save this as `.github/workflows/publish.yml` (`napi new` writes it for you). With trusted publishing configured (step 6 above), no secrets are needed.

```yaml
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
      - name: Update npm
        run: npm install -g npm@latest
      - run: npm install
      - run: npx napi-zig build --release
      - run: npx napi-zig publish
```

Notes:

- `id-token: write` is what enables OIDC. Don't remove it.
- The `Update npm` step is required: trusted publishing needs `npm >= 11.10`, and `actions/setup-node` ships an older default.
- The job runs on a single `ubuntu-latest` runner because Zig cross-compiles every target from one host. No matrix needed.

## What `napi publish` does

For each package in `npm/`:

1. Reads its `package.json`.
2. Runs `npm publish --access public`.
3. Attaches a [provenance attestation](https://docs.npmjs.com/generating-provenance-statements/) (auto in CI).

Per-platform binding packages are published before the main package, so users who install during the small window between publishes always get a working set.

`napi publish` runs over every addon in `npm/`, so a repo with multiple `addLib` calls in `build.zig` publishes them all in the same CI run.

## Extra packages in npm/

Anything you drop into `npm/` that isn't generated by napi-zig (a pure-JS wrapper, a companion CLI, a types-only package) is treated as a **first-class package**. As long as a top-level directory under `npm/` has a `package.json` with a `name` and no `optionalDependencies`, every release command picks it up automatically:

- `napi bump` bumps its `version` in lockstep with the generated packages (its own dependency ranges are left untouched, since those are yours to manage).
- `napi publish` packs and publishes it alongside the addon (after the main package, so an extra that depends on the addon sees it on the registry first).
- `napi npm-init` publishes its initial version and configures trusted publishing for it.
- `napi build --release` leaves it alone and does **not** flag it as an orphan.

Just create the folder and commit it:

```
npm/
  my-addon/                  <-- napi-zig generated
    @my-addon/binding-*/
  my-addon-cli/              <-- your extra package, published as-is
    package.json
    index.js
```

There's nothing to configure. Drop the package in `npm/` and it ships with the rest.

## Multiple addons in one repo

You can ship more than one addon from the same repository: call `addLib` once per addon in `build.zig` (each with its own `.name` and `.scope`). Every command in this guide already iterates per-addon: `napi build --release` cross-compiles every one, `napi bump` bumps every one in lockstep, `napi publish` publishes every one. See [`addLib` reference](/reference/build) for the constraints on `.scope`.

When you add a new addon to an existing repo:

```sh
napi build --release
napi npm-init --repo <owner>/<name> --workflow publish.yml
```

`napi npm-init` skips packages that are already on npm and only publishes initial versions and configures trusted publishing for the new ones. From the next `napi bump` onwards, the new addon ships alongside the existing ones.

## Provenance

In CI, provenance is on by default. Override:

```sh
napi publish --no-provenance     # opt out
napi publish --provenance        # force on (rarely needed; default in CI)
```

Provenance proves the package was built from a specific commit on a specific workflow. It shows up on the npm registry as a verified badge.

Provenance requires every package to declare a `repository` field that points to the source tree, otherwise npm rejects the publish with "package must specify a repository". Set `.repository` once in `build.zig` (`.npm.repository = "owner/repo"`). Release builds then write the field into the main package and every per-platform binding (twelve files by default), so the `package.json` files stay in sync without hand-editing. See [`addLib` reference](/reference/build#repository) for the accepted forms.

## What users see

```sh
npm install my-addon
```

```js
import addon from "my-addon";
addon.add(2, 3);
```

No `postinstall` hook, no `node-gyp`, no `nan`. npm picks the right binding via `optionalDependencies` and the platform fields, and the install is one fast download.

## Troubleshooting

**`Scope @<name> not found or not accessible to <username>`** during `napi npm-init`.
The org doesn't exist yet, or you're not a member. Create it at [npmjs.com/org/create](https://www.npmjs.com/org/create), or change the scope in `build.zig` to one you already own and re-run `napi build --release` before retrying.

**`napi bump` fails on `git push --follow-tags`.**
Either the branch has no upstream, or you don't have push access. Set the upstream once with `git push -u origin main` and confirm the remote is correct with `git remote -v`.

**The published main package's `optionalDependencies` versions don't match the bindings.**
This shouldn't happen. `napi bump` updates every `package.json` in lockstep, and `napi build --release` reconciles `optionalDependencies` to the current main version. If you see drift, run `napi build --release` once more to re-sync.

**You changed `.scope` after the first `napi build --release`.**
Run `napi build --release` again. It removes the old `<scope>/` directory, writes the new one, and updates the main package's `optionalDependencies` to match. The version (managed by `napi bump`) and your user fields are preserved.

**You changed `.platforms` (added or removed targets).**
Run `napi build --release` again. Bindings for removed targets are deleted and `optionalDependencies` is updated; bindings for added targets are created.

**You renamed the addon's `.name`.**
Run `napi build --release` again. The build creates a new `npm/<new-name>/` tree, then warns about the old `npm/<old-name>/` orphan. Copy any user fields you want to keep onto the new main `package.json`, then delete the orphan folder. Renaming a published npm package itself is a separate concern: see npm's [renaming guide](https://docs.npmjs.com/about-package-name-collisions).
