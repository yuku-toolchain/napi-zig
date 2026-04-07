import starlight from "@astrojs/starlight";
import { defineConfig } from "astro/config";

export default defineConfig({
  integrations: [
    starlight({
      title: "The simplest way to write cross-platform Node.js native addons in Zig",
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/yuku-toolchain/napi-zig",
        },
      ],
      customCss: ["./src/styles/index.css"],
      sidebar: [{ label: "Introduction", slug: "" }],
    }),
  ],
});
