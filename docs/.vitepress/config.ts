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
      { text: "Guide", link: "/guide/introduction", activeMatch: "/guide/" },
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
      "/guide/": [
        {
          text: "Introduction",
          items: [
            { text: "Introduction", link: "/guide/introduction" },
            { text: "Quick start", link: "/guide/quick-start" },
            { text: "Manual setup", link: "/guide/manual-setup" },
            { text: "Project layout", link: "/guide/project-layout" },
          ],
        },
        {
          text: "Writing addons",
          items: [
            { text: "Functions", link: "/guide/functions" },
            { text: "Namespaces", link: "/guide/namespaces" },
            { text: "Classes", link: "/guide/classes" },
            { text: "Type conversion", link: "/guide/type-conversion" },
            { text: "Memory model", link: "/guide/memory" },
            { text: "Errors", link: "/guide/errors" },
            { text: "Callbacks", link: "/guide/callbacks" },
          ],
        },
        {
          text: "Async",
          items: [
            { text: "Workers", link: "/guide/async/workers" },
            { text: "Threadsafe functions", link: "/guide/async/threadsafe" },
            { text: "Promises", link: "/guide/async/promises" },
          ],
        },
        {
          text: "Distribution",
          items: [
            { text: "TypeScript declarations", link: "/guide/typescript" },
            { text: "Cross-compiling", link: "/guide/cross-compiling" },
            { text: "Publishing to npm", link: "/guide/publishing" },
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
