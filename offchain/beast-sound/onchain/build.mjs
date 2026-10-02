// Build the onchain library: one script per module, the all-in-one blob, and the Cairo data.
//   node onchain/build.mjs
//
// Writes:
//   onchain/dist/modules/<name>.js       each module, registering into window.BeastSound.v1
//   onchain/dist/composer.js             all modules concatenated (one file for sites that want it)
//   onchain/dist/stored.b64              HEAD ++ every module segment (what token_uri splices in)
//   onchain/cairo/src/page_data.cairo    HEAD, kept by the page contract
//   onchain/cairo/src/modules.cairo      one contract per module, each storing its own segment
import { build } from 'esbuild';
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { MODULES, PAGES, VERSION, loadBuiltModules } from './modules.mjs';
import { storedSegments } from './page.js';

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
const segs = storedSegments(modules);
const inputSegs = storedSegments(loadBuiltModules(PAGES.inputs));
writeFileSync(here + 'dist/stored.b64', inputSegs.head + inputSegs.modules.map((m) => m.segment).join(''));
// The notes page (chain-composed felts): only the modules it needs.
const noteSegs = storedSegments(loadBuiltModules(PAGES.notes));
writeFileSync(here + 'dist/stored-notes.b64', noteSegs.head + noteSegs.modules.map((m) => m.segment).join(''));
writeFileSync(here + 'dist/modules.json', JSON.stringify(modules.map((m, i) => ({ name: m.name, deps: MODULES[i].deps, js_bytes: m.js.length, segment_chars: segs.modules[i].segment.length })), null, 1));

// ── Cairo ──────────────────────────────────────────────────────────
// A segment is stored as felt constants (31-byte words) and rebuilt by deserializing, ~5x cheaper
// than appending word by word.
function feltsFn(fnName, text, doc) {
  const bytes = Buffer.from(text, 'ascii');
  const words = [];
  for (let i = 0; i + 31 <= bytes.length; i += 31) words.push('0x' + bytes.subarray(i, i + 31).toString('hex'));
  const rest = bytes.subarray(words.length * 31);
  const PER_FN = 400; // keep each generated function small for the compiler
  const parts = [];
  for (let i = 0; i < words.length; i += PER_FN) parts.push(words.slice(i, i + PER_FN));
  return { felts: words.length + 3, code: `${doc}
pub fn ${fnName}() -> ByteArray {
    let mut felts: Array<felt252> = array![${words.length}];
${parts.map((_, i) => `    felts.append_span(${fnName}_${i}());`).join('\n')}
    felts.append(${rest.length ? '0x' + rest.toString('hex') : '0'});
    felts.append(${rest.length});
    let mut span = felts.span();
    Serde::deserialize(ref span).unwrap()
}
${parts.map((p, i) => `
fn ${fnName}_${i}() -> Span<felt252> {
    array![
${p.map((w) => `        ${w},`).join('\n')}
    ]
        .span()
}`).join('\n')}
` };
}

const head = feltsFn('head_segment', segs.head, `/// base64('"animation_url":"data:text/html;base64,' ++ base64(page head)): ${segs.head.length} characters.`);
writeFileSync(here + 'cairo/src/page_data.cairo', `// Generated by onchain/build.mjs. Do not edit.
//
// The page head segment, kept by BeastSoundPage. The library itself lives in the module contracts
// (modules.cairo); token_uri splices HEAD ++ each module's segment.
${head.code}`);

const pascal = (s) => s[0].toUpperCase() + s.slice(1);
let report = [`head: ${segs.head.length} chars, ${head.felts} felts`];
const mods = modules.map((m, i) => {
  const f = feltsFn('segment', segs.modules[i].segment, `/// base64(base64(<script>${m.name} module</script>)): ${m.js.length} bytes of JavaScript.`);
  report.push(`${m.name}: ${m.js.length} B js, ${f.felts} felts`);
  return `
/// Module \`${m.name}\`${MODULES[i].deps.length ? ` (needs ${MODULES[i].deps.join(', ')})` : ''}.
pub mod ${m.name} {${f.code.replace(/\n/g, '\n    ').replace(/\n    \n/g, '\n\n')}
    #[starknet::contract]
    pub mod BeastSoundModule${pascal(m.name)} {
        #[storage]
        struct Storage {}

        #[abi(embed_v0)]
        impl ModuleImpl of crate::IBeastSoundModule<ContractState> {
            fn name(self: @ContractState) -> felt252 {
                '${m.name}'
            }

            fn segment(self: @ContractState) -> ByteArray {
                super::segment()
            }
        }
    }
}`;
});
writeFileSync(here + 'cairo/src/modules.cairo', `// Generated by onchain/build.mjs. Do not edit.
//
// The Beast Sound library (${VERSION}), one contract per module. Each stores its module's segment,
// base64(base64(<script>…</script>)), in code. Load order: ${MODULES.map((m) => m.name).join(', ')}.

pub const MODULE_COUNT: u32 = ${MODULES.length};

/// The inputs page's module segments in load order (${PAGES.inputs.join(', ')}): what
/// BeastSoundPage fetches when deployed with that list. For tests and previews.
pub fn all_segments() -> ByteArray {
    let mut out: ByteArray = Default::default();
${PAGES.inputs.map((n) => `    out.append(@${n}::segment());`).join('\n')}
    out
}
${mods.join('\n')}
`);
console.log(report.join('\n'));
console.log(`all-in-one: ${modules.reduce((n, m) => n + m.js.length + 1, 0) - 1} B`);
console.log(`notes page (${PAGES.notes.join(', ')}): ${loadBuiltModules(PAGES.notes).reduce((n, m) => n + m.js.length, 0)} B`);
