import { defineConfig } from "vite";
import { resolve } from "node:path";

// The site's bundle: the app's own cat engine and renderer, drawn on the home page (src/site/main.ts). Run it as
//   npx --no-install vite build --config vite.site.config.ts
// never `npm run build`, which builds the app. The output is docs/assets/cats.js and cats.css, committed because GitHub Pages serves files as they are;
// scripts/check-site.sh rebuilds them into a temporary folder (--outDir) and fails when they differ.
export default defineConfig({
  publicDir: false,
  // The engine plays sounds through core/sound.ts; the site has none, so the build swaps that one module for a stand-in with the same call.
  resolve: { alias: [{ find: /^\.\.\/core\/sound\.ts$/, replacement: resolve(__dirname, "src/site/silent.ts") }] },
  build: {
    outDir: resolve(__dirname, "../docs/assets"),
    emptyOutDir: false,
    target: "es2020",
    minify: "esbuild",
    sourcemap: false,
    cssCodeSplit: false,
    rollupOptions: {
      input: resolve(__dirname, "src/site/main.ts"),
      output: { format: "iife", entryFileNames: "cats.js", assetFileNames: "cats[extname]" },
    },
  },
});
