// Notes layer: a compact felt-encoded score → song, so a player can be driven straight from felts
// the chain computed (e.g. the Cairo composer's get_score_notes), with no composer loaded.
//
// Two felt formats, detected from the first felt:
//   BSN1  Beast canons: 7 bits per note in runs on a fixed grid. Felts are [byte_len, 31-byte chunks…].
//   BSI1  any music: 62-bit instructions (header, tempo, notes), 4 per felt. See src/bsi.js.
import { decodeBsn } from '../../src/bsn.js';
import { decodeBsi, isBsi } from '../../src/bsi.js';
import { fromNotes } from './song.js';

/**
 * @param input felts (bigint / decimal / 0x-hex strings), "f1,f2,…" text, or BSN1 bytes (Uint8Array)
 * @returns song { notes, tempo_us, durationSeconds }
 */
export function decode(input) {
  const src = typeof input === 'string' ? input.split(',').map((f) => BigInt(f.trim())) : input;
  if (!(src instanceof Uint8Array) && isBsi(src)) {
    const { notes, tempo_us, length_ticks } = decodeBsi(src);
    return fromNotes(notes, tempo_us, length_ticks ? { length_ticks } : {});
  }
  const { tempo_us, events, length_ticks } = decodeBsn(src instanceof Uint8Array ? src : src.map((f) => BigInt(f)));
  return fromNotes(events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]), tempo_us, length_ticks ? { length_ticks } : {});
}
