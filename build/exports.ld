/* Linux/FreeBSD: limit exported symbols to the two N-API entry points.
 * Everything else (Zig stdlib, user code, etc.) becomes local. Keeps the
 * .node binary small and prevents accidental symbol collisions when
 * multiple addons are loaded into the same process. */
{
    global:
        napi_register_module_v1;
        node_api_module_get_api_version_v1;
    local:
        *;
};
