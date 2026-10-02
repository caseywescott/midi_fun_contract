// Notes layer: a compact felt-encoded score → song, so a player can be driven straight from felts
// the chain computed (e.g. the Cairo composer's get_score_notes), with no composer loaded.
//
// Format: BSN1, 7 bits per note in runs on a fixed grid (header: tempo, grid, duration, articulation,
// velocities; run: voice, start beat, count, then 7-bit keys). Felts are [byte_len, 31-byte chunks…].
import { decodeBsn } from '../../src/bsn.js';
import { fromNotes } from './song.js';

/**
 * @param input felts (bigint / decimal / 0x-hex strings), "f1,f2,…" text, or BSN1 bytes (Uint8Array)
 * @returns song { notes, tempo_us, durationSeconds }
 */
export function decode(input) {
  const src = typeof input === 'string' ? input.split(',').map((f) => BigInt(f.trim())) : input;
  const { tempo_us, events } = decodeBsn(src instanceof Uint8Array ? src : src.map((f) => BigInt(f)));
  return fromNotes(events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]), tempo_us);
}
