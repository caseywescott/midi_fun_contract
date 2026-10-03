// SMF layer: a Standard MIDI File → song, so any MIDI the chain writes (e.g. the Cairo composer's
// get_score_midi) plays through the chip synth. Reads type 0/1 files: note on/off (velocity 0 = off),
// tempo, running status; skips other meta, sysex and channel messages. Voice = MIDI channel.
import { fromNotes, TICKS_PER_BEAT } from './song.js';

/** Bytes (Uint8Array / ArrayBuffer) or base64 text → song { notes, tempo_us, length_ticks }. */
export function parse(input) {
  const b = typeof input === 'string' ? Uint8Array.from(atob(input), (c) => c.charCodeAt(0)) : new Uint8Array(input);
  let p = 0;
  const u8 = () => b[p++];
  const u16 = () => (b[p++] << 8) | b[p++];
  const u32 = () => ((b[p++] << 24) | (b[p++] << 16) | (b[p++] << 8) | b[p++]) >>> 0;
  const vlq = () => { let v = 0, c; do { c = b[p++]; v = (v << 7) | (c & 0x7f); } while (c & 0x80); return v; };
  const tag = () => String.fromCharCode(b[p++], b[p++], b[p++], b[p++]);

  if (tag() !== 'MThd') throw new Error('smf: not a MIDI file');
  const hlen = u32(), hstart = p;
  u16(); const ntrks = u16(), division = u16();
  if (division & 0x8000) throw new Error('smf: SMPTE time division is not supported');
  p = hstart + hlen;
  const scale = TICKS_PER_BEAT / division;

  let tempo_us = 500000, songEnd = 0;
  const notes = [];
  for (let t = 0; t < ntrks && p < b.length; t++) {
    if (tag() !== 'MTrk') throw new Error('smf: bad track');
    const length = u32();
    const end = p + length; // after reading the length (p + u32() would read p first)
    const open = new Map(); // (channel << 7 | key) → [start, velocity] FIFO
    let time = 0, status = 0;
    while (p < end) {
      time += vlq();
      let s = b[p];
      if (s & 0x80) p++; else s = status; // running status
      if (s === 0xff) {
        const type = u8(), len = vlq();
        if (type === 0x51 && len === 3) tempo_us = (b[p] << 16) | (b[p + 1] << 8) | b[p + 2];
        p += len;
        if (type === 0x2f) { songEnd = Math.max(songEnd, time); break; } // End of Track: the song's length
        continue;
      }
      if (s === 0xf0 || s === 0xf7) { p += vlq(); continue; }
      status = s;
      const kind = s & 0xf0, ch = s & 0x0f;
      if (kind === 0xc0 || kind === 0xd0) { p += 1; continue; }
      const key = u8(), vel = u8();
      if (kind !== 0x90 && kind !== 0x80) continue;
      const id = (ch << 7) | key;
      if (kind === 0x90 && vel > 0) {
        (open.get(id) || open.set(id, []).get(id)).push([time, vel]);
      } else {
        const q = open.get(id);
        if (q && q.length) {
          const [start, v] = q.shift();
          notes.push([Math.round(start * scale), Math.max(1, Math.round((time - start) * scale)), key, v, ch]);
        }
      }
    }
    p = end;
  }
  notes.sort((x, y) => x[0] - y[0] || x[4] - y[4] || x[2] - y[2]);
  return fromNotes(notes, tempo_us, { length_ticks: Math.round(songEnd * scale) });
}
