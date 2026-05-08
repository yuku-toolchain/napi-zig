const std = @import("std");
const targets_mod = @import("build/targets.zig");

pub const Platform = targets_mod.Platform;

pub const Import = struct {
    name: []const u8,
    module: *std.Build.Module,
};

/// .d.ts emission mode. `.none` (default), `.{ .file = path }` for
/// a hand-written file, or `.auto` to generate from the zig source.
pub const Dts = union(enum) {
    none,
    auto,
    file: std.Build.LazyPath,
};

pub const NpmConfig = struct {
    scope: []const u8,
    description: []const u8 = "",
    license: []const u8 = "MIT",
    repository: []const u8 = "",
    dts: Dts = .none,
    platforms: []const Platform = Platform.defaults,
};

pub const LibOptions = struct {
    name: []const u8,
    root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const Import = &.{},
    npm: ?NpmConfig = null,
    /// windows host binary the addon loads into (`"electron.exe"` etc).
    /// only affects windows import-library generation.
    host_exe: []const u8 = "node.exe",
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("napi", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const test_step = b.step("test", "Run all tests");
    const tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/tests.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    test_step.dependOn(&b.addRunArtifact(tests).step);
}

/// build a .node for the current platform. with -Dnpm=true also
/// cross-compiles every platform listed in the npm config.
pub fn addLib(b: *std.Build, napi_dep: *std.Build.Dependency, options: LibOptions) void {
    const napi_module = napi_dep.module("napi");
    const node_api_def = napi_dep.path("build/node_api.def");

    const lib_mod = b.createModule(.{
        .root_source_file = options.root,
        .target = options.target,
        .optimize = options.optimize,
    });
    lib_mod.addImport("napi-zig", napi_module);
    for (options.imports) |imp| lib_mod.addImport(imp.name, imp.module);

    const dest_dir: std.Build.InstallDir = .lib;
    const install_step = if (options.target.result.cpu.arch.isWasm())
        installWasm(b, options.name, lib_mod, dest_dir)
    else
        installNative(b, options.name, lib_mod, options.target, dest_dir, options.host_exe, node_api_def, napi_dep);
    b.getInstallStep().dependOn(install_step);

    if (options.npm) |npm| {
        installDts(b, napi_dep, napi_module, options, npm.dts, .lib, b.fmt("{s}.d.ts", .{options.name}));
    }

    // npm release mode (cross-compile and scaffold)
    if (options.npm) |npm| {
        if (npmFlag(b)) addNpmRelease(b, napi_dep, napi_module, options, npm, node_api_def);
    }
}

// `b.option` panics on a duplicate name. When `addLib` is called more than
// once in the same build, only the first call declares `-Dnpm`; later calls
// read the existing value.
fn npmFlag(b: *std.Build) bool {
    if (b.available_options_map.contains("npm")) {
        const opt_ptr = b.user_input_options.getPtr("npm") orelse return false;
        opt_ptr.used = true;
        return switch (opt_ptr.value) {
            .flag => true,
            .scalar => |s| std.mem.eql(u8, s, "true"),
            else => false,
        };
    }
    return b.option(bool, "npm", "Cross-compile and generate npm packages") orelse false;
}

fn installDts(
    b: *std.Build,
    napi_dep: *std.Build.Dependency,
    napi_module: *std.Build.Module,
    options: LibOptions,
    dts: Dts,
    install_dir: std.Build.InstallDir,
    sub_path: []const u8,
) void {
    switch (dts) {
        .none => {},
        .file => |path| {
            const step = b.addInstallFileWithDir(path, install_dir, sub_path);
            b.getInstallStep().dependOn(&step.step);
        },
        .auto => {
            // host-targeted helper that imports the user module and
            // prints its generated .d.ts to a file.
            const host = b.graph.host;
            const user_host_mod = b.createModule(.{
                .root_source_file = options.root,
                .target = host,
                .optimize = .Debug,
            });
            user_host_mod.addImport("napi-zig", napi_module);
            for (options.imports) |imp| user_host_mod.addImport(imp.name, imp.module);

            const emit_mod = b.createModule(.{
                .root_source_file = napi_dep.path("build/dts_emit.zig"),
                .target = host,
                .optimize = .Debug,
            });
            emit_mod.addImport("napi-zig", napi_module);
            emit_mod.addImport("user-root", user_host_mod);

            const exe = b.addExecutable(.{
                .name = b.fmt("{s}-dts-emit", .{options.name}),
                .root_module = emit_mod,
            });

            const run = b.addRunArtifact(exe);
            const out = run.addOutputFileArg("index.d.ts");

            const step = b.addInstallFileWithDir(out, install_dir, sub_path);
            b.getInstallStep().dependOn(&step.step);
        },
    }
}

fn addNpmRelease(
    b: *std.Build,
    napi_dep: *std.Build.Dependency,
    napi_module: *std.Build.Module,
    options: LibOptions,
    npm: NpmConfig,
    node_api_def: std.Build.LazyPath,
) void {
    const wf = b.addWriteFiles();

    _ = wf.add(
        b.fmt("npm/{s}/binding.js", .{options.name}),
        bindingJs(b.allocator, options.name, npm.scope),
    );
    _ = wf.add(
        b.fmt("npm/{s}/package.json", .{options.name}),
        rootPackageJson(b.allocator, options.name, npm),
    );

    for (npm.platforms) |platform| {
        _ = wf.add(
            b.fmt("npm/{s}/{s}/binding-{s}/package.json", .{ options.name, npm.scope, platform.suffix() }),
            platformPackageJson(b.allocator, options.name, npm, platform),
        );
    }

    const install_wf = b.addInstallDirectory(.{
        .source_dir = wf.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install_wf.step);

    // cross-compile a binding for each platform: native -> .node, wasm -> .wasm.
    for (npm.platforms) |platform| {
        const target = b.resolveTargetQuery(platform.zigTarget());

        // wasm is a fallback path optimized for size. download and parse cost
        // matters more than raw throughput. native targets are tuned for speed.
        const optimize: std.builtin.OptimizeMode = if (platform.isWasm()) .ReleaseSmall else .ReleaseFast;

        const lib_mod = b.createModule(.{
            .root_source_file = options.root,
            .target = target,
            .optimize = optimize,
        });
        lib_mod.addImport("napi-zig", napi_module);
        for (options.imports) |imp| lib_mod.addImport(imp.name, imp.module);

        const dest_dir: std.Build.InstallDir = .{ .custom = b.fmt(
            "npm/{s}/{s}/binding-{s}",
            .{ options.name, npm.scope, platform.suffix() },
        ) };

        const install_step = if (platform.isWasm())
            installWasm(b, options.name, lib_mod, dest_dir)
        else
            installNative(b, options.name, lib_mod, target, dest_dir, options.host_exe, node_api_def, napi_dep);
        b.getInstallStep().dependOn(install_step);
    }

    const npm_dir: std.Build.InstallDir = .{ .custom = b.fmt("npm/{s}", .{options.name}) };
    installIndexJs(b, napi_dep, napi_module, options, npm_dir);
    installDts(b, napi_dep, napi_module, options, npm.dts, npm_dir, "index.d.ts");
}

fn installIndexJs(
    b: *std.Build,
    napi_dep: *std.Build.Dependency,
    napi_module: *std.Build.Module,
    options: LibOptions,
    install_dir: std.Build.InstallDir,
) void {
    const host = b.graph.host;
    const user_host_mod = b.createModule(.{
        .root_source_file = options.root,
        .target = host,
        .optimize = .Debug,
    });
    user_host_mod.addImport("napi-zig", napi_module);
    for (options.imports) |imp| user_host_mod.addImport(imp.name, imp.module);

    const emit_mod = b.createModule(.{
        .root_source_file = napi_dep.path("build/index_js_emit.zig"),
        .target = host,
        .optimize = .Debug,
    });
    emit_mod.addImport("napi-zig", napi_module);
    emit_mod.addImport("user-root", user_host_mod);

    const exe = b.addExecutable(.{
        .name = b.fmt("{s}-index-js-emit", .{options.name}),
        .root_module = emit_mod,
    });

    const run = b.addRunArtifact(exe);
    const out = run.addOutputFileArg("index.js");

    const step = b.addInstallFileWithDir(out, install_dir, "index.js");
    b.getInstallStep().dependOn(&step.step);
}

fn installNative(
    b: *std.Build,
    name: []const u8,
    lib_mod: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    dest_dir: std.Build.InstallDir,
    host_exe: []const u8,
    node_api_def: std.Build.LazyPath,
    napi_dep: *std.Build.Dependency,
) *std.Build.Step {
    const lib = b.addLibrary(.{
        .name = name,
        .root_module = lib_mod,
        .linkage = .dynamic,
    });
    configureLinkerFlags(b, lib, target, node_api_def, host_exe, napi_dep);

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = dest_dir },
        .dest_sub_path = b.fmt("{s}.node", .{name}),
        .pdb_dir = .disabled,
        .implib_dir = .disabled,
    });
    return &install.step;
}

// wasi reactor: no main, just exported functions. linking libc gives us
// malloc/free for emnapi to allocate strings/buffers across the wasm boundary.
fn installWasm(
    b: *std.Build,
    name: []const u8,
    lib_mod: *std.Build.Module,
    dest_dir: std.Build.InstallDir,
) *std.Build.Step {
    lib_mod.link_libc = true;
    lib_mod.export_symbol_names = &.{ "malloc", "free" };

    const exe = b.addExecutable(.{
        .name = name,
        .root_module = lib_mod,
    });
    exe.entry = .disabled;
    exe.rdynamic = true;
    // emnapi's runtime needs the indirect function table at instantiation
    // time (it routes function-pointer callbacks through it).
    exe.export_table = true;
    exe.wasi_exec_model = .reactor;

    const install = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = dest_dir },
        .dest_sub_path = b.fmt("{s}.wasm", .{name}),
    });
    return &install.step;
}

fn configureLinkerFlags(b: *std.Build, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, node_api_def: std.Build.LazyPath, host_exe: []const u8, napi_dep: *std.Build.Dependency) void {
    lib.root_module.red_zone = false;
    lib.root_module.unwind_tables = .none;
    // drop unreferenced sections, meaningful saving on small addons.
    lib.link_gc_sections = true;

    switch (target.result.os.tag) {
        .macos => {
            lib.linker_allow_shlib_undefined = true;
        },
        .linux, .freebsd => {
            lib.root_module.link_libc = true;
            // limit exports to the two n-api entry points. smaller binaries,
            // no symbol collisions across addons in the same process.
            lib.setVersionScript(napi_dep.path("build/exports.ld"));
        },
        .windows => {
            // pe/coff needs all symbols resolved at link time. generate
            // an import library from node_api.def so the linker knows the
            // n-api symbols come from the host exe at runtime.
            const machine = switch (target.result.cpu.arch) {
                .x86_64 => "i386:x86-64",
                .aarch64 => "arm64",
                else => @panic("unsupported Windows architecture for Node.js addon"),
            };
            const dlltool = b.addSystemCommand(&.{ b.graph.zig_exe, "dlltool" });
            dlltool.addArg("-d");
            dlltool.addFileArg(node_api_def);
            dlltool.addArg("-D");
            dlltool.addArg(host_exe);
            dlltool.addArg("-m");
            dlltool.addArg(machine);
            dlltool.addArg("-l");
            const node_lib = dlltool.addOutputFileArg("node.lib");
            lib.root_module.addObjectFile(node_lib);
        },
        else => {},
    }
}

fn rootPackageJson(alloc: std.mem.Allocator, name: []const u8, npm: NpmConfig) []const u8 {
    var deps: []const u8 = "";
    for (npm.platforms, 0..) |platform, i| {
        deps = std.fmt.allocPrint(alloc, "{s}    \"{s}/binding-{s}\": \"0.0.0\"{s}\n", .{
            deps,                                       npm.scope, platform.suffix(),
            if (i < npm.platforms.len - 1) "," else "",
        }) catch return "";
    }

    const desc_line = if (npm.description.len > 0)
        std.fmt.allocPrint(alloc, "  \"description\": \"{s}\",\n", .{npm.description}) catch ""
    else
        "";

    const repo_line = repositoryLine(alloc, npm.repository, 2);

    // emnapi runtime is only pulled in when wasm is one of the cross-compile
    // targets. pure-native packages stay dep-free.
    const deps_block = if (hasWasm(npm.platforms))
        \\  "dependencies": {
        \\    "@emnapi/core": "^1.10.0",
        \\    "@emnapi/runtime": "^1.10.0"
        \\  },
        \\
    else
        "";

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}",
        \\  "version": "0.0.0",
        \\{s}  "license": "{s}",
        \\{s}  "type": "module",
        \\  "main": "index.js",
        \\  "types": "index.d.ts",
        \\  "files": [
        \\    "index.js",
        \\    "index.d.ts",
        \\    "binding.js"
        \\  ],
        \\{s}  "optionalDependencies": {{
        \\{s}  }}
        \\}}
        \\
    , .{ name, desc_line, npm.license, repo_line, deps_block, deps }) catch "";
}

fn hasWasm(platforms: []const Platform) bool {
    for (platforms) |p| if (p.isWasm()) return true;
    return false;
}

fn platformPackageJson(alloc: std.mem.Allocator, name: []const u8, npm: NpmConfig, platform: Platform) []const u8 {
    const repo_line = repositoryLine(alloc, npm.repository, 2);
    const ext = if (platform.isWasm()) "wasm" else "node";

    // wasm runs anywhere, so no os/cpu/libc filter. npm installs it on
    // every platform as a fallback.
    const filter_lines = if (platform.isWasm()) "" else blk: {
        const os_str = platform.npmOs() orelse break :blk "";
        const cpu_str = platform.npmCpu() orelse break :blk "";
        const libc_line = if (platform.npmLibc()) |libc|
            std.fmt.allocPrint(alloc, "  \"libc\": [\"{s}\"],\n", .{libc}) catch ""
        else
            "";
        break :blk std.fmt.allocPrint(alloc,
            \\  "os": ["{s}"],
            \\  "cpu": ["{s}"],
            \\{s}
        , .{ os_str, cpu_str, libc_line }) catch "";
    };

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}/binding-{s}",
        \\  "version": "0.0.0",
        \\{s}{s}  "main": "{s}.{s}",
        \\  "files": [
        \\    "{s}.{s}"
        \\  ]
        \\}}
        \\
    , .{
        npm.scope, platform.suffix(),
        filter_lines, repo_line,
        name,         ext,
        name,         ext,
    }) catch "";
}

/// emits a `"repository": { "type": "git", "url": "..." },\n` block
/// indented by `indent` spaces. returns "" when repo is empty.
fn repositoryLine(alloc: std.mem.Allocator, repo: []const u8, indent: usize) []const u8 {
    if (repo.len == 0) return "";
    const pad = "                ";
    const lead = pad[0..@min(indent, pad.len)];
    const url = repositoryUrl(alloc, repo);
    if (url.len == 0) return "";
    return std.fmt.allocPrint(alloc,
        \\{s}"repository": {{
        \\{s}  "type": "git",
        \\{s}  "url": "{s}"
        \\{s}}},
        \\
    , .{ lead, lead, lead, url, lead }) catch "";
}

/// expands an `owner/repo` shorthand to a github git+https url.
/// any string that already looks like a url is passed through.
fn repositoryUrl(alloc: std.mem.Allocator, repo: []const u8) []const u8 {
    if (repo.len == 0) return "";
    if (std.mem.startsWith(u8, repo, "http://") or
        std.mem.startsWith(u8, repo, "https://") or
        std.mem.startsWith(u8, repo, "git+") or
        std.mem.startsWith(u8, repo, "git@") or
        std.mem.startsWith(u8, repo, "ssh://"))
    {
        return alloc.dupe(u8, repo) catch "";
    }
    return std.fmt.allocPrint(alloc, "git+https://github.com/{s}.git", .{repo}) catch "";
}

fn bindingJs(alloc: std.mem.Allocator, name: []const u8, scope: []const u8) []const u8 {
    return std.fmt.allocPrint(alloc,
        \\import {{ createRequire }} from 'node:module';
        \\import {{ readFileSync, existsSync }} from 'node:fs';
        \\import {{ execSync }} from 'node:child_process';
        \\import {{ fileURLToPath }} from 'node:url';
        \\import {{ dirname, join }} from 'node:path';
        \\
        \\const require = createRequire(import.meta.url);
        \\const __dirname = dirname(fileURLToPath(import.meta.url));
        \\const {{ platform, arch }} = process;
        \\
        \\const isFileMusl = (f) => f.includes('libc.musl-') || f.includes('ld-musl-');
        \\
        \\function isMusl() {{
        \\  if (platform !== 'linux') return false;
        \\
        \\  try {{
        \\    if (readFileSync('/usr/bin/ldd', 'utf-8').includes('musl')) return true;
        \\  }} catch {{}}
        \\
        \\  try {{
        \\    const report = typeof process.report?.getReport === 'function'
        \\      ? process.report.getReport()
        \\      : null;
        \\    if (report) {{
        \\      const header = typeof report === 'string' ? JSON.parse(report).header : report.header;
        \\      if (header?.glibcVersionRuntime) return false;
        \\      if (Array.isArray(report.sharedObjects) && report.sharedObjects.some(isFileMusl)) return true;
        \\    }}
        \\  }} catch {{}}
        \\
        \\  try {{
        \\    return execSync('ldd --version', {{ encoding: 'utf8' }}).includes('musl');
        \\  }} catch {{}}
        \\
        \\  return false;
        \\}}
        \\
        \\function findWasm() {{
        \\  const local = join(__dirname, '{s}', 'binding-wasm32-wasi', '{s}.wasm');
        \\  if (existsSync(local)) return local;
        \\  try {{ return require.resolve('{s}/binding-wasm32-wasi'); }} catch {{ return null; }}
        \\}}
        \\
        \\function loadWasm() {{
        \\  const path = findWasm();
        \\  if (!path) return null;
        \\  const {{ instantiateNapiModuleSync }} = require('@emnapi/core');
        \\  const {{ getDefaultContext }} = require('@emnapi/runtime');
        \\  const {{ WASI }} = require('node:wasi');
        \\  const wasi = new WASI({{ version: 'preview1', env: process.env }});
        \\  const {{ napiModule }} = instantiateNapiModuleSync(readFileSync(path), {{
        \\    context: getDefaultContext(),
        \\    wasi,
        \\    // emnapi splits napi and emnapi into separate import modules.
        \\    // zig (and clang wasm32) imports them from `env`, so merge them.
        \\    overwriteImports(imports) {{
        \\      imports.env = {{ ...imports.env, ...imports.napi, ...imports.emnapi }};
        \\      return imports;
        \\    }},
        \\  }});
        \\  return napiModule.exports;
        \\}}
        \\
        \\function loadBinding() {{
        \\  const errors = [];
        \\  const libc = platform === 'linux' ? (isMusl() ? '-musl' : '-gnu') : '';
        \\  const suffix = `${{platform}}-${{arch}}${{libc}}`;
        \\
        \\  try {{
        \\    return require(join(__dirname, '{s}', 'binding-' + suffix, '{s}.node'));
        \\  }} catch (e) {{
        \\    errors.push(e);
        \\  }}
        \\
        \\  try {{
        \\    return require('{s}/binding-' + suffix + '/{s}.node');
        \\  }} catch (e) {{
        \\    errors.push(e);
        \\  }}
        \\
        \\  try {{
        \\    const wasm = loadWasm();
        \\    if (wasm) return wasm;
        \\  }} catch (e) {{
        \\    errors.push(e);
        \\  }}
        \\
        \\  throw new Error(
        \\    `Failed to load native binding for ${{platform}}-${{arch}}.\n` +
        \\    `If this persists, try removing node_modules and reinstalling.\n` +
        \\    errors.map(e => `  - ${{e.message}}`).join('\n'),
        \\    {{ cause: errors[errors.length - 1] }}
        \\  );
        \\}}
        \\
        \\export default loadBinding();
        \\
    , .{ scope, name, scope, scope, name, scope, name }) catch "";
}
