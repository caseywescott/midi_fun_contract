// Writes <copy of onchain-midi-player>/tests/beast_e2e_fixtures.cairo: our settings' Serde and two
// self-contained Beast MIDI files as get_midi plays them (Genesis Tracks: the Warlock, and the largest
// file, shiny #32) as ByteArray Serde.
import { writeFileSync } from 'node:fs';
const bm = new URL('../..', import.meta.url).pathname.replace(/\/$/, ''), out = process.argv[2];
const { engine: E } = await import(bm + '/offchain/beast-sound/src/index.js');
const { beastSoundMidi } = await import(bm + '/offchain/beast-sound/src/full_midi.js');
const { createEngineV11 } = await import(bm + '/offchain/beast-sound/src/engine_v11.js');
const v11 = createEngineV11(E);
const { genesisMidi } = await import(bm + '/offchain/beast-sound/src/lab.js'); // the Genesis Track, as get_midi
const { beastSynthSettings, serializeSettings, beastPrograms } = await import(bm + '/offchain/beast-sound/onchain/tinychip/synth_settings.mjs');
const byteArraySerde = (bytes) => {
  const full = Math.floor(bytes.length / 31), f = [BigInt(full)];
  const word = (a, b) => { let w = 0n; for (let i = a; i < b; i++) w = w * 256n + BigInt(bytes[i]); return w; };
  for (let i = 0; i < full; i++) f.push(word(i * 31, i * 31 + 31));
  f.push(word(full * 31, bytes.length), BigInt(bytes.length - full * 31));
  return f;
};
const fn = (name, ty, felts) => `pub fn ${name}() -> ${ty} {\n    let mut span = array![\n${felts.map((x) => `        0x${x.toString(16)},`).join('\n')}\n    ]\n        .span();\n    Serde::deserialize(ref span).unwrap()\n}\n`;
const W = { id: 1, shiny: 0, beast_type: 0 }, heavy = [{ id: 32, shiny: 1, beast_type: 1 }];
const warlock = genesisMidi(W.id, false, E, v11).midi, heaviest = genesisMidi(heavy[0].id, true, E, v11).midi;
// the settings get_settings serves each: the Warlock is a Magic Beast, the heavy one a mega Hunter
const s = serializeSettings(beastSynthSettings(undefined, beastPrograms(W.beast_type, W.shiny === 1))), mega = serializeSettings(beastSynthSettings(undefined, beastPrograms(heavy[0].beast_type, heavy[0].shiny === 1)));
writeFileSync(out, `//! Generated: Beast Sound end-to-end fixtures (settings Serde from BeastMidiProvider.get_settings, MIDI from get_midi).
use onchain_midi_player::types::TinySynthSettings;

pub const WARLOCK_LEN: u32 = ${warlock.length};
pub const HEAVIEST_LEN: u32 = ${heaviest.length};
pub const SETTINGS_FELTS: u32 = ${s.length};

${fn('beast_settings', 'TinySynthSettings', s)}
${fn('beast_mega_settings', 'TinySynthSettings', mega)}
${fn('warlock_midi', 'ByteArray', byteArraySerde(warlock))}
${fn('heaviest_midi', 'ByteArray', byteArraySerde(heaviest))}`);
console.log(`settings ${s.length} felts, warlock ${warlock.length} B, heaviest ${heaviest.length} B`);
