// The song shape shared by every layer: { notes: [[time, duration, pitch, velocity, voice], ...], tempo_us }.
// Tiny and dependency-free, so layers that only reshape songs (fx) need nothing else.
export const TICKS_PER_BEAT = 480;

/** Wrap any note list as a song (for midi.write, play and fx). */
export function fromNotes(notes, tempo_us, extra = {}) {
  const ticks = notes.length ? Math.max(...notes.map((n) => n[0] + n[1])) : 0;
  return { notes, tempo_us, durationSeconds: (ticks / TICKS_PER_BEAT) * (tempo_us / 1e6), ...extra };
}
