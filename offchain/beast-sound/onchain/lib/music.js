// Music layer: composition params + seed → a song. Knows nothing about Beasts; any project can
// build params (see beast.params for the shape) and get counterpoint back.
import { engine, TICKS_PER_BEAT } from './core.js';

/**
 * @returns song { notes: [[time, duration, pitch, velocity, voice], ...] (ticks, 480 per beat),
 *   tempo_us, durationSeconds, scoreHash ('0x…'), params, sections }
 */
export function generate(params, seed) {
  const form = engine.buildForm(params, BigInt(seed));
  return fromNotes(form.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]), params.tempo_us, {
    scoreHash: '0x' + form.score_hash.toString(16), params, sections: form.sections,
  });
}

/** Wrap any note list as a song (for midi.write, play and fx). */
export function fromNotes(notes, tempo_us, extra = {}) {
  const ticks = notes.length ? Math.max(...notes.map((n) => n[0] + n[1])) : 0;
  return { notes, tempo_us, durationSeconds: (ticks / TICKS_PER_BEAT) * (tempo_us / 1e6), ...extra };
}
