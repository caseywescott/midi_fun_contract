// Build the Beast Sound JS library (offchain tooling and demos): one script per module, plus
// all modules concatenated.
//   node onchain/build-library.mjs
//
// Writes onchain/dist/modules/<name>.js (each registers into window.BeastSound.v1),
// onchain/dist/composer.js (all modules) and onchain/dist/modules.json. The onchain token_uri page
// is the TinySynth player (onchain/build.mjs); this library is for sites, games and demos that
// compose, transform or play Beast music in the browser (see onchain/lib/index.js).
import { build } from 'esbuild';
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { MODULES, VERSION, loadBuiltModules } from './modules.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const lib = here + 'lib/';
mkdirSync(here + 'dist/modules', { recursive: true });

const exportsOf = async (m) => Object.keys(await import(lib + m.file));

// Virtual modules shared inside each bundle:
//   bs-ns           the window.BeastSound / v1 namespace (one copy per module)
//   bs-guard:<name> fails fast, before anything runs, if a dependency is not loaded yet
//   bs-module:<dep> another module's exports, read from where that module registered them
function modulePlugin(self) {
  return {
    name: 'beast-sound-modules',
    setup(b) {
      b.onResolve({ filter: /^bs-(ns|guard:.*)$/ }, (args) => ({ path: args.path, namespace: 'bs' }));
      b.onResolve({ filter: /^\.\/[a-z_]+\.js$/ }, (args) => {
        if (!args.importer.startsWith(lib)) return undefined;
        const other = MODULES.find((m) => './' + m.file === args.path);
        if (!other || other.name === self.name) return undefined;
        return { path: 'bs-module:' + other.name, namespace: 'bs' };
      });
      b.onLoad({ filter: /.*/, namespace: 'bs' }, async (args) => {
        if (args.path === 'bs-ns') {
          return { contents: `export const B = window.BeastSound || (window.BeastSound = {});\nexport const v1 = B.v1 || (B.v1 = { version: ${JSON.stringify(VERSION)}, modules: [] });`, loader: 'js' };
        }
        if (args.path.startsWith('bs-guard:')) {
          const m = MODULES.find((x) => x.name === args.path.slice(9));
          return { contents: `import { v1 } from 'bs-ns';\nfor (const d of ${JSON.stringify(m.deps)}) if (!v1.modules.includes(d)) throw new Error('beast-sound: module ${m.name} needs module ' + d + ' loaded first');`, loader: 'js', resolveDir: lib };
        }
        const other = MODULES.find((x) => x.name === args.path.slice(10));
        const names = await exportsOf(other);
        return { contents: `import { B, v1 } from 'bs-ns';\nconst g = ${other.global};\n${names.map((n) => `export const ${n} = g.${n};`).join('\n')}`, loader: 'js', resolveDir: lib };
      });
    },
  };
}

for (const m of MODULES) {
  const names = await exportsOf(m);
  const entry = `import 'bs-guard:${m.name}';
import { B, v1 } from 'bs-ns';
import { ${names.join(', ')} } from ${JSON.stringify(lib + m.file)};
const m = { ${names.join(', ')} };
${m.register};
v1.modules.push(${JSON.stringify(m.name)});`;
  await build({
    stdin: { contents: entry, resolveDir: lib, loader: 'js' },
    bundle: true, minify: true, format: 'iife', charset: 'utf8', target: 'es2020', logLevel: 'error',
    outfile: here + `dist/modules/${m.name}.js`,
    plugins: [modulePlugin(m)],
  });
}

const modules = loadBuiltModules();
writeFileSync(here + 'dist/composer.js', modules.map((m) => m.js).join('\n'));
writeFileSync(here + 'dist/modules.json', JSON.stringify(modules.map((m, i) => ({ name: m.name, deps: MODULES[i].deps, js_bytes: m.js.length })), null, 1));
console.log(modules.map((m) => `${m.name} ${m.js.length} B`).join(' · '));
console.log(`all-in-one: ${modules.reduce((n, m) => n + m.js.length + 1, 0) - 1} B`);
