import { defineConfig } from "vitepress";

export default defineConfig({
  title: "napi-zig",
  description:
    "Build Node.js native addons in Zig. Cross-compile every platform from one machine. Publish to npm with one command.",
  lang: "en-US",
  cleanUrls: true,
  lastUpdated: true,

  head: [
    ["meta", { name: "theme-color", content: "#f7a41d" }],
    ["meta", { property: "og:type", content: "website" }],
    ["meta", { property: "og:title", content: "napi-zig" }],
    [
      "meta",
      {
        property: "og:description",
        content: "Build Node.js native addons in Zig.",
      },
    ],
  ],

  themeConfig: {
    siteTitle: "napi-zig",

    nav: [
      { text: "Guide", link: "/", activeMatch: "^/(?!reference)" },
      { text: "Reference", link: "/reference/cli", activeMatch: "/reference/" },
      {
        text: "Resources",
        items: [
          {
            text: "Changelog",
            link: "https://github.com/yuku-toolchain/napi-zig/releases",
          },
          {
            text: "Issues",
            link: "https://github.com/yuku-toolchain/napi-zig/issues",
          },
          {
            text: "npm",
            link: "https://www.npmjs.com/package/napi-zig",
          },
        ],
      },
    ],

    sidebar: {
      "/": [
        {
          text: "Introduction",
          items: [
            { text: "Introduction", link: "/" },
            { text: "Quick start", link: "/quick-start" },
            { text: "Manual setup", link: "/manual-setup" },
            { text: "Project layout", link: "/project-layout" },
          ],
        },
        {
          text: "Writing addons",
          items: [
            { text: "Functions", link: "/functions" },
            { text: "Namespaces", link: "/namespaces" },
            { text: "Classes", link: "/classes" },
            { text: "Type conversion", link: "/type-conversion" },
            { text: "Memory model", link: "/memory" },
            { text: "Errors", link: "/errors" },
            { text: "Callbacks", link: "/callbacks" },
          ],
        },
        {
          text: "Async",
          items: [
            { text: "Workers", link: "/async/workers" },
            { text: "Threadsafe functions", link: "/async/threadsafe" },
            { text: "Promises", link: "/async/promises" },
          ],
        },
        {
          text: "Distribution",
          items: [
            { text: "TypeScript declarations", link: "/typescript" },
            { text: "Cross-compiling", link: "/cross-compiling" },
            { text: "Publishing to npm", link: "/publishing" },
          ],
        },
      ],
      "/reference/": [
        {
          text: "Reference",
          items: [
            { text: "CLI", link: "/reference/cli" },
            { text: "build.zig (addLib)", link: "/reference/build" },
          ],
        },
        {
          text: "API",
          items: [
            { text: "Env", link: "/reference/env" },
            { text: "Val", link: "/reference/val" },
            { text: "Callback", link: "/reference/callback" },
            { text: "ThreadsafeFn", link: "/reference/threadsafe-fn" },
            { text: "Ref", link: "/reference/ref" },
            { text: "Deferred", link: "/reference/deferred" },
            { text: "CallInfo", link: "/reference/call-info" },
            { text: "class", link: "/reference/class" },
            { text: "Error", link: "/reference/error" },
            { text: "dts", link: "/reference/dts" },
          ],
        },
      ],
    },

    socialLinks: [{ icon: "github", link: "https://github.com/yuku-toolchain/napi-zig" }],

    search: {
      provider: "local",
      options: {
        miniSearch: {
          searchOptions: {
            fuzzy: 0.2,
            prefix: true,
            boost: { title: 4, text: 2, titles: 1 },
          },
        },
      },
    },

    outline: {
      level: [2, 3],
      label: "On this page",
    },

    editLink: {
      pattern: "https://github.com/yuku-toolchain/napi-zig/edit/main/docs/:path",
      text: "Edit this page on GitHub",
    },

    lastUpdated: {
      text: "Updated",
      formatOptions: { dateStyle: "medium" },
    },

    docFooter: {
      prev: "Previous page",
      next: "Next page",
    },

    footer: {
      message: "Released under the MIT License.",
      copyright: `Copyright © ${new Date().getFullYear()} napi-zig contributors`,
    },
  },
});
