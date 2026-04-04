const std = @import("std");
const targets_mod = @import("build/targets.zig");

pub const Platform = targets_mod.Platform;

pub const Import = struct {
    name: []const u8,
    module: *std.Build.Module,
};

pub const LibOptions = struct {
    name: []const u8,
    root: std.Build.LazyPath,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    imports: []const Import = &.{},
};

pub const PackOptions = struct {
    output: []const u8 = "npm",
    entries: []const PackEntry,
    platforms: []const Platform = Platform.defaults,
};

pub const PackEntry = struct {
    name: []const u8,
    scope: []const u8,
    version: []const u8,
    description: []const u8 = "",
    license: []const u8 = "MIT",
    root: std.Build.LazyPath,
    imports: []const Import = &.{},
    /// user-provided .d.ts file path. null = auto-generate from comptime.
    dts: ?std.Build.LazyPath = null,
};

pub fn build(b: *std.Build) void {
    _ = b.addModule("napi", .{
        .root_source_file = b.path("src/root.zig"),
    });
}

pub const Lib = struct {
    compile: *std.Build.Step.Compile,
    install: *std.Build.Step.InstallArtifact,
    step: *std.Build.Step,
};

/// build a .node shared library for the current platform (dev mode).
/// installs to `zig-out/lib/{name}.node`.
pub fn addLib(b: *std.Build, napi_dep: *std.Build.Dependency, options: LibOptions) Lib {
    const napi_module = napi_dep.module("napi");

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

    configureLinkerFlags(lib, options.target);

    // install as {name}.node instead of platform default (lib*.dylib / lib*.so / *.dll)
    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = b.fmt("{s}.node", .{options.name}),
    });

    return .{
        .compile = lib,
        .install = install,
        .step = &install.step,
    };
}

/// add a pack step that cross-compiles for all platforms and generates npm packages.
pub fn addPack(b: *std.Build, napi_dep: *std.Build.Dependency, options: PackOptions) void {
    const pack_step = b.step("pack", "Cross-compile and package for npm");
    const napi_module = napi_dep.module("napi");

    for (options.entries) |entry| {
        const wf = b.addWriteFiles();

        // root package.json
        _ = wf.add(
            b.fmt("{s}/{s}/package.json", .{ options.output, entry.name }),
            rootPackageJson(b.allocator, entry, options.platforms),
        );

        // index.js loader
        _ = wf.add(
            b.fmt("{s}/{s}/index.js", .{ options.output, entry.name }),
            indexJs(b.allocator, entry),
        );

        // platform package.json files
        for (options.platforms) |platform| {
            _ = wf.add(
                b.fmt("{s}/{s}/{s}/binding-{s}/package.json", .{
                    options.output, entry.name, entry.scope, platform.suffix(),
                }),
                platformPackageJson(b.allocator, entry, platform),
            );
        }

        const install_wf = b.addInstallDirectory(.{
            .source_dir = wf.getDirectory(),
            .install_dir = .prefix,
            .install_subdir = "",
        });
        pack_step.dependOn(&install_wf.step);

        // cross-compile for each platform
        for (options.platforms) |platform| {
            const target = b.resolveTargetQuery(platform.zigTarget());

            const lib_mod = b.createModule(.{
                .root_source_file = entry.root,
                .target = target,
                .optimize = .ReleaseFast,
            });

            lib_mod.addImport("napi-zig", napi_module);
            for (entry.imports) |imp| {
                lib_mod.addImport(imp.name, imp.module);
            }

            const lib = b.addLibrary(.{
                .name = entry.name,
                .root_module = lib_mod,
                .linkage = .dynamic,
            });

            configureLinkerFlags(lib, target);

            const install = b.addInstallArtifact(lib, .{
                .dest_dir = .{ .override = .{
                    .custom = b.fmt("{s}/{s}/{s}/binding-{s}", .{
                        options.output, entry.name, entry.scope, platform.suffix(),
                    }),
                } },
                .dest_sub_path = b.fmt("{s}.node", .{entry.name}),
            });

            pack_step.dependOn(&install.step);
        }

        // user-provided dts
        if (entry.dts) |dts_path| {
            const install_dts = b.addInstallFileWithDir(
                dts_path,
                .{ .custom = b.fmt("{s}/{s}", .{ options.output, entry.name }) },
                "index.d.ts",
            );
            pack_step.dependOn(&install_dts.step);
        }
    }
}

fn configureLinkerFlags(lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    lib.root_module.red_zone = false;
    lib.root_module.unwind_tables = .none;

    switch (target.result.os.tag) {
        .macos => {
            lib.linker_allow_shlib_undefined = true;
        },
        .linux => {
            // napi addons on linux typically need libc for c_allocator
            lib.root_module.link_libc = true;
        },
        else => {},
    }
}

fn rootPackageJson(alloc: std.mem.Allocator, entry: PackEntry, platforms: []const Platform) []const u8 {
    var deps: []const u8 = "";
    for (platforms, 0..) |platform, i| {
        deps = std.fmt.allocPrint(alloc, "{s}    \"{s}/binding-{s}\": \"{s}\"{s}\n", .{
            deps, entry.scope, platform.suffix(), entry.version,
            if (i < platforms.len - 1) "," else "",
        }) catch return "";
    }

    const desc_line = if (entry.description.len > 0)
        std.fmt.allocPrint(alloc, "  \"description\": \"{s}\",\n", .{entry.description}) catch ""
    else
        "";

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}",
        \\  "version": "{s}",
        \\{s}  "license": "{s}",
        \\  "main": "index.js",
        \\  "types": "index.d.ts",
        \\  "files": [
        \\    "index.js",
        \\    "index.d.ts"
        \\  ],
        \\  "optionalDependencies": {{
        \\{s}  }}
        \\}}
        \\
    , .{
        entry.name,
        entry.version,
        desc_line,
        entry.license,
        deps,
    }) catch "";
}

fn platformPackageJson(alloc: std.mem.Allocator, entry: PackEntry, platform: Platform) []const u8 {
    const libc_line = if (platform.npmLibc()) |libc|
        std.fmt.allocPrint(alloc, "  \"libc\": [\"{s}\"],\n", .{libc}) catch ""
    else
        "";

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}/binding-{s}",
        \\  "version": "{s}",
        \\  "os": ["{s}"],
        \\  "cpu": ["{s}"],
        \\{s}  "main": "{s}.node",
        \\  "files": [
        \\    "{s}.node"
        \\  ]
        \\}}
        \\
    , .{
        entry.scope,
        platform.suffix(),
        entry.version,
        platform.npmOs(),
        platform.npmCpu(),
        libc_line,
        entry.name,
        entry.name,
    }) catch "";
}

fn indexJs(alloc: std.mem.Allocator, entry: PackEntry) []const u8 {
    return std.fmt.allocPrint(alloc,
        \\const {{ platform, arch }} = process;
        \\
        \\function isMusl() {{
        \\  try {{
        \\    const report = process.report.getReport();
        \\    const header = typeof report === 'string' ? JSON.parse(report).header : report.header;
        \\    return !header.glibcVersionRuntime;
        \\  }} catch {{
        \\    return false;
        \\  }}
        \\}}
        \\
        \\function loadBinding() {{
        \\  const libc = platform === 'linux' ? (isMusl() ? '-musl' : '-gnu') : '';
        \\  const suffix = `${{platform}}-${{arch}}${{libc}}`;
        \\
        \\  try {{
        \\    return require('{s}/binding-' + suffix + '/{s}.node');
        \\  }} catch (e) {{
        \\    throw new Error(
        \\      `Failed to load native binding for ${{platform}}-${{arch}}. ` +
        \\      `Tried: {s}/binding-${{suffix}}/{s}.node\n` +
        \\      `Error: ${{e.message}}`
        \\    );
        \\  }}
        \\}}
        \\
        \\module.exports = loadBinding();
        \\
    , .{ entry.scope, entry.name, entry.scope, entry.name }) catch "";
}
