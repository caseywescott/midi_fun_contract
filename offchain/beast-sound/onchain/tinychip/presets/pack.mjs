// Writes the optional preset pack (OPTIONAL_PACK in convert.mjs) for onchain-midi-player:
//
//   optional-pack/pack.json            the TinySynthSettings value (its own waves, re-indexed) and the preset names
//   optional-pack/settings.txt         that value as the page's SETTINGS text (format v1)
//   optional-pack/settings.txt.gz.b64  that text gzipped (level 9), then base64: the payload to ship with the player
//   optional-pack/README.md            what is in it and how to merge it with a Beast's settings
//
//   OMP=<onchain-midi-player checkout> node onchain/tinychip/presets/pack.mjs
//
// With OMP set it also checks the pack end to end against onchain-midi-player's own code: the Cairo
// checks (player/validate.js), its encoder (player/encode.js, byte for byte), its parser
// (player/settings.js decodeSettings, round trip), its page's gunzip shim (player/gunzip.js) on the
// payload, and the pack merged with each of the six Beast settings (settings/*.json).
import { mkdirSync, readFileSync, writeFileSync, readdirSync } from 'node:fs';
import { gzipSync } from 'node:zlib';
import { pathToFileURL } from 'node:url';
import { presets, waves, SETTINGS_BASE, OPTIONAL_PACK } from './convert.mjs';
import { ESSENTIALS } from '../essentials.mjs';

const out = new URL('../optional-pack/', import.meta.url);
const OP_FIELDS = ['volume', 'ratio', 'offset_hz', 'attack', 'hold', 'decay', 'sustain', 'release', 'pitch_ratio', 'pitch_time', 'key_scale'];
const TAGS = ['Sine', 'Square', 'Sawtooth', 'Triangle', 'WhiteNoise', 'MetallicNoise'];

/** A settings value holding only these presets and the sampled waves they use (re-indexed). */
export function packSettings(ids) {
  const sel = ids.map((id) => presets[id]);
  const used = [...new Set(sel.flatMap((p) => p.operators.filter((o) => typeof o.wave === 'object').map((o) => o.wave.Custom)))].sort((a, b) => a - b);
  const remap = new Map(used.map((w, i) => [w, i]));
  return {
    settings: { ...SETTINGS_BASE, waves: used.map((w) => ({ Samples: waves[w].Samples })), timbres: sel.map((p) => ({ drum: false, slot: p.program, operators: p.operators.map((o) => ({ ...o, wave: typeof o.wave === 'object' ? { Custom: remap.get(o.wave.Custom) } : o.wave })) })) },
    waveNames: used.map((w) => waves[w].name),
  };
}

/** SETTINGS text, format v1 (the grammar of onchain-midi-player's player/encode.js; no filters here). */
export function encode(s) {
  const o = [1, s.quality, s.reverb, s.master_vol, s.voices, s.waves.length];
  for (const w of s.waves) o.push(1, w.Samples.length, ...w.Samples);
  o.push(s.timbres.length);
  for (const t of s.timbres) {
    o.push(t.drum ? 1 : 0, t.slot, t.operators.length);
    for (const op of t.operators) { o.push(op.route); typeof op.wave === 'object' ? o.push(6, op.wave.Custom) : o.push(TAGS.indexOf(op.wave)); for (const k of OP_FIELDS) o.push(op[k]); o.push(0); }
  }
  return o.join(',');
}

/**
 * A Beast's settings with the pack added: the pack's waves are appended (a wave the base already
 * has is shared) and its operators' Custom(i) re-pointed; the base keeps its quality, reverb, volume
 * and voices. Throws if a pack slot is already taken.
 */
export function mergePack(base, pack) {
  const key = (w) => JSON.stringify(w), waves = base.waves.slice(), at = new Map(waves.map((w, i) => [key(w), i]));
  const map = pack.waves.map((w) => { if (!at.has(key(w))) { at.set(key(w), waves.length); waves.push(w); } return at.get(key(w)); });
  const taken = new Set(base.timbres.map((t) => (t.drum ? 128 : 0) + t.slot));
  for (const t of pack.timbres) if (taken.has((t.drum ? 128 : 0) + t.slot)) throw new Error('slot ' + t.slot + ' is already in the base settings');
  return { ...base, waves, timbres: [...base.timbres, ...pack.timbres.map((t) => ({ ...t, operators: t.operators.map((o) => (typeof o.wave === 'object' ? { ...o, wave: { Custom: map[o.wave.Custom] } } : o)) }))] };
}

if (OPTIONAL_PACK.some((id) => ESSENTIALS.includes(id))) throw new Error('the optional pack overlaps the launch set');
const { settings, waveNames } = packSettings(OPTIONAL_PACK);
const text = encode(settings), gz = gzipSync(Buffer.from(text), { level: 9 }), b64 = gz.toString('base64');
const meta = OPTIONAL_PACK.map((id) => ({ program: id, name: presets[id].name, category: presets[id].category, inspired: presets[id].inspired, operators: presets[id].operators.length }));

if (process.env.OMP) {
  const omp = (f) => import(pathToFileURL(process.env.OMP + '/player/' + f));
  const { validateSettings } = await omp('validate.js'), { encodeSettings } = await omp('encode.js'), { decodeSettings } = await omp('settings.js'), { gunzip } = await omp('gunzip.js');
  validateSettings(settings);
  if (encodeSettings(settings) !== text) throw new Error('SETTINGS text differs from onchain-midi-player encodeSettings');
  if (JSON.stringify(decodeSettings(text)) !== JSON.stringify(settings)) throw new Error('decodeSettings round trip differs');
  if (new TextDecoder().decode(gunzip(new Uint8Array(Buffer.from(b64, 'base64')))) !== text) throw new Error('the page gunzip shim does not give back the text');
  const dir = new URL('../settings/', import.meta.url);
  for (const f of readdirSync(dir).filter((x) => x.endsWith('.json')).sort()) {
    const base = JSON.parse(readFileSync(new URL(f, dir), 'utf8')), merged = mergePack(base, settings);
    validateSettings(merged);
    if (JSON.stringify(decodeSettings(encodeSettings(merged))) !== JSON.stringify(merged)) throw new Error(f + ': merged round trip differs');
    console.log(`  ${f}: ${base.timbres.length} + ${settings.timbres.length} timbres, ${base.waves.length} -> ${merged.waves.length} waves: valid`);
  }
  console.log('onchain-midi-player: valid, encoder byte-identical, decode round trip and gunzip shim OK');
} else console.log('OMP not set: skipping the onchain-midi-player checks');

mkdirSync(out, { recursive: true });
writeFileSync(new URL('pack.json', out), JSON.stringify({ name: 'tinychip-optional-pack', format: 'onchain-midi-player TinySynthSettings, SETTINGS format v1', programs: OPTIONAL_PACK, presets: meta, waves: waveNames, settings }, null, 1) + '\n');
writeFileSync(new URL('settings.txt', out), text + '\n');
writeFileSync(new URL('settings.txt.gz.b64', out), b64 + '\n');
const rows = meta.map((m) => `| ${m.program} | ${m.name} | ${m.category} | ${m.inspired ?? ''} | ${m.operators} |`).join('\n');
writeFileSync(new URL('README.md', out), `# TinyChip optional preset pack

25 TinyChip presets outside the Beasts launch set, as onchain-midi-player \`TinySynthSettings\`
timbres, to ship pre-encoded (gzip, then base64) alongside the player rather than in each
\`token_uri\`'s \`SETTINGS\`. Listen to them on https://beasts.autonomousaudio.net/onchain/presets.html
(filter "Optional pack").

Generated by \`onchain/tinychip/presets/pack.mjs\` from the same bank conversion as the audition page
and the launch settings (\`synth_settings.mjs\`): loudness gains and mix trims folded in, sampled chip
waves as \`WaveDef::Samples\`, fixed point x10000. Do not edit these files by hand.

| File | What it is |
|---|---|
| \`pack.json\` | The \`TinySynthSettings\` value (\`settings\`), plus the program list, names and wave names |
| \`settings.txt\` | That value as the page's \`SETTINGS\` text (format v1), ${text.length.toLocaleString('en-US')} bytes |
| \`settings.txt.gz.b64\` | The text gzipped (level 9), then base64: ${gz.length.toLocaleString('en-US')} bytes, ${b64.length.toLocaleString('en-US')} characters |

- **Slots:** each timbre sits in its bank program number (\`drum: false\`), so a MIDI program change to N
  plays preset N. None of them is a launch-set slot (0–9, 12–19, 50, 65) or a drum, so the pack can
  be added to any Beast's settings.
- **Waves:** the pack carries its own ${waveNames.length} waves (${waveNames.join(', ')}), indexed from 0. To add the pack to a
  Beast's settings, append the waves it doesn't already have and re-point each \`Custom(i)\`;
  \`mergePack(base, pack)\` in \`pack.mjs\` is the reference.
- **Checked against onchain-midi-player** (\`OMP=<checkout> node onchain/tinychip/presets/pack.mjs\`):
  \`validate.js\` accepts it, \`encode.js\` gives the same text byte for byte, \`decodeSettings\` round-trips
  it, the page's gunzip shim restores the text from the payload, and the pack merged with each of
  the six Beast settings (\`../settings/*.json\`) validates.
- **No AM modulators** and no filters in this selection.

| Program | Preset | Family | After | Operators |
|---|---|---|---|---|
${rows}
`);
console.log(`optional pack: ${OPTIONAL_PACK.length} presets, ${waveNames.length} waves (${waveNames.join(' ')}); SETTINGS ${text.length} bytes, gzip ${gz.length} bytes, base64 ${b64.length} chars`);
