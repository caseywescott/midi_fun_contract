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
  { name: 'notes', file: 'notes.js', deps: [], global: 'v1.notes', register: 'v1.notes = m' },
  { name: 'smf', file: 'smf.js', deps: [], global: 'v1.smf', register: 'v1.smf = m' },
  { name: 'api', file: 'index.js', deps: ['beast', 'music', 'midi', 'play'], global: '{ compose: v1.compose, fromInputs: v1.fromInputs, flat: B }', register: 'v1.compose = m.compose; v1.fromInputs = m.fromInputs; Object.assign(B, m.flat)' },
  { name: 'page', file: 'page.js', deps: ['midi', 'play'], global: '{}', register: 'm.mountPage(B)' },
];

// Module lists for the two token_uri page variants (a page contract's list is fixed at deploy):
//   inputs  the contract writes token ID + stats; the library composes (whole library on the page)
//   notes   the contract writes BSN1 felts computed in Cairo; the page only decodes and plays
//   midi    the contract writes a Standard MIDI File (get_score_midi, base64); the page parses and plays
export const PAGES = {
  inputs: MODULES.map((m) => m.name).filter((n) => n !== 'notes' && n !== 'smf'),
  notes: ['midi', 'synth', 'play', 'notes', 'page'],
  midi: ['midi', 'synth', 'play', 'smf', 'page'],
};

const here = fileURLToPath(new URL('.', import.meta.url));

/** The built module scripts, in load order: [{ name, js }]. Run onchain/build.mjs first. */
export function loadBuiltModules(names = MODULES.map((m) => m.name)) {
  return names.map((name) => ({ name, js: readFileSync(here + `dist/modules/${name}.js`, 'utf8') }));
}
