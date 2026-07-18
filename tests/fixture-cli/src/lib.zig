const napi = @import("napi-zig");

comptime {
    napi.module(@This());
}

// multiple threadlocals at nonzero .tls offsets: regression tripwire for
// the aarch64-windows TLS relocation bug (miscompiled section-relative
// SECREL when stripped). the cross-install windows-arm64 job executes
// this through add().
threadlocal var tls_a: u32 = 0;
threadlocal var tls_b: u32 = 0;
threadlocal var tls_c: u32 = 0;

pub fn add(a: i32, b: i32) i32 {
    tls_a +%= 1;
    tls_b +%= 2;
    tls_c = tls_a +% tls_b;
    if (tls_c == 0xdeadbeef) return -1;
    return a + b;
}
