// Standard MIDI File writer for any note list. No dependencies.
//
// notes: [[time, duration, pitch, velocity, voice], ...] in ticks (480 per quarter note).
// Output: type 1, one tempo track plus one track per voice (channel = voice). endTick (optional) puts
// the tempo track's End of Track there, so the file lasts that long even when it ends in a rest. For
// Beast scores the bytes are identical to beast_form_to_smf_bytes in beast_v3_sound.cairo (the engine
// calls this with the form's length).

export const PPQ = 480;

export function notesToMidi(notes, tempo_us, endTick = 0) {
  const vlq = (n) => { const b = [n & 0x7f]; while ((n >>= 7)) b.unshift((n & 0x7f) | 0x80); return b; };
  const chunk = (type, data) => [...type].map((c) => c.charCodeAt(0)).concat([(data.length >>> 24) & 255, (data.length >>> 16) & 255, (data.length >>> 8) & 255, data.length & 255], data);
  const tracks = [[0, 0xff, 0x51, 0x03, (tempo_us >> 16) & 255, (tempo_us >> 8) & 255, tempo_us & 255, ...vlq(endTick), 0xff, 0x2f, 0x00]];
  const voices = [...new Set(notes.map((n) => n[4]))].sort((a, b) => a - b);
  for (const v of voices) {
    const msgs = [];
    for (const [time, duration, pitch, velocity] of notes.filter((n) => n[4] === v)) {
      msgs.push([time, 0x90 | (v & 15), pitch, velocity]);
      msgs.push([time + duration, 0x80 | (v & 15), pitch, 64]);
    }
    msgs.sort((a, b) => a[0] - b[0] || (a[1] & 0xf0) - (b[1] & 0xf0));
    const data = [];
    let t = 0;
    for (const m of msgs) { data.push(...vlq(m[0] - t), m[1], m[2], m[3]); t = m[0]; }
    data.push(0, 0xff, 0x2f, 0x00);
    tracks.push(data);
  }
  const header = chunk('MThd', [0, 1, 0, tracks.length, (PPQ >> 8) & 255, PPQ & 255]);
  return new Uint8Array(header.concat(...tracks.map((d) => chunk('MTrk', d))));
}
