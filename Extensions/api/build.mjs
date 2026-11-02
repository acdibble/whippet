// Bundles the runtime Whippet loads into each extension's JavaScript context, with React in production mode, into
// WhippetCore's resources, and writes the type declarations extensions build against into dist/.
import { build } from "esbuild";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = fileURLToPath(new URL(".", import.meta.url));

await build({
  entryPoints: [`${root}src/runtime.ts`],
  outfile: `${root}../../Packages/WhippetCore/Sources/WhippetCore/Resources/ExtensionRuntime.js`,
  bundle: true,
  format: "iife",
  platform: "neutral",
  target: "safari18",
  minify: true,
  // Keeps React's licence notices.
  legalComments: "eof",
  define: { "process.env.NODE_ENV": '"production"' },
  mainFields: ["main"],
  logLevel: "info",
});

execFileSync(`${root}node_modules/.bin/tsc`, ["-p", `${root}tsconfig.json`], { stdio: "inherit" });
