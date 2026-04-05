pub const napi_env = *opaque {};

pub const napi_value = *opaque {};

pub const napi_ref = *opaque {};

pub const napi_callback_info = *opaque {};

pub const napi_deferred = *opaque {};

pub const napi_callback = *const fn (napi_env, napi_callback_info) callconv(.c) ?napi_value;

pub const napi_finalize = *const fn (napi_env, ?*anyopaque, ?*anyopaque) callconv(.c) void;

pub const napi_status = enum(c_int) {
    ok = 0,
    invalid_arg = 1,
    object_expected = 2,
    string_expected = 3,
    name_expected = 4,
    function_expected = 5,
    number_expected = 6,
    boolean_expected = 7,
    array_expected = 8,
    generic_failure = 9,
    pending_exception = 10,
    cancelled = 11,
    escape_called_twice = 12,
    handle_scope_mismatch = 13,
    callback_scope_mismatch = 14,
    queue_full = 15,
    closing = 16,
    bigint_expected = 17,
    date_expected = 18,
    arraybuffer_expected = 19,
    detachable_arraybuffer_expected = 20,
    would_deadlock = 21,
    no_external_buffers_allowed = 22,
    cannot_run_js = 23,
};

pub const napi_valuetype = enum(c_int) {
    undefined = 0,
    null = 1,
    boolean = 2,
    number = 3,
    string = 4,
    symbol = 5,
    object = 6,
    function = 7,
    external = 8,
    bigint = 9,
};

pub const napi_typedarray_type = enum(c_int) {
    int8_array = 0,
    uint8_array = 1,
    uint8_clamped_array = 2,
    int16_array = 3,
    uint16_array = 4,
    int32_array = 5,
    uint32_array = 6,
    float32_array = 7,
    float64_array = 8,
    bigint64_array = 9,
    biguint64_array = 10,
};

// sentinel value meaning "compute the length automatically from the null terminator".
pub const NAPI_AUTO_LENGTH: usize = @as(usize, @bitCast(@as(isize, -1)));

pub extern fn napi_get_cb_info(env: napi_env, cbinfo: napi_callback_info, argc: *usize, argv: ?[*]napi_value, this_arg: ?*napi_value, data: ?*?*anyopaque) napi_status;

pub extern fn napi_throw(env: napi_env, @"error": napi_value) napi_status;
pub extern fn napi_throw_error(env: napi_env, code: ?[*:0]const u8, msg: [*:0]const u8) napi_status;
pub extern fn napi_throw_type_error(env: napi_env, code: ?[*:0]const u8, msg: [*:0]const u8) napi_status;
pub extern fn napi_throw_range_error(env: napi_env, code: ?[*:0]const u8, msg: [*:0]const u8) napi_status;
pub extern fn napi_is_exception_pending(env: napi_env, result: *bool) napi_status;


pub extern fn napi_create_object(env: napi_env, result: *napi_value) napi_status;
pub extern fn napi_set_property(env: napi_env, object: napi_value, key: napi_value, value: napi_value) napi_status;
pub extern fn napi_get_property(env: napi_env, object: napi_value, key: napi_value, result: *napi_value) napi_status;
pub extern fn napi_set_named_property(env: napi_env, object: napi_value, utf8name: [*:0]const u8, value: napi_value) napi_status;
pub extern fn napi_get_named_property(env: napi_env, object: napi_value, utf8name: [*:0]const u8, result: *napi_value) napi_status;
pub extern fn napi_has_named_property(env: napi_env, object: napi_value, utf8name: [*:0]const u8, result: *bool) napi_status;


pub extern fn napi_create_array(env: napi_env, result: *napi_value) napi_status;
pub extern fn napi_create_array_with_length(env: napi_env, length: usize, result: *napi_value) napi_status;
pub extern fn napi_is_array(env: napi_env, value: napi_value, result: *bool) napi_status;
pub extern fn napi_get_array_length(env: napi_env, value: napi_value, result: *u32) napi_status;
pub extern fn napi_set_element(env: napi_env, object: napi_value, index: u32, value: napi_value) napi_status;
pub extern fn napi_get_element(env: napi_env, object: napi_value, index: u32, result: *napi_value) napi_status;


pub extern fn napi_create_string_utf8(env: napi_env, str: [*]const u8, length: usize, result: *napi_value) napi_status;
pub extern fn napi_get_value_string_utf8(env: napi_env, value: napi_value, buf: ?[*]u8, bufsize: usize, result: ?*usize) napi_status;


pub extern fn napi_create_int32(env: napi_env, value: i32, result: *napi_value) napi_status;
pub extern fn napi_create_uint32(env: napi_env, value: u32, result: *napi_value) napi_status;
pub extern fn napi_create_int64(env: napi_env, value: i64, result: *napi_value) napi_status;
pub extern fn napi_create_double(env: napi_env, value: f64, result: *napi_value) napi_status;
pub extern fn napi_get_value_int32(env: napi_env, value: napi_value, result: *i32) napi_status;
pub extern fn napi_get_value_uint32(env: napi_env, value: napi_value, result: *u32) napi_status;
pub extern fn napi_get_value_int64(env: napi_env, value: napi_value, result: *i64) napi_status;
pub extern fn napi_get_value_double(env: napi_env, value: napi_value, result: *f64) napi_status;


pub extern fn napi_get_boolean(env: napi_env, value: bool, result: *napi_value) napi_status;
pub extern fn napi_get_value_bool(env: napi_env, value: napi_value, result: *bool) napi_status;


pub extern fn napi_get_null(env: napi_env, result: *napi_value) napi_status;
pub extern fn napi_get_undefined(env: napi_env, result: *napi_value) napi_status;
pub extern fn napi_get_global(env: napi_env, result: *napi_value) napi_status;


pub extern fn napi_typeof(env: napi_env, value: napi_value, result: *napi_valuetype) napi_status;


pub extern fn napi_create_function(env: napi_env, utf8name: ?[*:0]const u8, length: usize, cb: napi_callback, data: ?*anyopaque, result: *napi_value) napi_status;
pub extern fn napi_call_function(env: napi_env, recv: napi_value, func: napi_value, argc: usize, argv: ?[*]const napi_value, result: *napi_value) napi_status;


pub extern fn napi_create_arraybuffer(env: napi_env, byte_length: usize, data: *?*anyopaque, result: *napi_value) napi_status;
pub extern fn napi_create_external_arraybuffer(env: napi_env, external_data: ?*anyopaque, byte_length: usize, finalize_cb: ?napi_finalize, finalize_hint: ?*anyopaque, result: *napi_value) napi_status;
pub extern fn napi_get_arraybuffer_info(env: napi_env, arraybuffer: napi_value, data: ?*?*anyopaque, byte_length: ?*usize) napi_status;
pub extern fn napi_is_arraybuffer(env: napi_env, value: napi_value, result: *bool) napi_status;
pub extern fn napi_create_typedarray(env: napi_env, @"type": napi_typedarray_type, length: usize, arraybuffer: napi_value, byte_offset: usize, result: *napi_value) napi_status;
pub extern fn napi_is_typedarray(env: napi_env, value: napi_value, result: *bool) napi_status;
pub extern fn napi_create_buffer(env: napi_env, length: usize, data: *?*anyopaque, result: *napi_value) napi_status;
pub extern fn napi_is_buffer(env: napi_env, value: napi_value, result: *bool) napi_status;
pub extern fn napi_get_buffer_info(env: napi_env, value: napi_value, data: *?*anyopaque, length: *usize) napi_status;


pub extern fn napi_create_bigint_int64(env: napi_env, value: i64, result: *napi_value) napi_status;
pub extern fn napi_create_bigint_uint64(env: napi_env, value: u64, result: *napi_value) napi_status;
pub extern fn napi_get_value_bigint_int64(env: napi_env, value: napi_value, result: *i64, lossless: *bool) napi_status;
pub extern fn napi_get_value_bigint_uint64(env: napi_env, value: napi_value, result: *u64, lossless: *bool) napi_status;


pub extern fn napi_create_reference(env: napi_env, value: napi_value, initial_refcount: u32, result: *napi_ref) napi_status;
pub extern fn napi_delete_reference(env: napi_env, ref: napi_ref) napi_status;
pub extern fn napi_get_reference_value(env: napi_env, ref: napi_ref, result: *napi_value) napi_status;


pub extern fn napi_get_version(env: napi_env, result: *u32) napi_status;


pub extern fn napi_create_promise(env: napi_env, deferred: *napi_deferred, promise: *napi_value) napi_status;
pub extern fn napi_resolve_deferred(env: napi_env, deferred: napi_deferred, resolution: napi_value) napi_status;
pub extern fn napi_reject_deferred(env: napi_env, deferred: napi_deferred, rejection: napi_value) napi_status;


pub const napi_async_work = *opaque {};

pub const napi_async_execute_callback = *const fn (napi_env, ?*anyopaque) callconv(.c) void;

pub const napi_async_complete_callback = *const fn (napi_env, napi_status, ?*anyopaque) callconv(.c) void;

pub extern fn napi_create_async_work(env: napi_env, async_resource: ?napi_value, async_resource_name: napi_value, execute: napi_async_execute_callback, complete: napi_async_complete_callback, data: ?*anyopaque, result: *napi_async_work) napi_status;
pub extern fn napi_delete_async_work(env: napi_env, work: napi_async_work) napi_status;
pub extern fn napi_queue_async_work(env: napi_env, work: napi_async_work) napi_status;


pub const napi_threadsafe_function = *opaque {};

pub const napi_threadsafe_function_release_mode = enum(c_int) {
    release = 0,
    abort = 1,
};

pub const napi_threadsafe_function_call_mode = enum(c_int) {
    non_blocking = 0,
    blocking = 1,
};

pub const napi_threadsafe_function_call_js = *const fn (napi_env, napi_value, ?*anyopaque, ?*anyopaque) callconv(.c) void;

pub extern fn napi_create_threadsafe_function(env: napi_env, func: ?napi_value, async_resource: ?napi_value, async_resource_name: napi_value, max_queue_size: usize, initial_thread_count: usize, thread_finalize_data: ?*anyopaque, thread_finalize_cb: ?napi_finalize, context: ?*anyopaque, call_js_cb: ?napi_threadsafe_function_call_js, result: *napi_threadsafe_function) napi_status;
pub extern fn napi_call_threadsafe_function(func: napi_threadsafe_function, data: ?*anyopaque, is_blocking: napi_threadsafe_function_call_mode) napi_status;
pub extern fn napi_release_threadsafe_function(func: napi_threadsafe_function, mode: napi_threadsafe_function_release_mode) napi_status;
pub extern fn napi_acquire_threadsafe_function(func: napi_threadsafe_function) napi_status;
pub extern fn napi_ref_threadsafe_function(env: napi_env, func: napi_threadsafe_function) napi_status;
pub extern fn napi_unref_threadsafe_function(env: napi_env, func: napi_threadsafe_function) napi_status;
