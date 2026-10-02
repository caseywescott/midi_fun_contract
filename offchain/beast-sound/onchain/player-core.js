// Pure parts of the TinySynth page player (no DOM, no WebAudio), shared with the Node tests.
//
// TinySynth parses a MIDI file into `song = { timebase, ev: [{ t, m }] }`: `t` is the absolute tick
// in the file's own units and `timebase` is ticks per whole note (4 × PPQN), i.e. one 4/4 bar.

/** Page orchestration version. Changing anything below that changes the sound is a new version. */
export const ORCHESTRATION = 1;

/** Extra program slot after General MIDI's 0..127, for the page's own lead. */
export const LEAD_PROGRAM = 128;

/**
 * The chip lead, as close as TinySynth gets to the previous page's triangle lead: a triangle with a
 * 3 ms attack, full sustain and a 2-frame (33 ms) release, plus 6 Hz, 30-cent vibrato faded in over
 * 0.2 s (TinySynth timbre fields: g output, w wave, t/f frequency ratio/offset, v level, a/h/d/s/r
 * envelope, p/q pitch sweep, k key tracking).
 */
export const LEAD = [
  { g: 0, w: 'triangle', t: 1, f: 0, v: 0.3, a: 0.003, h: 0.01, d: 0.01, s: 1, r: 0.033, p: 1, q: 1, k: 0 },
  { g: 1, w: 'triangle', t: 0, f: 6, v: 2 ** (30 / 1200) - 1, a: 0.2, h: 0, d: 0.01, s: 1, r: 0.033, p: 1, q: 1, k: 0 },
];

/** General MIDI percussion keys used by the accompaniment (channel 10). */
export const DRUM_KEYS = { kick: 36, snare: 38, hat: 42, openhat: 46 };

/**
 * A bare score sets no programs and uses no percussion channel. Those get the page orchestration;
 * anything else plays exactly as written.
 */
export function isBareScore(events) {
  return !events.some(({ m }) => (m[0] & 0xf0) === 0xc0 || (m[0] >= 0x80 && m[0] < 0xf0 && (m[0] & 0x0f) === 9));
}

/** Channels with at least one note-on, ascending. */
export function noteChannels(events) {
  const set = new Set();
  for (const { m } of events) if ((m[0] & 0xf0) === 0x90 && m[2] > 0) set.add(m[0] & 0x0f);
  return [...set].sort((a, b) => a - b);
}

/** Loop length: the score rounded up to whole 4/4 bars (as the previous page's scheduler did). */
export function loopEndTicks(maxTick, timebase) {
  return Math.ceil(maxTick / timebase) * timebase;
}

/** Voices spread from -0.85 to 0.85, as a MIDI pan controller value (64 = centre). */
export function panValue(index, count) {
  const pan = count < 2 ? 0 : -0.85 + (1.7 * index) / (count - 1);
  return 64 + pan * 64;
}

/**
 * The previous page's drum pass (server/scheduler.js `drumPass`) at any PPQN: kick on beat 1, snare
 * on beat 3, hi-hat on every eighth at ±30% level, about 1 in 8 off-beats opened. Returns
 * [{ time, kind, level }].
 */
export function drumPass(loopTicks, ppq, random = Math.random) {
  const out = [];
  const eighth = ppq / 2;
  for (let time = 0; time < loopTicks; time += eighth) {
    const onBeat = time % ppq === 0, beat = time / ppq;
    if (onBeat && beat % 4 === 0) out.push({ time, kind: 'kick', level: 0.32 });
    if (onBeat && beat % 4 === 2) out.push({ time, kind: 'snare', level: 0.16 });
    const open = !onBeat && random() < 0.125;
    const level = (onBeat ? 0.075 : 0.05) * (0.7 + random() * 0.6);
    out.push({ time, kind: open ? 'openhat' : 'hat', level });
  }
  return out;
}

/** Drum levels as velocities: TinySynth's amplitude goes with velocity², so velocity ∝ √level. */
export function drumVelocity(level) {
  return Math.max(1, Math.min(127, Math.round(127 * Math.sqrt(level / 0.32))));
}

/** The accompaniment as TinySynth song events on channel 10. */
export function drumEvents(loopTicks, ppq, random = Math.random) {
  return drumPass(loopTicks, ppq, random).map((d) => ({ t: d.time, m: [0x99, DRUM_KEYS[d.kind], drumVelocity(d.level)] }));
}

/** Base64 MIDI text (whitespace allowed) to bytes; null unless it is a Standard MIDI File. */
export function decodeMidi(text, atobFn = globalThis.atob) {
  try {
    const bin = atobFn(String(text).replace(/\s+/g, ''));
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return bytes.length >= 14 && bin.startsWith('MThd') ? bytes : null;
  } catch {
    return null;
  }
}
