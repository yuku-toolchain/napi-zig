//! runtime resolution of n-api symbols on windows.
//!
//! pe/coff binds imports to a module *name* at link time, so an import
//! library pointing at "node.exe" only loads when the host executable is
//! literally node.exe. it breaks under bun.exe, deno.exe, electron.exe,
//! or a renamed node. instead of importing, every extern fn in c.zig is
//! satisfied by a tiny trampoline that jumps through a pointer slot, and
//! the slots are filled at module registration via
//! GetProcAddress(GetModuleHandleW(null)), the same host-agnostic
//! resolution that node-gyp and napi-rs perform in their delay-load
//! hooks. all napi-capable hosts export the symbols from their
//! executable.

const std = @import("std");
const builtin = @import("builtin");
const c = @import("c.zig");

const emit = builtin.os.tag == .windows and builtin.output_mode == .Lib;

const slot_prefix = "__napi_zig_slot_";

/// every extern fn declared in c.zig, derived at comptime so the
/// trampolines can never drift from the bindings.
const symbol_names = blk: {
    @setEvalBranchQuota(50_000);
    var names: []const [:0]const u8 = &.{};
    for (@typeInfo(c).@"struct".decls) |d| {
        const v = @field(c, d.name);
        if (@TypeOf(v) == type) continue;
        if (@typeInfo(@TypeOf(v)) != .@"fn") continue;
        names = names ++ [_][:0]const u8{d.name};
    }
    break :blk names;
};

/// one pointer slot per symbol. a distinct generic instantiation gives
/// each slot its own global, exported under a stable name so the
/// trampoline assembly can reference it.
fn Slot(comptime name: [:0]const u8) type {
    return struct {
        comptime {
            _ = name;
        }
        var ptr: ?*const anyopaque = null;
    };
}

comptime {
    if (emit) {
        @setEvalBranchQuota(100_000);
        for (symbol_names) |name| {
            // hidden keeps the slots out of the dll export table.
            @export(&Slot(name).ptr, .{ .name = slot_prefix ++ name, .visibility = .hidden });
        }
        asm (trampolines());
    }
}

fn trampolines() []const u8 {
    var s: []const u8 = ".text\n";
    for (symbol_names) |name| {
        s = s ++ switch (builtin.cpu.arch) {
            .x86_64 => ".globl " ++ name ++ "\n" ++
                ".p2align 4\n" ++
                name ++ ":\n" ++
                "jmpq *" ++ slot_prefix ++ name ++ "(%rip)\n",
            .aarch64 => ".globl " ++ name ++ "\n" ++
                ".p2align 2\n" ++
                name ++ ":\n" ++
                "adrp x16, " ++ slot_prefix ++ name ++ "\n" ++
                "ldr x16, [x16, :lo12:" ++ slot_prefix ++ name ++ "]\n" ++
                "br x16\n",
            else => @compileError("napi-zig: unsupported windows architecture"),
        };
    }
    return s;
}

// called when the host runtime does not export a Node-API symbol the
// addon uses at runtime. @trap, not @panic: the panic machinery brings
// std.debug threadlocals into the addon, and zig's aarch64-windows
// codegen currently miscompiles TLS accesses to variables at a nonzero
// .tls$ offset (the SECREL high half receives the raw byte offset, so
// the access lands offset*4096 bytes past the TLS block). keeping
// napi-zig free of threadlocals keeps SmpAllocator's thread_index at
// offset 0, where every layout resolves correctly.
fn missingSymbol() callconv(.c) noreturn {
    @trap();
}

const HMODULE = std.os.windows.HMODULE;
extern "kernel32" fn GetModuleHandleW(module_name: ?[*:0]const u16) callconv(.winapi) ?HMODULE;
extern "kernel32" fn GetProcAddress(module: HMODULE, proc_name: [*:0]const u8) callconv(.winapi) ?*const anyopaque;

const State = enum(u8) { unresolved, busy, done };
var state = std.atomic.Value(State).init(.unresolved);

/// fill every slot from the host executable's export table. called at
/// module registration, before any napi function can be reached. envs
/// can register concurrently (worker threads), so exactly one caller
/// resolves while the rest wait.
pub fn init() void {
    if (comptime !emit) return;
    while (true) {
        switch (state.load(.acquire)) {
            .done => return,
            .unresolved => {
                if (state.cmpxchgWeak(.unresolved, .busy, .acquire, .monotonic) == null) {
                    resolve();
                    state.store(.done, .release);
                    return;
                }
            },
            .busy => std.atomic.spinLoopHint(),
        }
    }
}

fn resolve() void {
    const host = GetModuleHandleW(null) orelse unreachable; // current process, cannot fail
    const missing: *const anyopaque = @ptrCast(&missingSymbol);

    inline for (symbol_names) |name| {
        Slot(name).ptr = GetProcAddress(host, name.ptr) orelse missing;
    }
}
