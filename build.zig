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
    /// strip debug info and the symbol table from the addon. defaults
    /// to true for non-debug builds, where it cuts the binary size by
    /// several times on ELF targets. the dynamic symbols Node loads
    /// through are always kept. on aarch64-windows the default is false:
    /// stripping makes the compiler emit section-relative TLS
    /// relocations, which zig currently resolves incorrectly for any
    /// threadlocal at a nonzero offset (the access lands offset*4096
    /// bytes past the thread's TLS block and corrupts or crashes).
    strip: ?bool = null,
};

// see the `strip` doc comment. keep symbols on aarch64-windows so TLS
// relocations stay symbol-relative until the zig codegen bug is fixed.
fn defaultStrip(target: std.Build.ResolvedTarget, non_debug: bool) bool {
    if (target.result.os.tag == .windows and target.result.cpu.arch == .aarch64) return false;
    return non_debug;
}

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

    const lib_mod = b.createModule(.{
        .root_source_file = options.root,
        .target = options.target,
        .optimize = options.optimize,
        .strip = options.strip orelse defaultStrip(options.target, options.optimize != .Debug),
    });
    lib_mod.addImport("napi-zig", napi_module);
    for (options.imports) |imp| lib_mod.addImport(imp.name, imp.module);

    const lib = b.addLibrary(.{
        .name = options.name,
        .root_module = lib_mod,
        .linkage = .dynamic,
    });
    configureLinkerFlags(b, lib, options.target, napi_dep);

    const install = b.addInstallArtifact(lib, .{
        .dest_dir = .{ .override = .lib },
        .dest_sub_path = b.fmt("{s}.node", .{options.name}),
    });
    b.getInstallStep().dependOn(&install.step);

    if (options.npm) |npm| {
        installDts(b, napi_dep, napi_module, options, npm.dts, .lib, b.fmt("{s}.d.ts", .{options.name}));
    }

    // npm release mode (cross-compile and scaffold)
    if (options.npm) |npm| {
        if (npmFlag(b)) {
            // read before the filter so -Dnpm-host stays registered even when
            // every addon is filtered out
            const host_only = npmHostOnly(b);
            if (npmSelected(b, options.name)) {
                addNpmRelease(b, napi_dep, napi_module, options, npm, host_only);
            }
        }
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

// duplicate-declaration guard like npmFlag, the first addLib call declares the
// option and later calls read the cached input
fn npmHostOnly(b: *std.Build) bool {
    if (b.available_options_map.contains("npm-host")) {
        const opt_ptr = b.user_input_options.getPtr("npm-host") orelse return false;
        opt_ptr.used = true;
        return switch (opt_ptr.value) {
            .flag => true,
            .scalar => |s| std.mem.eql(u8, s, "true"),
            else => false,
        };
    }
    return b.option(bool, "npm-host", "Cross-compile only the host platform") orelse false;
}

// Zig bundles no bionic libc, so android compiles need explicit libc paths
// (`zig libc` format): crt objects plus libc/libm/libdl stubs. An explicit
// -Dlibc-file wins (the top-level `zig build --libc` flag does not reach
// child compilations, hence the dedicated option); without it, the Android
// NDK is located through the usual environment variables and a paths file
// pointing at its sysroot is generated, which is enough for `-Dnpm` release
// builds on stock GitHub runners. Non-android targets keep Zig's bundled
// libc behavior.
fn applyLibcFile(b: *std.Build, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget) void {
    // Read (and thereby declare) the option on every configure so it shows in
    // `zig build --help` and is accepted on non-android builds; only android
    // compiles consume it.
    const explicit = libcFilePath(b);
    if (!target.result.abi.isAndroid()) return;
    if (explicit) |p| {
        lib.setLibCFile(.{ .cwd_relative = p });
        return;
    }
    if (ndkLibcFile(b, target)) |generated| {
        lib.setLibCFile(generated);
        return;
    }
    // A full cross build drops android before it gets here (see
    // buildablePlatforms), so this only fires when android was asked for on
    // its own. Without libc paths the link fails later with a hint about the
    // top-level --libc flag, which cannot help here. Fail this compile early
    // with the two remedies that do.
    const fail = b.addFail(b.fmt(
        "{s}: android targets need bionic libc paths; pass -Dlibc-file=<file> (see `zig libc`) or set ANDROID_NDK_ROOT to an Android NDK install",
        .{lib.name},
    ));
    lib.step.dependOn(&fail.step);
}

// True when an android compile can find bionic libc paths in this
// environment, either from an explicit -Dlibc-file or from an NDK the build
// can read.
fn androidLibcAvailable(b: *std.Build) bool {
    if (libcFilePath(b) != null) return true;
    return ndkSysroot(b) != null;
}

// Locates the sysroot of an Android NDK advertised in the environment.
// Layout (NDK r19+): <ndk>/toolchains/llvm/prebuilt/<host>/sysroot. Returns
// null when no NDK is advertised or the install does not have that layout,
// which is what makes android skippable rather than fatal.
fn ndkSysroot(b: *std.Build) ?[]const u8 {
    const ndk = for ([_][]const u8{
        "ANDROID_NDK_ROOT", "ANDROID_NDK_HOME", "ANDROID_NDK_LATEST_HOME", "ANDROID_NDK",
    }) |name| {
        if (b.graph.environ_map.get(name)) |value| {
            if (value.len != 0) break value;
        }
    } else return null;

    // An NDK install ships exactly one host dir under toolchains/llvm/prebuilt
    // (macs get a universal darwin-x86_64); enumerate it instead of hardcoding
    // host names so unofficial ports (e.g. linux-aarch64 NDK builds used from
    // Termux) work too.
    const io = b.graph.io;
    const prebuilt = b.pathJoin(&.{ ndk, "toolchains", "llvm", "prebuilt" });
    var prebuilt_dir = std.Io.Dir.openDirAbsolute(io, prebuilt, .{ .iterate = true }) catch return null;
    defer prebuilt_dir.close(io);
    var it = prebuilt_dir.iterate();
    while (it.next(io) catch null) |entry| {
        if (entry.kind == .directory) {
            return b.pathJoin(&.{ prebuilt, b.dupe(entry.name), "sysroot" });
        }
    }
    return null;
}

// Synthesizes a `zig libc` paths file from an Android NDK install: headers in
// usr/include (+ a per-triple subdir) and crt objects plus libc/libm/libdl
// stubs in usr/lib/<triple>/<api>. Returns null when no NDK is advertised in
// the environment; a wrong NDK path surfaces as a link error naming the
// missing file, which is actionable enough.
fn ndkLibcFile(b: *std.Build, target: std.Build.ResolvedTarget) ?std.Build.LazyPath {
    const sysroot = ndkSysroot(b) orelse return null;
    const triple = switch (target.result.cpu.arch) {
        .aarch64 => "aarch64-linux-android",
        .x86_64 => "x86_64-linux-android",
        .x86 => "i686-linux-android",
        .arm, .thumb => "arm-linux-androideabi",
        else => return null,
    };
    const api = target.result.os.version_range.linux.android;
    const content = b.fmt(
        \\include_dir={s}/usr/include
        \\sys_include_dir={s}/usr/include/{s}
        \\crt_dir={s}/usr/lib/{s}/{d}
        \\msvc_lib_dir=
        \\kernel32_lib_dir=
        \\gcc_dir=
        \\
    , .{ sysroot, sysroot, triple, sysroot, triple, api });
    return b.addWriteFiles().add(b.fmt("libc-{s}-{d}.txt", .{ triple, api }), content);
}

// duplicate-declaration guard like npmFlag, the first addLib call declares the
// option and later calls read the cached input
fn libcFilePath(b: *std.Build) ?[]const u8 {
    if (b.available_options_map.contains("libc-file")) {
        const opt_ptr = b.user_input_options.getPtr("libc-file") orelse return null;
        opt_ptr.used = true;
        return switch (opt_ptr.value) {
            .scalar => |s| s,
            else => null,
        };
    }
    return b.option([]const u8, "libc-file", "libc paths file applied to android addon compiles (see `zig libc`)");
}

// Why a platform in `.npm.platforms` cannot be compiled here, or null when it
// can. Everything Zig links on its own is always buildable, so only android,
// which depends on bionic files this machine may lack, can answer non-null.
fn skipReason(b: *std.Build, platform: Platform) ?[]const u8 {
    if (platform.isAndroid() and !androidLibcAvailable(b)) {
        return "no Android NDK found (set ANDROID_NDK_ROOT) and no -Dlibc-file given";
    }
    return null;
}

// addLib runs once per addon, so without this the same skip would be reported
// once per addon in a multi-addon repo.
var skip_warned = std.EnumSet(Platform).initEmpty();

// Drops platforms this machine cannot compile so a full cross build stays
// usable (11 of 12 platforms beats a failed release build), and warns for each
// one. When every requested platform is unbuildable the list is returned
// untouched. Such a build was narrowed to that platform on purpose, so it
// fails with the actionable message instead of quietly producing nothing.
fn buildablePlatforms(b: *std.Build, requested: []const Platform) []const Platform {
    var count: usize = 0;
    for (requested) |platform| {
        if (skipReason(b, platform) == null) count += 1;
    }
    if (count == requested.len or count == 0) return requested;

    const kept = b.allocator.alloc(Platform, count) catch @panic("OOM");
    var i: usize = 0;
    for (requested) |platform| {
        const reason = skipReason(b, platform) orelse {
            kept[i] = platform;
            i += 1;
            continue;
        };
        if (skip_warned.contains(platform)) continue;
        skip_warned.insert(platform);
        // the CLI parses this line to label the platform in its target grid
        std.log.warn("napi-zig: skipping {s}: {s}", .{ platform.suffix(), reason });
    }
    return kept;
}

fn npmSelected(b: *std.Build, name: []const u8) bool {
    const raw = npmOnlyRaw(b) orelse return true;
    if (raw.len == 0) return true;
    var it = std.mem.splitScalar(u8, raw, ',');
    while (it.next()) |part| {
        const trimmed = std.mem.trim(u8, part, " ");
        if (trimmed.len == 0) continue;
        if (std.mem.eql(u8, trimmed, name)) return true;
    }
    return false;
}

fn npmOnlyRaw(b: *std.Build) ?[]const u8 {
    if (b.available_options_map.contains("npm-only")) {
        const opt_ptr = b.user_input_options.getPtr("npm-only") orelse return null;
        opt_ptr.used = true;
        return switch (opt_ptr.value) {
            .scalar => |s| s,
            else => null,
        };
    }
    return b.option([]const u8, "npm-only", "Comma-separated addon names to build (default: all)");
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
    host_only: bool,
) void {
    const wf = b.addWriteFiles();

    _ = wf.add(
        b.fmt("npm/{s}/binding.js", .{options.name}),
        bindingJs(b.allocator, options.name, npm.scope),
    );
    // always lists every platform so a later full build and publish stay complete
    _ = wf.add(
        b.fmt("npm/{s}/package.json", .{options.name}),
        rootPackageJson(b.allocator, options.name, npm),
    );

    // host_only compiles just the host binding for fast local iteration
    const requested = if (host_only) blk: {
        const host = Platform.fromTarget(b.graph.host.result) orelse
            std.debug.panic("napi-zig: host platform is not in the npm platform list; cannot use --current", .{});
        const one = b.allocator.alloc(Platform, 1) catch @panic("OOM");
        one[0] = host;
        break :blk @as([]const Platform, one);
    } else npm.platforms;

    // the main package.json above still lists every platform in
    // optionalDependencies. only what this machine can compile is scaffolded
    // and built here.
    const platforms = buildablePlatforms(b, requested);

    for (platforms) |platform| {
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

    // cross-compile a .node for each platform.
    for (platforms) |platform| {
        const target = b.resolveTargetQuery(platform.zigTarget());

        const lib_mod = b.createModule(.{
            .root_source_file = options.root,
            .target = target,
            .optimize = .ReleaseFast,
            .strip = options.strip orelse defaultStrip(target, true),
        });
        lib_mod.addImport("napi-zig", napi_module);
        for (options.imports) |imp| lib_mod.addImport(imp.name, imp.module);

        const lib = b.addLibrary(.{
            .name = options.name,
            .root_module = lib_mod,
            .linkage = .dynamic,
        });
        configureLinkerFlags(b, lib, target, napi_dep);

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

fn configureLinkerFlags(b: *std.Build, lib: *std.Build.Step.Compile, target: std.Build.ResolvedTarget, napi_dep: *std.Build.Dependency) void {
    applyLibcFile(b, lib, target);
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
        // windows needs no import library: n-api symbols are satisfied by
        // trampolines (src/win_napi.zig) resolved at load time from the
        // host executable, whatever its name (node, bun, deno, electron).
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
        \\  "optionalDependencies": {{
        \\{s}  }}
        \\}}
        \\
    , .{ name, desc_line, npm.license, repo_line, deps }) catch "";
}

fn platformPackageJson(alloc: std.mem.Allocator, name: []const u8, npm: NpmConfig, platform: Platform) []const u8 {
    const libc_line = if (platform.npmLibc()) |libc|
        std.fmt.allocPrint(alloc, "  \"libc\": [\"{s}\"],\n", .{libc}) catch ""
    else
        "";

    const repo_line = repositoryLine(alloc, npm.repository, 2);

    return std.fmt.allocPrint(alloc,
        \\{{
        \\  "name": "{s}/binding-{s}",
        \\  "version": "0.0.0",
        \\  "license": "{s}",
        \\  "os": ["{s}"],
        \\  "cpu": ["{s}"],
        \\{s}{s}  "main": "{s}.node",
        \\  "files": [
        \\    "{s}.node"
        \\  ]
        \\}}
        \\
    , .{
        npm.scope,        platform.suffix(), npm.license,
        platform.npmOs(), platform.npmCpu(), libc_line,
        repo_line,        name,              name,
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
        \\let binding;
        \\
        \\export function load() {{
        \\  if (binding === undefined) binding = loadBinding();
        \\  return binding;
        \\}}
        \\
    , .{ scope, name, scope, name }) catch "";
}
