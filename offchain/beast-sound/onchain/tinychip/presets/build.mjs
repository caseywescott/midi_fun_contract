// Builds public/onchain/presets.html: all 100 TinyChip presets as onchain-midi-player TinySynthSettings timbres
// (the same conversion as onchain/tinychip/synth_settings.mjs, extended to the 80 presets outside
// the launch set and to AM modulators), played through the pinned TinySynth engine the way the
// onchain player installs settings.
//
//   node onchain/tinychip/presets/build.mjs <webaudio-tinysynth-4bf9829.min.js>   writes public/onchain/presets.html
//   OMP=<onchain-midi-player checkout> ...                                  also validates every timbre with its player/validate.js
import { readFileSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { ESSENTIALS } from '../essentials.mjs';
import { STEPS } from '../synth_settings.mjs';
import { presets, drums, waves, WAVES, full, presetOps, OPTIONAL_PACK } from './convert.mjs';

const here = new URL('.', import.meta.url);
if (process.env.OMP) {
  const { validateSettings } = await import(pathToFileURL(process.env.OMP + '/player/validate.js'));
  const { encodeSettings } = await import(pathToFileURL(process.env.OMP + '/player/encode.js'));
  validateSettings(full);
  console.log(`${presets.length} presets, ${drums.length} drums, ${waves.length} waves; full SETTINGS ${encodeSettings(full).length} bytes; valid`);
} else console.log('OMP not set: skipping onchain-midi-player validation');

// The launch set's settings must match synth_settings.mjs's own (same conversion for the 20).
const { beastSynthSettings } = await import('../synth_settings.mjs');
const ref = beastSynthSettings(undefined, ESSENTIALS, []);
const named = (ops, names) => ops.map((o) => ({ ...o, wave: typeof o.wave === 'object' ? names[o.wave.Custom] : o.wave }));
const refNames = Object.keys(STEPS).filter((w) => new Set(ESSENTIALS.flatMap((id) => presetOps(id).map((o) => o.w))).has(w));
for (const t of ref.timbres) {
  if (JSON.stringify(named(presets[t.slot].operators, WAVES)) !== JSON.stringify(named(t.operators, refNames))) throw new Error('launch preset ' + t.slot + ' differs from synth_settings.mjs');
}
console.log('launch set matches synth_settings.mjs');

const data = { waves, presets, drums, optional: OPTIONAL_PACK, settingsBase: { quality: 1, reverb: 30, master_vol: 40, voices: 64 } };
if (!process.argv[2]) throw new Error('usage: node onchain/tinychip/presets/build.mjs <webaudio-tinysynth-4bf9829.min.js>');
const engine = readFileSync(process.argv[2], 'utf8');
const page = readFileSync(new URL('page.src.html', here), 'utf8')
  .replace('/*ENGINE*/', () => engine.replace(/<\/script/gi, '<\\/script'))
  .replace('/*DATA*/null', () => JSON.stringify(data));
writeFileSync(new URL('../../../public/onchain/presets.html', here), page);
console.log('presets.html', page.length, 'bytes');
