# Project layout

A napi-zig project is a Zig project and a Node.js project sharing one root. This page is a one-stop map: every file the scaffolder writes, every directory the build creates, and where to look for more on each.

## After `napi new`

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
| `package.json`                  | The local Node project. Holds dev deps and `napi build` / `napi bump` script aliases.                                                                               |
| `src/lib.zig`                   | The **root module**. Everything `pub` in this file is a JS export. See [Functions](/functions). To use a different file or location, update `.root` in `build.zig`. |
| `test.mjs`                      | Loads the built addon and exercises it. The default scripts run it via `node test.mjs`.                                                                             |
| `.github/workflows/publish.yml` | Tag-driven CI publish. See [Publishing](/publishing#the-ci-workflow).                                                                                               |

## After `napi build`

```
zig-out/lib/
├── <name>.node            # the native module Node loads
└── <name>.d.ts            # generated TypeScript types (if .dts is set)

<name>.js                  # CLI-written re-exporter at the project root
<name>.d.ts                # copied alongside <name>.js (if .dts is set)
```

`<name>.js` lets `import addon from "./<name>.js"` work locally without going through the npm package layout. It points at `zig-out/lib/<name>.node`. Both `<name>.js` and `<name>.d.ts` at the project root are gitignored; they are derived artifacts.

## After `napi build --release`

```
npm/<name>/
├── package.json
├── index.js               # your seam over the addon
├── binding.js             # platform detection + dynamic require
├── index.d.ts             # types (if .dts is set)
└── <scope>/
    └── binding-<os>-<arch>[-<libc>]/
        ├── package.json
        └── <name>.node
```

This is the publishable tree. `napi publish` ships every directory under `npm/` to npm. The tree is reconciled on every release build: policy fields come from `build.zig`, your version and user-edited fields are preserved. See [Cross-compiling](/cross-compiling#what-every-release-build-does) for the full rules.

## Where to put your code

- **One file is fine.** Keep adding to `src/lib.zig` until it feels too large.
- **Splitting into namespaces.** A `pub const x = @import("x.zig")` in `lib.zig` becomes the JS namespace `addon.x`. See [Namespaces](/namespaces#splitting-across-files).
- **Shared Zig modules outside the root.** Pass them through `.imports` so they are importable as `@import("name")` from anywhere in your addon. See [`addLib` `Import`](/reference/build#import).

## Generated and ignored

The scaffolder's `.gitignore` excludes everything derived: `node_modules`, `zig-out`, `.zig-cache`, `zig-pkg`, and the project-root `<name>.js` / `<name>.d.ts` re-exporters. Commit `npm/` only after your first `napi build --release`; from then on, every release build keeps it in sync with `build.zig` automatically.
