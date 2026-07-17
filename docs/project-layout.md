# Project layout

A napi-zig project is a Zig project and a Node.js project sharing one root. This page is a one-stop map: every file in the project, every directory the build creates, and where to look for more on each.

The same layout applies whether you scaffolded with `napi-zig new` or wired things up by hand following [Manual setup](/manual-setup).

## Source tree

```
my-addon/
├── build.zig              # napi_zig.addLib entry point
├── build.zig.zon          # Zig dependency lockfile
├── package.json           # npm name, version, scripts
├── src/
│   └── lib.zig            # your addon's root module
├── test.mjs               # smoke test
├── .gitignore
├── README.md
└── .github/
    └── workflows/
        └── publish.yml    # tag-driven publish (OIDC, no NPM_TOKEN)
```

| File / dir                      | Purpose                                                                                                                                                             |
| ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `build.zig`                     | The single call to [`napi_zig.addLib`](/reference/build) configures the artifact and the npm release graph.                                                         |
| `build.zig.zon`                 | Pins the napi-zig Zig dependency. Zig manages this; you rarely edit it.                                                                                             |
| `package.json`                  | The local Node project. Holds dev deps and `napi-zig build` / `napi-zig bump` script aliases.                                                                       |
| `src/lib.zig`                   | The **root module**. Everything `pub` in this file is a JS export. See [Functions](/functions). To use a different file or location, update `.root` in `build.zig`. |
| `test.mjs`                      | Loads the built addon and exercises it. The default scripts run it via `node test.mjs`.                                                                             |
| `.github/workflows/publish.yml` | Tag-driven CI publish. See [Publishing](/publishing#the-ci-workflow).                                                                                               |

## After `napi-zig build`

```
zig-out/lib/
├── <name>.node            # the native module Node loads
└── <name>.d.ts            # generated TypeScript types (if .dts is set)

<name>.js                  # CLI-written re-exporter at the project root
<name>.d.ts                # copied alongside <name>.js (if .dts is set)
```

`<name>.js` lets `import addon from "./<name>.js"` work locally without going through the npm package layout. It points at `zig-out/lib/<name>.node`. Both `<name>.js` and `<name>.d.ts` at the project root are gitignored; they are derived artifacts.

## After `napi-zig build --release`

```
bindings/<name>/
├── package.json
├── index.js               # your seam over the addon
├── binding.js             # platform detection + dynamic require
├── index.d.ts             # types (if .dts is set)
└── <scope>/
    └── binding-<os>-<arch>[-<libc>]/
        ├── package.json
        └── <name>.node
```

This is the publishable tree. `napi-zig publish` ships every directory under `bindings/` to npm. The tree is reconciled on every release build: policy fields come from `build.zig`, your version and user-edited fields are preserved. See [Cross-compiling](/cross-compiling#what-every-release-build-does) for the full rules.

If `build.zig` calls `addLib` more than once, each addon gets its own `bindings/<name>/` subtree alongside the others. See [Multiple addons in one repo](/publishing#multiple-addons-in-one-repo).

## Where to put your code

- **One file is fine.** Keep adding to `src/lib.zig` until it feels too large.
- **Splitting into namespaces.** A `pub const x = @import("x.zig")` in `lib.zig` becomes the JS namespace `addon.x`. See [Namespaces](/namespaces#splitting-across-files).
- **Shared Zig modules outside the root.** Pass them through `.imports` so they are importable as `@import("name")` from anywhere in your addon. See [`addLib` `Import`](/reference/build#import).

## Generated and ignored

Exclude everything derived from version control: `node_modules`, `zig-out`, `.zig-cache`, `zig-pkg`, and the project-root `<name>.js` / `<name>.d.ts` re-exporters. (`napi-zig new` writes a `.gitignore` with all of these; if you set up by hand, see [Manual setup, step 5](/manual-setup#_5-add-a-gitignore).) Commit `bindings/` once you start publishing. Every release build keeps it in sync with `build.zig` automatically.
