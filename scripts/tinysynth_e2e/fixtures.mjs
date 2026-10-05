// Writes <copy of onchain-tinysynth>/tests/beast_e2e_fixtures.cairo: our settings' Serde and two
// self-contained Beast MIDI files from composer v1.1 (Warlock calm, a heavy score) as ByteArray Serde.
import { writeFileSync } from 'node:fs';
const bm = new URL('../..', import.meta.url).pathname.replace(/\/$/, ''), out = process.argv[2];
const { engine: E } = await import(bm + '/offchain/beast-sound/src/index.js');
const { beastFullMidi } = await import(bm + '/offchain/beast-sound/src/full_midi.js');
const { createEngineV11 } = await import(bm + '/offchain/beast-sound/src/engine_v11.js');
const v11 = createEngineV11(E), V11 = { keys: 'mode', even: true, traj: true }; // composer v1.1, as get_midi
const { beastSynthSettings, serializeSettings } = await import(bm + '/offchain/beast-sound/onchain/tinychip/synth_settings.mjs');
const byteArraySerde = (bytes) => {
  const full = Math.floor(bytes.length / 31), f = [BigInt(full)];
  const word = (a, b) => { let w = 0n; for (let i = a; i < b; i++) w = w * 256n + BigInt(bytes[i]); return w; };
  for (let i = 0; i < full; i++) f.push(word(i * 31, i * 31 + 31));
  f.push(word(full * 31, bytes.length), BigInt(bytes.length - full * 31));
  return f;
};
const fn = (name, ty, felts) => `pub fn ${name}() -> ${ty} {\n    let mut span = array![\n${felts.map((x) => `        0x${x.toString(16)},`).join('\n')}\n    ]\n        .span();\n    Serde::deserialize(ref span).unwrap()\n}\n`;
const W = { id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 };
const calm = { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 500, species_count: 954 };
const heavy = [{ id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 }, { adventurers_killed: 500, scars: 63, summit_held_seconds: 0, rank: 1, species_count: 1243 }];
const warlock = beastFullMidi(v11.render(W, calm, V11), E.formLength), heaviest = beastFullMidi(v11.render(...heavy, V11), E.formLength);
const s = serializeSettings(beastSynthSettings());
writeFileSync(out, `//! Generated: Beast Sound end-to-end fixtures (settings Serde from BeastMidiProvider.get_settings, MIDI from get_midi).
use onchain_tinysynth::types::SynthSettings;

pub const WARLOCK_LEN: u32 = ${warlock.length};
pub const HEAVIEST_LEN: u32 = ${heaviest.length};
pub const SETTINGS_FELTS: u32 = ${s.length};

${fn('beast_settings', 'SynthSettings', s)}
${fn('warlock_midi', 'ByteArray', byteArraySerde(warlock))}
${fn('heaviest_midi', 'ByteArray', byteArraySerde(heaviest))}`);
console.log(`settings ${s.length} felts, warlock ${warlock.length} B, heaviest ${heaviest.length} B`);
