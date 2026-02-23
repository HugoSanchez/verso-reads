import { build } from "esbuild";

const entryPoints = ["notes-editor/index.ts"];
const outFile = "verso-reads/Resources/NotesEditor/tiptap.bundle.js";

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
