# napi-zig

Build [Node.js native addons](https://nodejs.org/api/n-api.html) in Zig. Cross-compile every platform from one machine. Publish to npm with one command.

```zig
const napi = @import("napi-zig");

comptime { napi.module(@This()); }

pub fn add(a: i32, b: i32) i32 {
    return a + b;
}
```

```js
import addon from "./my-addon.js";
addon.add(2, 3); // 5
```

## Quick start

```sh
npx napi-zig@latest new my-addon
```

```sh
cd my-addon
node test.mjs
```

That's it. You have a working native Node.js addon written in Zig.

## Documentation

Full guides, API reference, and the publish pipeline:

**[napi-zig.dev](https://napi-zig.dev)**

- [Introduction](https://napi-zig.dev/)
- [Quick start](https://napi-zig.dev/quick-start)
- [Functions, classes, and types](https://napi-zig.dev/functions)
- [Async (workers, threadsafe, promises)](https://napi-zig.dev/async/workers)
- [Cross-compiling and publishing](https://napi-zig.dev/cross-compiling)
- [API reference](https://napi-zig.dev/reference/env)

## License

MIT
