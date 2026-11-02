// Builds an extension: bundles its src/index.tsx into the index.js Whippet loads, as CommonJS, leaving out React and
// @whippet/api, which Whippet supplies. Usage: node build-extension.mjs <extension folder> [--watch]
import { build, context } from "esbuild";
import { resolve } from "node:path";

const folder = resolve(process.argv[2] ?? ".");
const options = {
  entryPoints: [`${folder}/src/index.tsx`],
  outfile: `${folder}/index.js`,
  bundle: true,
  format: "cjs",
  platform: "neutral",
  target: "safari18",
  jsx: "automatic",
  external: ["react", "react/jsx-runtime", "@whippet/api"],
  logLevel: "info",
};

if (process.argv.includes("--watch")) {
  await (await context(options)).watch();
} else {
  await build(options);
}
