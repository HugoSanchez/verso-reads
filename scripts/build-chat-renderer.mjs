import { build } from "esbuild";

const entryPoints = ["chat-renderer/index.ts"];
const outFile = "verso-reads/Resources/ChatRenderer/chat.bundle.js";

await build({
  entryPoints,
  outfile: outFile,
  bundle: true,
  format: "iife",
  platform: "browser",
  target: ["es2019"],
  minify: false,
  sourcemap: false,
});

console.log(`Built ${outFile}`);
