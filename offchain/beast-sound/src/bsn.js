// BSN1: the compact onchain note stream (7 bits per note). Standalone, so the onchain library's
// `notes` module can decode felts without the engine; the engine adds it via createBsn.
// Byte-identical to beast_score_notes in beast_v3_sound.cairo; checked by test/golden.test.mjs.
import { notesToMidi } from './midi_file.js';

// Format constants (BSN1): grid and base velocity written into the header, articulation code 3 = accent.
const GRID = 480, BASE_VELOCITY = 90, ACCENT = 3;

// ── BSN1: compact onchain note stream (see beast_v3_sound.cairo) ──
// header: version 8 | tempo_us 24 | grid 12 | duration 12 | articulation 3 | base_vel 7 | vel_ceiling 7 | runs 8
// run: voice 4 | start_beat 12 | count 8, then count × key 7
// trailer: length_beats 12 (the form's length; older streams end without it and older decoders stop
// after the runs)
export function encodeBsn(result) {
  const { form, params } = result;
  const length = form.section_ticks * form.sections.length;
  const ev = form.events, grid = GRID, dur = ev[0].duration;
  const bits = [];
  const push = (v, w) => { for (let i = w - 1; i >= 0; i--) bits.push((v >> i) & 1); };
  const runs = [];
  ev.forEach((e, i) => {
    const p = ev[i - 1];
    if (!p || p.voice_id !== e.voice_id || p.time + grid !== e.time) runs.push([]);
    runs[runs.length - 1].push(e);
  });
  push(1, 8); push(params.tempo_us, 24); push(grid, 12); push(dur, 12); push(params.articulation_profile, 3);
  push(BASE_VELOCITY, 7); push(params.velocity_ceiling, 7); push(runs.length, 8);
  for (const r of runs) { push(r[0].voice_id, 4); push(r[0].time / grid, 12); push(r.length, 8); r.forEach((e) => push(e.pitch, 7)); }
  push(length / grid, 12);
  while (bits.length % 8) bits.push(0);
  const bytes = new Uint8Array(bits.length / 8);
  for (let i = 0; i < bytes.length; i++) for (let b = 0; b < 8; b++) bytes[i] = (bytes[i] << 1) | bits[i * 8 + b];
  return bytes;
}

// Bytes <-> felts in the to_felt252_array layout: [byte_len, 31-byte big-endian chunks...].
export function bytesToFelts(bytes) {
  const felts = [BigInt(bytes.length)];
  for (let i = 0; i < bytes.length; i += 31) felts.push(bytes.slice(i, i + 31).reduce((v, x) => v * 256n + BigInt(x), 0n));
  return felts;
}
export function feltsToBytes(felts) {
  const len = Number(BigInt(felts[0]));
  const out = new Uint8Array(len);
  for (let c = 1, o = 0; o < len; c++) {
    const n = Math.min(31, len - o);
    let v = BigInt(felts[c]);
    for (let k = n - 1; k >= 0; k--) { out[o + k] = Number(v & 255n); v >>= 8n; }
    o += n;
  }
  return out;
}

// Decode BSN1 (bytes, or felts straight from get_score_notes) into canonical note events.
export function decodeBsn(input) {
  const bytes = input instanceof Uint8Array ? input : feltsToBytes(input);
  let pos = 0;
  const read = (w) => { let v = 0; for (let i = 0; i < w; i++, pos++) v = v * 2 + ((bytes[pos >> 3] >> (7 - (pos & 7))) & 1); return v; };
  const version = read(8);
  if (version !== 1) throw new Error('unsupported BSN version ' + version);
  const tempo_us = read(24), grid = read(12), duration = read(12), articulation = read(3);
  const base = read(7), ceilRaw = read(7), runCount = read(8);
  const ceil = ceilRaw === 0 ? 127 : ceilRaw;
  const events = [];
  let prevVoice = Infinity, section = -1, idx = 0;
  for (let r = 0; r < runCount; r++) {
    const voice = read(4), start = read(12), count = read(8);
    if (voice <= prevVoice) { section += 1; idx = 0; } // a non-ascending voice starts a new section
    prevVoice = voice;
    for (let k = 0; k < count; k++, idx++) {
      let vel = articulation === ACCENT && idx % 4 === 0 ? Math.min(base + 20, ceil) : base;
      if (vel > ceil) vel = ceil;
      events.push({ time: (start + k) * grid, duration, pitch: read(7), velocity: vel, voice_id: voice, section });
    }
  }
  // the length trailer, when present (padding is under 8 bits, the field is 12)
  const length_ticks = bytes.length * 8 - pos >= 12 ? read(12) * grid : 0;
  return { tempo_us, events, length_ticks };
}

/** BSN1 (bytes, or felts as from get_score_notes) → Standard MIDI File bytes. */
export const bsnToMidi = (input) => {
  const d = decodeBsn(input);
  return notesToMidi(d.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]), d.tempo_us, d.length_ticks);
};

/** The engine's BSN1 methods (kept for the package API and parity scripts). */
export function createBsn() {
  return { encodeBsn, decodeBsn, bsnToMidi, bytesToFelts, feltsToBytes };
}
