# CallInfo

Raw call info for variadic or dynamic-arity functions. Recognized by type as a function parameter; does not consume a JS argument.

```zig
pub fn sum(env: napi.Env, info: napi.CallInfo) !napi.Val {
    const args = try info.args(env, 16);
    const argc = try info.argCount(env);
    var total: f64 = 0;
    for (0..argc) |i| total += try args[i].to(env, f64);
    return env.toJs(total);
}
```

## Methods

| Method                           | Returns          | Purpose                                                               |
| -------------------------------- | ---------------- | --------------------------------------------------------------------- |
| `args(env, comptime max: usize)` | `![max]napi.Val` | Extract up to `max` arguments. Missing slots filled with `undefined`. |
| `argCount(env)`                  | `!usize`         | Number of arguments actually passed.                                  |
| `this(env)`                      | `!napi.Val`      | The `this` binding of the call.                                       |

`args` returns a fixed-size array; the size is comptime. Use `argCount` to know how many slots are real.

## When to use it

- Variadic functions like `sum(...nums)`.
- Functions whose argument types depend on runtime conditions (where you would convert each argument with `val.to(env, T)` based on its observed type).
- Reaching `this` from a function that is being called as a method on a JS object.

For everything else, prefer typed parameters; the bridge does the conversion for you and the result is shorter and clearer.
