const std = @import("std");
const targets_mod = @import("build/targets.zig");

pub const Platform = targets_mod.Platform;

pub const Import = struct {
    name: []const u8,
    module: *std.Build.Module,
};

pub const Repository = struct {
    type: []const u8 = "git",
    url: []const u8,
};

/// `.dts` controls TypeScript declaration emission for the addon.
///
/// - `.none`         , don't emit a `.d.ts`. (Default.)
/// - `.{ .file = … }`, copy a hand-written `.d.ts`. **Recommended for
///                      libraries published to npm**, gives you full
///                      TypeScript expressiveness (overloads, conditional
///                      types, JSDoc, etc).
/// - `.auto`         , generate one automatically by walking your module
///                      at comptime. Useful for prototypes and internal
///                      addons. The output is a starting point; expect
///                      `unknown` wherever you used `napi.Val` or
///                      `napi.Callback`. Tighten those Zig signatures
///                      or switch to `.file` to fix.
pub const Dts = union(enum) {
    none,
    auto,
    file: std.Build.LazyPath,
};

pub const NpmConfig = struct {
    scope: []const u8,
    repository: Repository,
    description: []const u8 = "",
    license: []const u8 = "MIT",
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
    /// Windows host binary the addon will be loaded into. Defaults to
    /// `"node.exe"`. Set to `"electron.exe"` for Electron, etc. Only
    /// affects the Windows import-library generation; ignored elsewhere.
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

/// Build a `.node` shared library for the current platform, and
/// (optionally, behind `-Dnpm=true`) cross-compile binding packages
/// for every platform listed in the npm config.
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

    const lib = b.addLibrary(.{
        .name = options.name,
        .root_module = lib_mod,
        .linkage = .dynamic,
    });
    configureLinkerFlags(b, lib, options.target, node_api_def, options.host_exe, napi_dep);

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = b.fmt("{s}.node", .{options.name}),
    });
    b.getInstallStep().dependOn(&install.step);

    // .d.ts for local development
    if (options.npm) |npm| {
        installDts(b, napi_dep, napi_module, options, npm.dts, .lib, b.fmt("{s}.d.ts", .{options.name}));
    }

    // npm release mode (cross-compile + scaffold)
    if (options.npm) |npm| {
        const do_npm = b.option(bool, "npm", "Cross-compile and generate npm packages") orelse false;
        if (do_npm) addNpmRelease(b, napi_dep, napi_module, options, npm, node_api_def);
    }
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
            // Build a host-targeted helper that imports the user module
            // and prints its generated .d.ts to a file.
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
    _ = wf.add(
        b.fmt("npm/{s}/index.js", .{options.name}),
        defaultIndexJs(b.allocator),
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

    // Cross-compile .node for each platform.
    for (npm.platforms) |platform| {
        const target = b.resolveTargetQuery(platform.zigTarget());

        const lib_mod = b.createModule(.{
            .root_source_file = options.root,
            .target = target,
            .optimize = .ReleaseFast,
        });
        lib_mod.addImport("napi-zig", napi_module);
        for (options.imports) |imp| lib_mod.addImport(imp.name, imp.module);

        const lib = b.addLibrary(.{
            .name = options.name,
            .root_module = lib_mod,
            .linkage = .dynamic,
        });
        configureLinkerFlags(b, lib, target, node_api_def, options.host_exe, napi_dep);

        const node_install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{
                .custom = b.fmt("npm/{s}/{s}/binding-{s}", .{ options.name, npm.scope, platform.suffix() }),
            } },
            .dest_sub_path = b.fmt("{s}.node", .{options.name}),
            .pdb_dir = .disabled,
            .implib_dir = .disabled,
        });
        b.getInstallStep().dependOn(&node_install.step);
    }

    // .d.ts inside the npm package
    installDts(b, napi_dep, napi_module, options, npm.dts, .{ .custom = b.fmt("npm/{s}", .{options.name}) }, "index.d.ts");
}

fn configureLinkerFlags(b: *std.Build, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, node_api_def: std.Build.LazyPath, host_exe: []const u8, napi_dep: *std.Build.Dependency) void {
    lib.root_module.red_zone = false;
    lib.root_module.unwind_tables = .none;
    // Drop unreferenced sections, meaningful saving on small addons.
    lib.link_gc_sections = true;

    switch (target.result.os.tag) {
        .macos => {
            lib.linker_allow_shlib_undefined = true;
            // (Symbol-export limiting on macOS requires `-exported_symbols_list`,
            // which Zig 0.17's Compile API doesn't expose directly. Skipped.)
        },
        .linux, .freebsd => {
            lib.root_module.link_libc = true;
            // Limit exported symbols to the two N-API entry points.
            // Smaller binaries; no accidental symbol collisions when
            // multiple addons load into the same process.
            lib.setVersionScript(napi_dep.path("build/exports.ld"));
        },
        .windows => {
            // Windows PE/COFF needs all symbols resolved at link time.
            // Generate an import library from node_api.def so the linker
            // knows these N-API symbols come from the host (node.exe,
            // electron.exe, etc.) at runtime.
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
            deps, npm.scope, platform.suffix(),
            if (i < npm.platforms.len - 1) "," else "",
        }) catch return "";
    }

    const desc_line = if (npm.description.len > 0)
        std.fmt.allocPrint(alloc, "  \"description\": \"{s}\",\n", .{npm.description}) catch ""
    else
        "";

    const repo_line = std.fmt.allocPrint(alloc,
        \\  "repository": {{
        \\    "type": "{s}",
        \\    "url": "{s}"
        \\  }},
        \\
    , .{ npm.repository.type, npm.repository.url }) catch "";

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}",
        \\  "version": "0.0.0",
        \\{s}{s}  "license": "{s}",
        \\  "type": "module",
        \\  "main": "index.js",
        \\  "types": "index.d.ts",
        \\  "files": [
        \\    "index.js",
        \\    "index.d.ts",
        \\    "binding.js"
        \\  ],
        \\  "optionalDependencies": {{
        \\{s}  }}
        \\}}
        \\
    , .{ name, desc_line, repo_line, npm.license, deps }) catch "";
}

fn platformPackageJson(alloc: std.mem.Allocator, name: []const u8, npm: NpmConfig, platform: Platform) []const u8 {
    const libc_line = if (platform.npmLibc()) |libc|
        std.fmt.allocPrint(alloc, "  \"libc\": [\"{s}\"],\n", .{libc}) catch ""
    else
        "";

    const repo_line = std.fmt.allocPrint(alloc,
        \\  "repository": {{
        \\    "type": "{s}",
        \\    "url": "{s}"
        \\  }},
        \\
    , .{ npm.repository.type, npm.repository.url }) catch "";

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}/binding-{s}",
        \\  "version": "0.0.0",
        \\{s}  "os": ["{s}"],
        \\  "cpu": ["{s}"],
        \\{s}  "main": "{s}.node",
        \\  "files": [
        \\    "{s}.node"
        \\  ]
        \\}}
        \\
    , .{
        npm.scope, platform.suffix(),       repo_line, platform.npmOs(),
        platform.npmCpu(), libc_line,       name,      name,
    }) catch "";
}

fn bindingJs(alloc: std.mem.Allocator, name: []const u8, scope: []const u8) []const u8 {
    return std.fmt.allocPrint(alloc,
        \\import {{ createRequire }} from 'node:module';
        \\import {{ readFileSync }} from 'node:fs';
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
    , .{ scope, name, scope, name }) catch "";
}

fn defaultIndexJs(alloc: std.mem.Allocator) []const u8 {
    return std.fmt.allocPrint(alloc,
        \\import binding from './binding.js';
        \\export default binding;
        \\
    , .{}) catch "";
}
