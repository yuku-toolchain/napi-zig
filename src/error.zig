const c = @import("c.zig");

pub const Error = error{
    InvalidArg,
    ObjectExpected,
    StringExpected,
    NameExpected,
    FunctionExpected,
    NumberExpected,
    BooleanExpected,
    ArrayExpected,
    GenericFailure,
    PendingException,
    Cancelled,
    EscapeCalledTwice,
    HandleScopeMismatch,
    CallbackScopeMismatch,
    QueueFull,
    Closing,
    BigintExpected,
    DateExpected,
    ArrayBufferExpected,
    DetachableArrayBufferExpected,
    WouldDeadlock,
    NoExternalBuffersAllowed,
    CannotRunJs,
    OutOfMemory,
};

pub fn check(status: c.napi_status) Error!void {
    return switch (status) {
        .ok => {},
        .invalid_arg => Error.InvalidArg,
        .object_expected => Error.ObjectExpected,
        .string_expected => Error.StringExpected,
        .name_expected => Error.NameExpected,
        .function_expected => Error.FunctionExpected,
        .number_expected => Error.NumberExpected,
        .boolean_expected => Error.BooleanExpected,
        .array_expected => Error.ArrayExpected,
        .generic_failure => Error.GenericFailure,
        .pending_exception => Error.PendingException,
        .cancelled => Error.Cancelled,
        .escape_called_twice => Error.EscapeCalledTwice,
        .handle_scope_mismatch => Error.HandleScopeMismatch,
        .callback_scope_mismatch => Error.CallbackScopeMismatch,
        .queue_full => Error.QueueFull,
        .closing => Error.Closing,
        .bigint_expected => Error.BigintExpected,
        .date_expected => Error.DateExpected,
        .arraybuffer_expected => Error.ArrayBufferExpected,
        .detachable_arraybuffer_expected => Error.DetachableArrayBufferExpected,
        .would_deadlock => Error.WouldDeadlock,
        .no_external_buffers_allowed => Error.NoExternalBuffersAllowed,
        .cannot_run_js => Error.CannotRunJs,
    };
}

const testing = @import("std").testing;

test "ok status returns void" {
    try check(.ok);
}

test "every non-ok status maps to a distinct error" {
    try testing.expectError(Error.InvalidArg, check(.invalid_arg));
    try testing.expectError(Error.StringExpected, check(.string_expected));
    try testing.expectError(Error.QueueFull, check(.queue_full));
    try testing.expectError(Error.PendingException, check(.pending_exception));
    try testing.expectError(Error.CannotRunJs, check(.cannot_run_js));
}
