// Transforms: song → new song. Pure functions; inputs are never modified.
import { fromNotes } from './music.js';

const BAR = 4 * 480;
const end = (song) => (song.notes.length ? Math.max(...song.notes.map((n) => n[0] + n[1])) : 0);
const clampPitch = (p) => Math.max(0, Math.min(127, p));
// Re-time b's ticks into a's tempo so both play at the right speed under one tempo.
const retime = (notes, from_us, to_us) => notes.map(([t, d, ...rest]) => [Math.round((t * from_us) / to_us), Math.max(1, Math.round((d * from_us) / to_us)), ...rest]);

/** Shift every pitch by `semitones` (clamped to 0–127). */
export const transpose = (song, semitones) => fromNotes(song.notes.map(([t, d, p, ...r]) => [t, d, clampPitch(p + semitones), ...r]), song.tempo_us);

/** Play `factor` times faster (2 = double speed, 0.5 = half). */
export const tempo = (song, factor) => fromNotes(song.notes, Math.round(song.tempo_us / factor));

/** Keep only the listed voices. */
export const voices = (song, keep) => fromNotes(song.notes.filter((n) => keep.includes(n[4])), song.tempo_us);

/** Scale every velocity by `factor` (clamped to 1–127). */
export const gain = (song, factor) => fromNotes(song.notes.map(([t, d, p, v, ...r]) => [t, d, p, Math.max(1, Math.min(127, Math.round(v * factor))), ...r]), song.tempo_us);

/** Play songs together. Each song's voices get their own channels; the first song sets the tempo. */
export function layer(...songs) {
  const tempo_us = songs[0].tempo_us;
  const notes = [];
  let base = 0;
  for (const s of songs) {
    const ids = [...new Set(s.notes.map((n) => n[4]))].sort((a, b) => a - b);
    for (const [t, d, p, v, voice] of retime(s.notes, s.tempo_us, tempo_us)) notes.push([t, d, p, v, base + ids.indexOf(voice)]);
    base += ids.length;
  }
  return fromNotes(notes.sort((a, b) => a[0] - b[0] || a[4] - b[4]), tempo_us);
}

/** Play songs one after another, each starting on a bar line; the first song sets the tempo. */
export function concat(...songs) {
  const tempo_us = songs[0].tempo_us;
  const notes = [];
  let offset = 0;
  for (const s of songs) {
    const timed = retime(s.notes, s.tempo_us, tempo_us);
    for (const [t, ...rest] of timed) notes.push([t + offset, ...rest]);
    offset += Math.ceil(end({ notes: timed }) / BAR) * BAR;
  }
  return fromNotes(notes, tempo_us);
}
