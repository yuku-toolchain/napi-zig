const std = @import("std");
const targets_mod = @import("build/targets.zig");

pub const Platform = targets_mod.Platform;

pub const Import = struct {
    name: []const u8,
    module: *std.Build.Module,
};

pub const NpmConfig = struct {
    scope: []const u8,
    description: []const u8 = "",
    license: []const u8 = "MIT",
    dts: ?std.Build.LazyPath = null,
    platforms: []const Platform = Platform.defaults,
};

pub const LibOptions = struct {
    name: []const u8,
    root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const Import = &.{},
    npm: ?NpmConfig = null,
};

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    _ = b.addModule("napi", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const check_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const check_lib = b.addLibrary(.{
        .name = "napi-zig",
        .root_module = check_mod,
        .linkage = .dynamic,
    });

    check_lib.linker_allow_shlib_undefined = true;

    const check_step = b.step("check", "Check the source compiles");

    check_step.dependOn(&check_lib.step);
}

pub const Lib = struct {
    compile: *std.Build.Step.Compile,
    install: *std.Build.Step.InstallArtifact,
    step: *std.Build.Step,
};

/// build a .node shared library for the current platform.
///
/// installs to zig-out/lib/{name}.node for local development.
///
/// if `npm` config is provided and `-Dnpm=true` is passed, also cross-compiles
/// for all target platforms and generates npm package scaffold in zig-out/npm/.
/// use the napi-zig CLI to sync the output to your project's npm/ folder.
pub fn addLib(b: *std.Build, napi_dep: *std.Build.Dependency, options: LibOptions) Lib {
    const napi_module = napi_dep.module("napi");
    const node_api_def = napi_dep.path("build/node_api.def");

    const lib_mod = b.createModule(.{
        .root_source_file = options.root,
        .target = options.target,
        .optimize = options.optimize,
    });

    lib_mod.addImport("napi-zig", napi_module);
    for (options.imports) |imp| {
        lib_mod.addImport(imp.name, imp.module);
    }

    const lib = b.addLibrary(.{
        .name = options.name,
        .root_module = lib_mod,
        .linkage = .dynamic,
    });

    configureLinkerFlags(b, lib, options.target, node_api_def);

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = b.fmt("{s}.node", .{options.name}),
    });

    // connect to default install step so `zig build` builds the .node
    b.getInstallStep().dependOn(&install.step);

    // install .d.ts to zig-out/lib/ for dev use
    if (options.npm) |npm| {
        if (npm.dts) |dts_path| {
            const install_dts = b.addInstallFileWithDir(dts_path, .lib, b.fmt("{s}.d.ts", .{options.name}));
            b.getInstallStep().dependOn(&install_dts.step);
        }
    }

    // npm release mode
    if (options.npm) |npm| {
        const do_npm = b.option(bool, "npm", "Cross-compile and generate npm packages") orelse false;
        if (do_npm) {
            addNpmRelease(b, napi_module, options, npm, node_api_def);
        }
    }

    return .{
        .compile = lib,
        .install = install,
        .step = &install.step,
    };
}

fn addNpmRelease(
    b: *std.Build,
    napi_module: *std.Build.Module,
    options: LibOptions,
    npm: NpmConfig,
    node_api_def: std.Build.LazyPath,
) void {
    const wf = b.addWriteFiles();

    // binding.js (platform loader, internal)
    _ = wf.add(
        b.fmt("npm/{s}/binding.js", .{options.name}),
        bindingJs(b.allocator, options.name, npm.scope),
    );

    // root package.json
    _ = wf.add(
        b.fmt("npm/{s}/package.json", .{options.name}),
        rootPackageJson(b.allocator, options.name, npm),
    );

    // default index.js
    _ = wf.add(
        b.fmt("npm/{s}/index.js", .{options.name}),
        defaultIndexJs(b.allocator, options.name),
    );

    // platform binding package.json files
    for (npm.platforms) |platform| {
        _ = wf.add(
            b.fmt("npm/{s}/{s}/binding-{s}/package.json", .{
                options.name, npm.scope, platform.suffix(),
            }),
            platformPackageJson(b.allocator, options.name, npm, platform),
        );
    }

    const install_wf = b.addInstallDirectory(.{
        .source_dir = wf.getDirectory(),
        .install_dir = .prefix,
        .install_subdir = "",
    });
    b.getInstallStep().dependOn(&install_wf.step);

    // cross-compile .node for each platform
    for (npm.platforms) |platform| {
        const target = b.resolveTargetQuery(platform.zigTarget());

        const lib_mod = b.createModule(.{
            .root_source_file = options.root,
            .target = target,
            .optimize = .ReleaseFast,
        });

        lib_mod.addImport("napi-zig", napi_module);
        for (options.imports) |imp| {
            lib_mod.addImport(imp.name, imp.module);
        }

        const lib = b.addLibrary(.{
            .name = options.name,
            .root_module = lib_mod,
            .linkage = .dynamic,
        });

        configureLinkerFlags(b, lib, target, node_api_def);

        const node_install = b.addInstallArtifact(lib, .{
            .dest_dir = .{ .override = .{
                .custom = b.fmt("npm/{s}/{s}/binding-{s}", .{
                    options.name, npm.scope, platform.suffix(),
                }),
            } },
            .dest_sub_path = b.fmt("{s}.node", .{options.name}),
            .pdb_dir = .disabled,
            .implib_dir = .disabled,
        });

        b.getInstallStep().dependOn(&node_install.step);
    }

    // user-provided .d.ts
    if (npm.dts) |dts_path| {
        const install_dts = b.addInstallFileWithDir(
            dts_path,
            .{ .custom = b.fmt("npm/{s}", .{options.name}) },
            "index.d.ts",
        );
        b.getInstallStep().dependOn(&install_dts.step);
    }
}

fn configureLinkerFlags(b: *std.Build, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, node_api_def: std.Build.LazyPath) void {
    lib.root_module.red_zone = false;
    lib.root_module.unwind_tables = .none;

    switch (target.result.os.tag) {
        .macos => {
            lib.linker_allow_shlib_undefined = true;
        },
        .linux, .freebsd => {
            lib.root_module.link_libc = true;
        },
        .windows => {
            // windows PE/COFF requires all symbols resolved at link time.
            // generate an import library from node_api.def so the linker knows
            // these N-API symbols come from node.exe at runtime.
            const machine = switch (target.result.cpu.arch) {
                .x86_64 => "i386:x86-64",
                .aarch64 => "arm64",
                else => @panic("unsupported Windows architecture for Node.js addon"),
            };
            const dlltool = b.addSystemCommand(&.{ b.graph.zig_exe, "dlltool" });
            dlltool.addArg("-d");
            dlltool.addFileArg(node_api_def);
            dlltool.addArg("-D");
            dlltool.addArg("node.exe");
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

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}",
        \\  "version": "0.0.0",
        \\{s}  "license": "{s}",
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
    , .{
        name,
        desc_line,
        npm.license,
        deps,
    }) catch "";
}

fn platformPackageJson(alloc: std.mem.Allocator, name: []const u8, npm: NpmConfig, platform: Platform) []const u8 {
    const libc_line = if (platform.npmLibc()) |libc|
        std.fmt.allocPrint(alloc, "  \"libc\": [\"{s}\"],\n", .{libc}) catch ""
    else
        "";

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}/binding-{s}",
        \\  "version": "0.0.0",
        \\  "os": ["{s}"],
        \\  "cpu": ["{s}"],
        \\{s}  "main": "{s}.node",
        \\  "files": [
        \\    "{s}.node"
        \\  ]
        \\}}
        \\
    , .{
        npm.scope,
        platform.suffix(),
        platform.npmOs(),
        platform.npmCpu(),
        libc_line,
        name,
        name,
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

fn defaultIndexJs(alloc: std.mem.Allocator, name: []const u8) []const u8 {
    _ = name;
    return std.fmt.allocPrint(alloc,
        \\import binding from './binding.js';
        \\export default binding;
        \\
    , .{}) catch "";
}
