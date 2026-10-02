// MIDI layer: any song (or note list) → Standard MIDI File. Beast scores come out byte-identical
// to the Cairo get_score_midi.
import { notesToMidi } from '../../src/midi_file.js';

/** song: { notes, tempo_us } → Uint8Array (type 1, one track per voice). */
export const write = (song) => notesToMidi(song.notes, song.tempo_us);

/** Object URL for an <a download> link (revoke it when done). */
export const url = (song) => URL.createObjectURL(new Blob([write(song)], { type: 'audio/midi' }));
