# showcase

The kitchen-sink napi-zig example. Exercises every major capability:

- plain functions
- env-injected functions with allocator
- struct args with defaults
- enum args
- nested namespaces (`crypto.*`)
- classes (`Counter`)
- workers / Promises (`asyncFib`)
- raw mode for variadic args (`sum`)
- callbacks (`forEach`)

## Build & run

From this directory:

```sh
zig build
node -e "import('./showcase.js').then(({default: m}) => {
  console.log(m.add(2, 3));                       // 5
  console.log(m.greet('world'));                  // Hello, world!
  console.log(m.crypto.hash('hi'));               // sha256 hex
  const c = new m.Counter(10);
  console.log(c.increment(), c.addN(5), c.get()); // 11 16 16
  m.asyncFib(30).then(console.log);               // 832040
  m.forEach([1, 2, 3], (item, i) => console.log(i, item));
  console.log(m.sum(1, 2, 3, 4, 5));              // 15
})"
```

The auto-generated `showcase.d.ts` ships next to `showcase.js` — open it to see what TypeScript inferred from the Zig source.
