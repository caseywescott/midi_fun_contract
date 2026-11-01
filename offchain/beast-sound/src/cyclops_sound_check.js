// Authored Cyclops Sound Check: exact original Beast Sound Check track 504.
// All effects retain the eight programs/pitches/order. Standard Check performance changes
// tempo, portato gates and accents; normal0 remains the exact original175BPM reference.
export const CYCLOPS_SOUND_CHECK_PROGRAMS = Object.freeze([34, 35, 36, 37, 38, 39, 40, 41]);
export const CYCLOPS_SOUND_CHECK_TEMPO_US = 342857;
export const CYCLOPS_SOUND_CHECK_LENGTH = 38400;

export function cyclopsSoundCheckMidi(fx = 0) {
  if (!Number.isInteger(fx) || fx < 0 || fx > 3) throw new RangeError('Sound effects must be0..3');
  const tempoUs = CYCLOPS_SOUND_CHECK_TEMPO_US - [0, 25000, 30000, 45000][fx];
  const vlq = (n) => { const bytes = [n & 127]; while ((n >>>= 7)) bytes.unshift((n & 127) | 128); return bytes; };
  const chunk = (tag, bytes) => [...tag].map((c) => c.charCodeAt(0)).concat([bytes.length >>> 24, (bytes.length >>> 16) & 255, (bytes.length >>> 8) & 255, bytes.length & 255], bytes);
  const tempo = [0, 255, 81, 3, tempoUs >> 16, (tempoUs >> 8) & 255, tempoUs & 255, ...vlq(CYCLOPS_SOUND_CHECK_LENGTH), 255, 47, 0];
  const data = []; let last = 0;
  const event = (tick, ...bytes) => { data.push(...vlq(tick - last), ...bytes); last = tick; };
  const note = (at, key, duration) => {
    const gate = fx === 2 ? Math.min(duration, Math.max(60, Math.floor(duration * 3 / 4))) : duration;
    const velocity = fx === 3 && at % 1920 === 0 ? 108 : 100;
    event(at, 144, key, velocity); event(at + gate, 128, key, 64);
  };
  CYCLOPS_SOUND_CHECK_PROGRAMS.forEach((program, i) => {
    const start = i * 4800;
    event(start, 192, program);
    if (i === 0) { event(0, 176, 7, 100); event(0, 176, 10, 64); }
    [60, 64, 67, 72].forEach((key, k) => note(start + k * 480, key, 440));
    note(start + 1920, 67, 1100);
    [60, 64, 67, 72].forEach((key, k) => note(start + 3360 + k * 240, key, 58));
  });
  event(CYCLOPS_SOUND_CHECK_LENGTH, 255, 47, 0);
  const midi = Uint8Array.from(chunk('MThd', [0, 1, 0, 2, 1, 224]).concat(chunk('MTrk', tempo), chunk('MTrk', data)));
  return { midi, settingsKey: 'cyclops-check', info: { key: 'C major', presets: [...CYCLOPS_SOUND_CHECK_PROGRAMS], tempo: Math.round(60e6 / tempoUs), tempo_us: tempoUs, authored: true } };
}
