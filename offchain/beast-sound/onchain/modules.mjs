// The Beast Sound library's onchain modules, in load order. Each is built as its own script
// (dist/modules/<name>.js), stored in its own contract, and registers into window.BeastSound.v1.
// A module finds its dependencies there, so any subset loads in dependency order with no copies.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export const VERSION = 'beast-sound/engine-v1';

// file: the lib/ source; deps: modules that must load first;
// global: how other modules reach this one's exports; register: how it attaches itself.
export const MODULES = [
  { name: 'core', file: 'core.js', deps: [], global: 'v1.core', register: 'v1.core = m' },
  { name: 'beast', file: 'beast.js', deps: ['core'], global: 'v1.beast', register: 'v1.beast = m' },
  { name: 'music', file: 'music.js', deps: ['core'], global: 'v1.music', register: 'v1.music = m' },
  { name: 'midi', file: 'midi.js', deps: [], global: 'v1.midi', register: 'v1.midi = m' },
  { name: 'synth', file: 'synth.js', deps: [], global: 'v1.synth', register: 'v1.synth = m' },
  { name: 'play', file: 'player.js', deps: ['synth'], global: '{ play: v1.play, context: v1.context }', register: 'v1.play = m.play; v1.context = m.context' },
  { name: 'fx', file: 'fx.js', deps: [], global: 'v1.fx', register: 'v1.fx = m' },
  { name: 'api', file: 'index.js', deps: ['beast', 'music', 'midi', 'play'], global: '{ compose: v1.compose, fromInputs: v1.fromInputs, flat: B }', register: 'v1.compose = m.compose; v1.fromInputs = m.fromInputs; Object.assign(B, m.flat)' },
  { name: 'page', file: 'page.js', deps: ['api'], global: '{}', register: 'm.mountPage(B)' },
];

const here = fileURLToPath(new URL('.', import.meta.url));

/** The built module scripts, in load order: [{ name, js }]. Run onchain/build.mjs first. */
export function loadBuiltModules(names = MODULES.map((m) => m.name)) {
  return names.map((name) => ({ name, js: readFileSync(here + `dist/modules/${name}.js`, 'utf8') }));
}
