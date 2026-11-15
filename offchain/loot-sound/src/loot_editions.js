// Loot Dungeon Monthly Track Editions: the Beasts edition engine (midi_fun_contract v1.0.1,
// offchain/beast-sound/src/editions_lite.js) with chromatic harmony. Its Cairo port must reproduce it
// byte for byte, so it stays integer-only and data-driven.
//
// What differs from the Beasts engine:
//   - A chord is a scale degree, a colour and an optional seventh. The colour is the scale the chord
//     borrows for its bar (colour 0 is the purchase's home scale). Accompaniment, bass, pad and the
//     lead's notes in that bar use the colour, so mixture chords (bVI, bVII, iv), chromatic mediants
//     (bIII, III), applied dominants (II7, III7, VI7), the Neapolitan and the German sixth sound with
//     a melody that follows them instead of clashing.
//   - Progressions are written in Roman numerals (src/loot_styles.js), 64 a style, 4 or 8 chords long.
//   - Sound effects are 0 (regular) and 1 (mega): no chip echo.
//
//   editionGenome(e)                         -> the edition's style (e >= 1)
//   editionMidi(species, mega, e, seedKey)   -> { midi: Uint8Array (format 1), info }
// `species` = { id, tier, type, tonicPc, degrees } (its Species Song theme's scale degrees).

import { STYLES } from './loot_styles.js';
export { STYLES };

export const TPQ = 480;
const imul = Math.imul;

export function rng(seed) {
  let a = seed >>> 0;
  const f = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = imul(t ^ (t >>> 15), t | 1);
    t ^= t + imul(t ^ (t >>> 7), t | 61);
    return (t ^ (t >>> 14)) >>> 0;
  };
  f.int = (n) => Math.floor((f() * n) / 4294967296);
  f.pick = (xs) => xs[f.int(xs.length)];
  return f;
}

// home scales: ionian, aeolian, harmonic minor, lydian, phrygian (the Beasts engine's mode ids)
export const SCALES = [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10], [0, 2, 3, 5, 7, 8, 11], [0, 2, 4, 6, 7, 9, 11], [0, 1, 3, 5, 7, 8, 10]];
export const SCALE_NAMES = ['major', 'minor', 'harmonic minor', 'Lydian', 'Phrygian'];
// the colours a chord borrows: semitones above the tonic of each degree (colour 0 = the home scale)
export const COLOURS = [
  null,
  [0, 2, 3, 5, 7, 8, 10], // 1 aeolian: bIII, iv, bVI
  [0, 2, 4, 6, 7, 9, 11], // 2 lydian: II (V/V), #iv dim
  [0, 1, 3, 5, 7, 8, 10], // 3 phrygian: bII (the Neapolitan)
  [0, 2, 4, 5, 8, 9, 11], // 4 raised fifth: III (V/vi)
  [0, 2, 4, 5, 7, 8, 11], // 5 harmonic major: vii dim7
  [0, 2, 3, 5, 7, 8, 11], // 6 harmonic minor: V and vii dim7 in minor
  [0, 2, 4, 5, 7, 9, 10], // 7 mixolydian: bVII, v
  [1, 2, 4, 5, 7, 9, 11], // 8 raised tonic: VI (V/ii)
  [0, 2, 3, 5, 6, 8, 11], // 9 German: bVI with the augmented sixth (its seventh, Gb, is F#)
  [0, 2, 4, 5, 7, 9, 11], // 10 ionian: the major I and IV in minor
  [0, 2, 3, 5, 7, 9, 10], // 11 dorian: IV in minor
];
// Roman numerals as [degree, colour, seventh], by the style's home
const MAJOR = {
  I: [0, 0], ii: [1, 0], iii: [2, 0], IV: [3, 0], V: [4, 0], vi: [5, 0], vii: [6, 0],
  V7: [4, 0, 1], ii7: [1, 0, 1], Imaj7: [0, 0, 1], IVmaj7: [3, 0, 1], iii7: [2, 0, 1], vi7: [5, 0, 1], I7: [0, 7, 1], iv7: [3, 1, 1], bVImaj7: [5, 1, 1],
  bIII: [2, 1], iv: [3, 1], bVI: [5, 1], bVII: [6, 7], v: [4, 7],
  N: [1, 3], II: [1, 2], II7: [1, 2, 1], III: [2, 4], III7: [2, 4, 1], VI7: [5, 8, 1], 'vii°7': [6, 5, 1], Ger: [5, 9, 1],
};
const MINOR = {
  i: [0, 0], 'ii°': [1, 0], III: [2, 0], iv: [3, 0], v: [4, 0], VI: [5, 0], VII: [6, 0],
  V: [4, 6], V7: [4, 6, 1], 'vii°7': [6, 6, 1], N: [1, 3], Ger: [5, 9, 1], IV: [3, 11], I: [0, 10], I7: [0, 7, 1],
  i7: [0, 0, 1], iv7: [3, 0, 1], 'iiø7': [1, 0, 1], VImaj7: [5, 0, 1], VII7: [6, 0, 1], II: [1, 2], II7: [1, 2, 1],
};
const LYDIAN = { I: [0, 0], II: [1, 0], iii: [2, 0], V: [4, 0], vi: [5, 0], vii: [6, 0], Imaj7: [0, 0, 1], II7: [1, 0, 1], iii7: [2, 0, 1], Vmaj7: [4, 0, 1], vi7: [5, 0, 1] };
const NUMERALS = { major: MAJOR, minor: MINOR, lydian: LYDIAN };
/** A chord token: degree (bits 0-2), colour (bits 3-6), seventh (bit 7). */
export function chordToken(home, numeral) {
  const x = NUMERALS[home][numeral];
  if (!x) throw new Error(`no ${home} numeral ${numeral}`);
  return x[0] + 8 * x[1] + (x[2] ? 128 : 0);
}
// Substitutes a chord may take in an answering phrase (same function, another colour), by home.
const SUBS = {
  major: { I: ['vi', 'Imaj7', 'iii'], IV: ['ii', 'ii7', 'IVmaj7', 'iv'], V: ['V7', 'vii°7', 'iii'], vi: ['IV', 'vi7'], ii: ['ii7', 'IV'], iii: ['iii7', 'I'], bVI: ['iv', 'bVImaj7'], bVII: ['v', 'IV'], bIII: ['bVI'], V7: ['vii°7'], Imaj7: ['vi7'], IVmaj7: ['ii7'], II: ['II7', 'ii'], II7: ['ii7', 'II'], iv: ['ii', 'bVI'], III7: ['iii7', 'III'], III: ['iii'], VI7: ['vi', 'vi7'], vi7: ['IV'], ii7: ['IV', 'ii'], iii7: ['V'], v: ['bVII'], I7: ['I'] },
  minor: { i: ['VI', 'i7', 'III'], iv: ['iiø7', 'iv7', 'VI'], V: ['V7', 'vii°7'], V7: ['vii°7'], VI: ['iv', 'VImaj7'], VII: ['VII7', 'v'], III: ['i', 'VII'], v: ['VII'], N: ['iv'], 'iiø7': ['iv'], i7: ['iv'], iv7: ['iiø7'], VImaj7: ['iv7'], VII7: ['v'], II: ['iiø7'], I7: ['iv'] },
  lydian: { I: ['vi', 'iii'], II: ['vii'], V: ['iii'], vi: ['I'], iii: ['V'] },
};
/**
 * A section's 8 bars of chords (numerals). An 8-chord progression plays as written. A 4-chord one at
 * one chord a bar plays, then answers: its first chord again (the tune restates its first two bars
 * there), its second chord or a substitute, and a cadence: closed on the tonic when the section's tune
 * ends there, open on the dominant when it does not. At two bars a chord, the last chord gets an
 * approach chord (the cadence's first) in its first bar. `H` draws the choices.
 */
export function sectionNumerals(S, prog, closing, H) {
  // `sub` always takes a substitute when the chord has one; `maybe` half the time
  const sub = (n) => { const xs = SUBS[S.home][n]; return xs ? xs[H.int(xs.length)] : n; };
  const maybe = (n) => (H.int(2) ? sub(n) : n);
  const cads = S.cadences[closing ? 'close' : 'open'], cad = cads[H.int(cads.length)];
  if (prog.length === 8) return prog.slice();
  if (S.chordBars === 1) return [...prog, maybe(prog[0]), sub(prog[1]), cad[0], cad[1]];
  return [prog[0], prog[0], prog[1], sub(prog[1]), prog[2], maybe(prog[2]), cad[0], prog[3]];
}
/** Every style's progressions as chord tokens. */
export const PROGS = STYLES.map((S) => S.progs.map((p) => p.map((n) => chordToken(S.home, n))));
const deg = (tok) => tok & 7, col = (tok) => (tok >> 3) & 15, sev = (tok) => tok >= 128;

const NOTE = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
export const MEGA_LEADS = [50, 65];

export const FORMS = ['AABA', 'ABAB', 'AABB', 'ABAC', 'ADBA', 'ABDB', 'ADBD', 'ABDC'];
const THEMES = ['as written', 'inverted', 'reversed', 'a third up'];
export const PARTS = ['descant', 'bass', 'pad', 'percussion'];
export const EDITION_DRUMS = [...new Set(STYLES.flatMap((S) => S.percs.flat().map((x) => x[1])))].sort((a, b) => a - b);

// ── the calendar: edition 1 is December 2026, the styles in turn ──
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
export const editionMonth = (e) => { const m = 10 + e; return MONTHS[m % 12] + ' ' + (2026 + Math.floor(m / 12)); };
const ADJ = ['Ember', 'Hollow', 'Gilded', 'Shattered', 'Sunken', 'Howling', 'Crimson', 'Frost', 'Ashen', 'Verdant', 'Obsidian', 'Wandering', 'Midnight', 'Thorned', 'Silver', 'Abyssal', 'Storm', 'Lantern'];

/** Edition e's style: the styles in turn; each pass through them moves on the tempo. */
export function editionGenome(e) {
  if (e < 1) throw new Error('editions start at 1');
  const style = (e - 1) % STYLES.length, S = STYLES[style];
  const pass = Math.floor((e - 1) / STYLES.length);
  const bpm = S.bpm[0] + ((pass * 7 + style * 3) % (S.bpm[1] - S.bpm[0] + 1));
  const name = 'The ' + ADJ[(e * 7) % ADJ.length] + ' ' + S.noun;
  return { style, bpm, name, month: editionMonth(e), edition: e };
}

// ── pitch ──
const mod7 = (d) => ((d % 7) + 7) % 7;
const pitch = (base, scale, d) => base + 12 * Math.floor(d / 7) + scale[mod7(d)];
const SNAP = [0, -1, 0, -1, 0, -1, 1];
const snap = (d, c) => d + SNAP[mod7(d - c)];
function triad(c, lo) { const r = lo + mod7(c - lo); return [r, r + 2, r + 4]; }

class Track {
  constructor() { this.b = []; this.time = 0; }
  delta(t) { if (t < this.time) throw new Error('time goes backwards'); let v = t - this.time; this.time = t; const s = [v & 127]; while ((v >>= 7)) s.unshift((v & 127) | 128); this.b.push(...s); }
  msg(t, ...bytes) { this.delta(t); this.b.push(...bytes); }
  block(ch, t, d, ps, v) {
    if (d <= 0) return;
    v = Math.max(1, Math.min(127, v));
    const qs = ps.filter((p) => p >= 0 && p < 128);
    for (const p of qs) this.msg(t, 0x90 | ch, p, v);
    for (const p of qs) this.msg(t + d, 0x80 | ch, p, 0);
  }
  finish(t) { this.msg(Math.max(t, this.time), 0xff, 0x2f, 0); return this.b; }
}

// ── spread chords ──
// In some bars the accompaniment's chords are not struck together: they are rolled (strummed, the notes
// a 64th or a 32nd-triplet apart and held, upward or downward) or broken into an arpeggio at a subdivision of the beat
// (eighths, sixteenths or, rarely, thirty-seconds: each arpeggiated bar draws its own, so the subdivision changes through the
// track; never triplets, which would cross the meter), upward or up and back.
// A purchase draws how many of its bars do this and which way it leans; the choice is made per bar of a
// tune, so a tune's repeat spreads the same bars.
export const SPREAD_SHARES = [20, 35, 50];
export const SPREAD_LEANS = ['rolled', 'arpeggiated', 'rolled and arpeggiated'];
export const SPREAD_NAMES = ['struck', 'rolled up', 'rolled down', 'arpeggio up', 'arpeggio up and back'];
function mix(h, x) { const m = imul((h ^ x) >>> 0, 0x9e3779b1) >>> 0; return (m ^ (m >>> 15)) >>> 0; }
/** How a bar's chords are played: 0 struck, 1-2 rolled up or down, 3-4 an arpeggio up or up and back. */
export function spreadOf(seed, share, lean, kind, bar) {
  const h = mix(seed, kind * 16 + bar);
  if (h % 100 >= share) return 0;
  const arp = lean === 1 || (lean === 2 && (h >>> 8) % 2 === 1);
  return (arp ? 3 : 1) + ((h >>> 12) % 3 === 0 ? 1 : 0);
}
/** An arpeggio's subdivisions in ticks, and their names. */
export const SPREAD_STEPS = [240, 120, 60];
export const STEP_NAMES = { 240: 'eighths', 120: 'sixteenths', 60: 'thirty-seconds' };
/** How often each subdivision is drawn: thirty-seconds are the rare one (1 in 17 where all three fit, 1 in 9
 * beside sixteenths, 1 in 10 where nothing slower fits), only one track in four may use them at all, and
 * such a track keeps them to one bar of one tune (FAST_BARS; the bar comes back when its tune does). */
export const STEP_WEIGHTS = { 240: 8, 120: 8, 60: 1 }, FAST_BARS = 1;
/** The step of a bar's arpeggios: drawn per bar, by weight, from the subdivisions that fit a chord's room
 * at least twice. 0 (the chord is rolled instead) when none fits, and nine times in ten where only
 * thirty-seconds would. */
export function spreadStep(seed, kind, bar, room) {
  const fits = SPREAD_STEPS.filter((s) => room >= 2 * s), h = mix(seed ^ 0x53544550, kind * 16 + bar) >>> 4;
  if (!fits.length) return 0;
  if (fits.length === 1 && fits[0] === 60) return h % 10 === 0 ? 60 : 0;
  const bag = fits.flatMap((s) => Array(STEP_WEIGHTS[s]).fill(s));
  return bag[h % bag.length];
}
/**
 * A chord's notes [time, length, pitch, velocity] played `how`, from tick t for d ticks, with `room`
 * ticks before the part's next event. A roll keeps every note to the chord's end. An arpeggio moves a
 * `step` at a time, once through the chord for a short chord and for as long as the chord lasts for a
 * long one; with no step it is rolled instead.
 */
export function spreadChord(how, t, d, room, pitches, v, step = room >= 720 ? 240 : 120) {
  const ps = [...new Set(pitches.filter((p) => p >= 0 && p < 128))].sort((a, b) => a - b);
  if (how === 0 || ps.length < 2 || d < 100) return ps.map((p) => [t, d, p, v]);
  const n = step ? Math.min(Math.floor(room / step), d >= 480 ? Math.max(2, Math.floor((d + 40) / step)) : ps.length) : 0;
  if (how >= 3 && n >= 2) {
    const cycle = how === 4 && ps.length > 2 ? [...ps, ...ps.slice(1, -1).reverse()] : ps;
    return Array.from({ length: n }, (_, k) => [t + k * step, k === n - 1 ? Math.max(step - 20, d - k * step) : step - 20, cycle[k % cycle.length], k === 0 ? v : v - 6]);
  }
  const gap = Math.min(d >= 400 ? 40 : 20, Math.floor(d / (2 * ps.length))), order = how === 2 || how === 4 ? [...ps].reverse() : ps;
  return order.map((p, k) => [t + k * gap, d - k * gap, p, k === order.length - 1 ? v + 4 : v - 4]);
}

// ── harp glissandi ──
// Now and then a harp sweeps the scale into a section's end, the intro or the ending: a scale step every
// thirty-second note, soft, upward or downward, diatonic, in one of three tracks an octave higher. A
// track has one (11 in 20) or none (9 in 20), never more. It plays on channel 6 (GLISS_CHANNEL).
export const GLISS_CHANNEL = 6, GLISS_STEP = 60;
// a tune's last bar in the drums: fills and cuts out of 20, and the fill (snare, then down the toms)
export const DRUM_FILLS = 7, DRUM_CUTS = 5, DRUM_FILL = [38, 38, 50, 48, 47, 45, 43, 41];
// a second lead, for a B or C tune given to another instrument
export const ALT_CHANNEL = 7, ALT_SHARE = [2, 5]; // two purchases in five
// slower styles and how much faster a purchase may take them, in percent
export const SLOW_TOP = 124, QUICKER = [0, 0, 0, 8, 14, 20, 26, 34, 42];
/** A track's glissando, if it has one, from a draw of 20 and a seed: which of its four places (`weights`
 * lists them, the likelier ones more than once), which way it goes and whether it is an octave higher.
 * A list of one or none. */
export function glissPlan(draw20, seed, weights) {
  const spot = weights[seed % weights.length];
  return draw20 < 9 ? [] : [{ spot, up: ((seed >>> (16 + spot)) & 1) === 1, high: (seed >>> 8) % 3 === 0 }];
}
/** A glissando's notes { t, len, d, v }: `span` ticks of scale steps ending at tick `end`, about the
 * tonic above the bass register (degrees 1 - n/2 to n/2 for n notes; `high`: an octave above that), each
 * ringing on, velocities 43-63 (the sketch's 51-74, 15% quieter). */
export function glissando(plan, end, span, seed, last = end + 480) {
  const n = Math.floor(span / GLISS_STEP), low = 1 - Math.floor(n / 2) + (plan.high ? 7 : 0);
  return Array.from({ length: n }, (_, k) => { const t = end - (n - k) * GLISS_STEP; return { t, len: Math.min(360, last - t), d: plan.up ? low + k : low + n - 1 - k, v: Math.round((51 + mix(seed, k) % 24) * 0.85) }; });
}

/** The styles whose accompaniment the sample bank plays pizzicato: there it sits an octave lower on a
 * third of the purchases, and weekly drift moves it down or back up on about half the weeks. */
export const LOW_ACCOMP_STYLES = ['overworld', 'toymarch', 'sugarplum', 'trepak'];

const VOL = [100, 64, 74, 100, 58, 62, 70, 100, 0, 70];
export const RARE_LEADS = [47];
/** CC 7 as a mix level (the Beasts mix notes): see editions_lite.js volOf. */
export function volOf(styleKey, ch, prog) {
  const k = styleKey === 'arabian' && ch === 3 ? 837 : styleKey === 'overworld' && ch === 2 ? 837
    : (ch === 0 || ch === 1) && prog === 72 ? 725 : (ch === 0 || ch === 1) && prog === 62 ? 949 : ch === 2 && prog === 99 ? 837 : ch === 4 && prog === 33 ? 1072 : 1000;
  return Math.floor((VOL[ch] * k + 500) / 1000);
}
const PAN = [64, 46, 82, 64, 64, 88, 100, 76, 0, 64];

/** A section's melody over its chords' degrees (the Beasts engine's, unchanged). */
function melody(c, degs, lo, hi, motif, full, R) {
  const S = c.S, half = 4, bars = 8, out = [];
  const plan = [], idea = [R.pick(S.cells), R.pick(S.cells)];
  for (let b = 0; b < bars; b++) plan.push(b % half < 2 ? idea[b % 2] : b % half === half - 1 ? R.pick(S.end) : R.pick(S.cells));
  let prev = lo + 3, mi = 0;
  for (let b = 0; b < bars; b++) {
    const ch = degs[b];
    if (b >= half && b < half + 2) {
      for (const n of out.filter((n) => n.t >= (b - half) * c.bar && n.t < (b - half + 1) * c.bar)) {
        const t = n.t + half * c.bar, d = c.strong(t) ? snap(n.d, ch) : n.d;
        out.push({ t, len: n.len, d }); prev = d;
      }
      continue;
    }
    let t = b * c.bar;
    const cell = plan[b];
    cell.forEach((u, i) => {
      const len = u * 240;
      let d;
      if (mi < motif.length) { d = motif[mi++]; while (d > hi) d -= 7; while (d < lo) d += 7; }
      else {
        const target = lo + [3, 5, 6, 5][b % half];
        const dir = prev < target - 1 ? 1 : prev > target + 1 ? -1 : R.int(2) ? 1 : -1;
        const x = R.int(100);
        d = Math.max(lo, Math.min(hi, prev + (x < 12 ? 0 : x < 66 ? dir : x < 90 ? 2 * dir : -dir)));
      }
      if (c.strong(t) || len >= 720) d = snap(d, ch);
      if (i === cell.length - 1 && b === bars - 1 && full) d = prev >= 4 ? 7 : 0;
      else if (i === cell.length - 1 && (b === half - 1 || b === bars - 1)) d = prev >= 1 ? 4 : -3;
      out.push({ t, len, d }); prev = d; t += len;
    });
  }
  return out;
}

/**
 * Edition `e`'s track for a species, mega or not, and a purchase seed (the Beasts engine's draws, in
 * the same order). On a day of drift `drift` ({ rhythm, rotate, dayKnob, delta, day }: the Casey
 * Drift layers) the month brings new melodies and figures, the week swaps a part and inverts the
 * accompaniment, and the day turns one knob.
 */
// A walking bass: a note on every beat, the chord's root on the downbeat, chord tones and passing notes
// between, and a last note a scale step from the next bar's root. WALKS[raw + 6] holds the lines for a
// root that moves by `raw` scale steps (-6 to 6), as steps above the bar's root; the third note falls on
// the bar's second strong beat and is always a chord tone.
export const WALKS = [
  [[0, -3, -5, -7]], [[0, -1, -3, -4]], [[0, -1, -3, -5]],
  [[0, 2, 0, -2], [0, 4, 0, -2]], [[0, 2, 0, -1], [0, 4, 0, -1]], [[0, 4, 2, 0], [0, 2, 0, -2]],
  [[0, 4, 2, 1], [0, 2, 4, 1]],
  [[0, 2, 4, 2], [0, 4, 2, 0]], [[0, 2, 4, 3], [0, 4, 0, 1]], [[0, 1, 2, 4], [0, 2, 4, 2]],
  [[0, 1, 2, 3]], [[0, 1, 2, 4]], [[0, 2, 4, 5]],
];
export const WALK_SHARE = 5, WALK_HITS = 3; // three purchases in five walk (it was one in five), and only for part of the track
// where it walks (tunes 0-3): the second half twice as often as the last tune or the third tune alone
export const WALK_SPANS = [[2, 3], [2, 3], [3], [2]];
export const WALK_SPAN_NAMES = ['the second half', 'the second half', 'the last tune', 'the third tune'];
/** A tune's walking bass: `roots` are its bars' chord degrees, `next` the root of the bar after it (null
 * at the end of the track, where the last bar holds its root). Notes { t, len, d, bar, beat }: `d` a scale
 * degree, to be pitched in bar `bar`'s colour. 4/4 walks in quarters, 3/4 in three, 6/8 long-short
 * twice, 2/4 in two (four across two bars that share a chord). */
export function walkBass(roots, next, num, den, seed) {
  const bar = num * (1920 / den), out = [], n = roots.length;
  const line = (b, to) => { const raw = to - roots[b], v = WALKS[raw + 6]; return v[mix(seed, b) % v.length]; };
  const put = (b, offs, durs, at = 0) => { let t = b * bar + at; offs.forEach((o, i) => { out.push({ t, len: durs[i], d: roots[b] + o, bar: b, beat: i }); t += durs[i]; }); };
  for (let b = 0; b < n; b++) {
    const to = b + 1 < n ? roots[b + 1] : next;
    if (to === null) { put(b, [0], [bar]); continue; }
    if (num === 2 && den === 4) {
      const to2 = b + 2 < n ? roots[b + 2] : next;
      if (b % 2 === 0 && b + 1 < n && roots[b + 1] === roots[b] && to2 !== null) { const w = line(b, to2); put(b, w.slice(0, 2), [480, 480]); put(b + 1, w.slice(2), [480, 480]); b++; continue; }
      const w = line(b, to); put(b, [w[0], w[3]], [480, 480]);
    } else if (den === 8) { put(b, line(b, to), [480, 240, 480, 240]); }
    else if (num === 3) { const w = line(b, to); put(b, [w[0], w[2], w[3]], [480, 480, 480]); }
    else put(b, line(b, to), [480, 480, 480, 480]);
  }
  return out;
}

export function editionTrack(sp, mega, e, seedKey, drift = null, plainChords = false, walk = null, intro = null) {
  const knob = drift ? drift.dayKnob : 6;
  const g = editionGenome(e);
  const S = STYLES[g.style], progs = PROGS[g.style];
  const seed = BigInt(String(seedKey).replace(/^seed:/, ''));
  const fold = Number((seed & 0xffffffffn) ^ ((seed >> 32n) & 0xffffffffn));
  const R = rng((fold ^ imul(e, 0x9e3779b1) ^ imul(sp.id, 0x85ebca77)) >>> 0);
  let tonic = (sp.tonicPc + R.pick([0, 0, 0, 5, 7, 10, 2, 3])) % 12;
  // the slower styles (those that top out at 124 or under) are often taken faster, by anything up to 42%,
  // from a stream of its own: three purchases in nine as written, the rest spread over six steps
  const TP = rng((fold ^ imul(e, 0x5bd1e995) ^ imul(sp.id, 0x1b56c4e9)) >>> 0);
  const quicker = S.bpm[1] <= SLOW_TOP ? QUICKER[TP.int(QUICKER.length)] : 0;
  const bpm = Math.round((g.bpm + R.pick([-4, -2, 0, 0, 2, 4])) * (100 + quicker) / 100);
  // the A, B and C progressions: any of the style's (32), all different
  const NP = progs.length;
  let pA = R.int(NP), pB = R.int(NP); if (pB === pA) pB = (pA + 1) % NP;
  let pC = (pA + 1 + R.int(NP - 2)) % NP; if (pC === pB) pC = (pC + 1) % NP;
  if (knob === 0) [pA, pB] = [pB, pA];
  R.int(S.modes.length); // the mode draw (one home mode per style)
  let formId = R.int(8);
  const accI = R.int(4), bassFig = S.basses[R.int(3)], percI = R.int(2);
  const month = drift && drift.rhythm !== null ? Number(BigInt(drift.rhythm) & 0xffffffffn) : null;
  const scale = SCALES[S.modes[0]];
  const accomp = S.accomps[month !== null ? (accI + 1 + month % 3) % 4 : accI], perc = S.percs[month !== null ? (percI + 1) % 2 : percI];
  if (month !== null) {
    formId = (formId + 1 + Math.floor(month / 64) % 3) % 8;
    const km = Math.floor(month / 256) % 3;
    if (km < 2) tonic = (tonic + [7, 5][km]) % 12;
  }
  const form = FORMS[formId];
  const theme = R.int(4);
  let orn = [0, 0, 15, 30][R.int(4)];
  const ornSeed = R.int(100);
  let detached = R.int(2) === 1;
  if (knob >= 2 && knob <= 5) detached = !detached;
  let ornKind = ornSeed % 4;
  const roll = R.int(100);
  let bassMode = roll % 3;
  let count = (roll < 20 ? 1 : roll < 60 ? 2 : roll < 88 ? 3 : 4) + (sp.tier <= 2 ? 1 : 0);
  if (count > 4) count = 4;
  const order = [0, 1, 2, 3];
  for (let i = 3; i > 0; i--) { const j = R.int(i + 1); [order[i], order[j]] = [order[j], order[i]]; }
  const playing = order.slice(0, count);
  let rot = 0;
  if (drift && drift.rotate !== null) {
    const h = Number(BigInt(drift.rotate) & 0xffffffffn);
    if (count === 4) playing.splice(h % 4, 1);
    else playing[h % count] = order[count + Math.floor(h / 4) % (4 - count)];
    rot = 1 + Math.floor(h / 16) % 2;
    ornKind = (ornKind + 1 + Math.floor(h / 32) % 3) % 4;
    orn = [0, 15, 30, 45, 60][Math.floor(h / 128) % (Math.min(4, 2 + Math.floor(drift.day / 180)) + 1)];
    bassMode = (bassMode + 1 + Math.floor(h / 512) % 2) % 3;
  }
  // the walking bass, from a stream of its own: three purchases in five, for the second half, the last tune
  // or the third tune only; the style's figure plays elsewhere. One week in four trades the walk for the
  // figure or back, and a week moves it to another span; `walk` true or false overrides the draw (true
  // brings the bass in)
  const WK = rng((fold ^ imul(e, 0x51ed270b) ^ imul(sp.id, 0x2f0b4a13)) >>> 0);
  let walking = WK.int(WALK_SHARE) < WALK_HITS;
  const walkSeed = WK();
  let walkSpan = WK.int(WALK_SPANS.length);
  if (drift && drift.rotate !== null) { const h = Number(BigInt(drift.rotate) & 0xffffffffn); if (Math.floor(h / 16384) % 4 === 0) walking = !walking; walkSpan = (walkSpan + Math.floor(h / 65536) % WALK_SPANS.length) % WALK_SPANS.length; }
  if (walk !== null) walking = walk;
  const walksIn = (s) => walking && WALK_SPANS[walkSpan].includes(s);
  const on = (part) => playing.includes(PARTS.indexOf(part)) || (part === 'bass' && walk === true);
  const bar = S.num * (1920 / S.den);
  const strong2 = S.den === 8 ? 720 : S.num === 4 ? 960 : 0;
  const c = { S, bar, strong: (t) => t % bar === 0 || (strong2 > 0 && t % bar === strong2) };
  const base = tonic < 6 ? 60 + tonic : 48 + tonic, bassBase = base - 24;
  // a pitch in a chord's colour: the home scale, or the scale the chord borrows
  const sc = (tok) => (col(tok) === 0 ? scale : COLOURS[col(tok)]);
  const P = (d, tok) => pitch(base, sc(tok), d), PB = (d, tok) => pitch(bassBase, sc(tok), d);
  const pal = S.palette.map((r) => r[sp.type]);
  if (mega) { pal[0] = MEGA_LEADS[sp.id % 2]; pal.push(MEGA_LEADS[(sp.id + 1) % 2]); }
  if (!mega && RARE_LEADS.includes(pal[0]) && (ornSeed + roll) % 4 !== 0) pal[0] = pal[1];
  pal[1] = pal[0];
  let accDown = pal[2] === 99 && Math.floor(ornSeed / 8) % 3 === 0;
  const T = { alt: new Track(), lead: new Track(), descant: new Track(), accomp: new Track(), bass: new Track(), pad: new Track(), percussion: new Track(), mega: new Track() };
  let t0 = 0;
  let motif = sp.degrees.slice(0, 6);
  if (theme === 1) motif = motif.map((d) => -d); else if (theme === 2) motif = motif.reverse(); else if (theme === 3) motif = motif.map((d) => d + 2);
  const MR = drift && drift.rhythm !== null ? rng(Number(BigInt(drift.rhythm) & 0xffffffffn)) : R;
  const progOf = [pA, pB, pC, pA];
  const kinds = form.split('').map((x) => x.charCodeAt(0) - 65);
  const lastKind = kinds[3];
  // On two purchases in five a B tune (or the C tune, when the form has one, half of those times) is led by
  // a second instrument on a channel of its own; every time that tune comes round. A stream of its own.
  const AL = rng((fold ^ imul(e, 0x7ed55d16) ^ imul(sp.id, 0x165667c5)) >>> 0);
  const altDraw = AL.int(ALT_SHARE[1]) < ALT_SHARE[0], altC = AL.int(2) === 0;
  const altKind = !altDraw ? -1 : kinds.includes(2) && altC ? 2 : kinds.includes(1) ? 1 : -1;
  // A tune that follows itself (A A, B B) may come back with the lead doubled in harmony on every note: a
  // third above, or a fourth or a fifth below, in the descant's voice (which then sounds even when the
  // descant part is off). Four such repeats in five, from a stream of its own so the purchase's other
  // draws stay as they were.
  const DB = rng((fold ^ imul(e, 0x3c6ef372) ^ imul(sp.id, 0x1b873593)) >>> 0);
  const doubled = kinds.map((k, s) => (s > 0 && k === kinds[s - 1] && (DB.int(2) === 0 || DB.int(5) < 3) ? [2, -3, -4][DB.int(3)] : 0));
  // and the first pass of such a pair is left plain (no descant either), so the harmony arrives with the repeat
  const plainPass = kinds.map((k, s) => s < 3 && kinds[s + 1] === k);
  // each tune's 8 bars of chords: the progression and its answer (sectionNumerals), drawn from a stream
  // of their own so the purchase's other draws stay as they were; a tune closes on the tonic when its
  // melody ends there (A, C and A' always, B when the form ends on it)
  const H = rng((fold ^ imul(e, 0x27d4eb2d) ^ imul(sp.id, 0x165667b1)) >>> 0);
  // the spread chords, from a stream of their own too: the month spreads other bars, the week changes
  // how many and which way they lean
  const SP = rng((fold ^ imul(e, 0x2545f491) ^ imul(sp.id, 0x61c88647)) >>> 0);
  let spreadShare = SP.int(3), spreadLean = SP.int(3), spreadSeed = SP();
  if (month !== null) spreadSeed = mix(spreadSeed, month);
  if (drift && drift.rotate !== null) { const h = Number(BigInt(drift.rotate) & 0xffffffffn); spreadShare = (spreadShare + 1 + Math.floor(h / 2048) % 2) % 3; spreadLean = (spreadLean + 1 + Math.floor(h / 4096) % 2) % 3; }
  let accLow = SP.int(3) === 0;
  if (drift && drift.rotate !== null && Math.floor(Number(BigInt(drift.rotate) & 0xffffffffn) / 8192) % 2 === 1) accLow = !accLow;
  if (!LOW_ACCOMP_STYLES.includes(S.key)) accLow = false;
  if (accLow) accDown = true;
  if (plainChords) spreadShare = -1;
  // harp glissandi: into the second, third or fourth tune, or into the end; the week moves them
  const GL = rng((fold ^ imul(e, 0x7feb352d) ^ imul(sp.id, 0x846ca68b)) >>> 0);
  const glDraw = GL.int(20);
  let glSeed = GL();
  if (drift && drift.rotate !== null) glSeed = mix(glSeed, Number(BigInt(drift.rotate) & 0xffffffffn));
  const glPlan = glissPlan(glDraw, glSeed, [3, 3, 1, 0, 2]), glEv = [];
  let spreadBars = 0, chordBars = 0, rolledBars = 0;
  const stepsUsed = new Set(), fastBars = new Set();
  const NUM = [0, 1, 2, 3].map((kind) => sectionNumerals(S, S.progs[progOf[kind]], kind !== 1 || lastKind === 1, H));
  const sectionChords = (kind) => NUM[kind].map((n) => chordToken(S.home, n));
  const degsOf = (kind) => sectionChords(kind).map(deg);
  const melA = melody(c, degsOf(0), -1, 9, motif, true, MR);
  const melB = melody(c, degsOf(1), 1, 11, [], lastKind === 1, MR);
  const melC = formId % 4 === 3 ? melody(c, degsOf(2), 1, 11, [], true, MR) : [];
  const newEnding = Math.floor(ornSeed / 4) % 2 === 0;
  let melD = [];
  if (formId >= 4) {
    if (newEnding) {
      const fresh = melody(c, degsOf(0), -1, 9, motif, true, MR);
      melD = [...melA.filter((n) => n.t < 4 * bar), ...fresh.filter((n) => n.t >= 4 * bar)];
    } else {
      melD = melA.flatMap((n, i) => {
        const nx = melA[i + 1];
        if (n.len < 480 || !nx) return [n];
        const h = n.len >> 1;
        return [{ t: n.t, len: h, d: n.d }, { t: n.t + h, len: n.len - h, d: n.d + (nx.d < n.d ? -1 : 1) }];
      });
    }
  }
  const gap = (len) => (detached && len <= 240 ? len >> 1 : 20);
  // How each tune's last bar goes in the drums, from a stream of its own: 7 times in 20 a fill of snare and
  // toms over its second half, 5 in 20 a cut (the drums drop out for the bar, as a dance track mutes them
  // before the next section), otherwise the pattern as usual.
  const DF = rng((fold ^ imul(e, 0x2c1b3c6d) ^ imul(sp.id, 0x297a2d39)) >>> 0), halfBar = bar >> 1;
  const drumEnds = [0, 1, 2, 3].map(() => { const r = DF.int(20); return r < DRUM_FILLS ? 1 : r < DRUM_FILLS + DRUM_CUTS ? 2 : 0; });
  // An intro before the first tune, on half the purchases, from a stream of its own: one to four bars (two to
  // four in 2/4) that close on the dominant. It is a dialogue: the lead calls with the opening of the tune,
  // a step lower for each bar still to go, and the accompaniment's instrument answers half a bar later at
  // another pitch (a fourth or a sixth below, or a third above), sometimes turned upside down; under them a
  // pad and, more often than not, a bass line that moves against the call. A longer intro opens with a bar of
  // the accompaniment alone. The drums keep out of the way: a soft count on the hat and a quiet fill, no
  // crash. Now and then, and quietly, a run of sixteenths into the tune or an arpeggio through the chord.
  // Each layer plays only if its part is in the track. `intro` false leaves it out, true or a number of bars
  // puts it in. The tunes after it are note for note what they are without it.
  const IN = rng((fold ^ imul(e, 0x6a09e667) ^ imul(sp.id, 0x3c6ef35f)) >>> 0);
  let introBars = IN.int(2) === 0 ? 1 + IN.int(4) : 0;
  const inKind = IN.int(4), inUp = IN.int(3) > 0;
  // the dialogue: the answer's interval (a fourth below, a third above, a sixth below), whether it is turned
  // upside down, whether the bass moves against the call; the run and the arpeggio are the exception
  const inAnswer = [-3, 2, -5][IN.int(3)], inMirror = IN.int(2) === 0, inCounter = IN.int(3) > 0, inRun = IN.int(4) === 0, inArp = inKind === 3 && IN.int(2) === 0;
  if (intro !== null) introBars = intro === false ? 0 : intro === true ? introBars || 2 : Math.max(0, Math.min(4, intro | 0));
  if (introBars === 1 && S.num === 2) introBars = 2;
  const introHas = [];
  if (introBars) {
    const N = introBars, plan = (S.home === 'minor' ? ['i', 'VI', 'iv', 'V'] : S.home === 'lydian' ? ['I', 'II', 'I', 'V'] : ['I', 'vi', 'IV', 'V']).slice(4 - N).map((x) => chordToken(S.home, x));
    const sub = 120, first = melA.length ? melA[0].d : 0, half = bar >> 1, runLen = Math.floor(half / sub), dir = inUp ? 1 : -1;
    // the call: what the tune's first bar plays in its first half (its first note, cut to fit, when it has none)
    let call = melA.filter((n) => n.t + n.len <= half);
    if (!call.length && melA.length) call = [{ t: 0, len: half, d: first }];
    const note = (what) => { if (!introHas.includes(what)) introHas.push(what); };
    for (let k = 0; k < N; k++) {
      const t = k * bar, tok = plan[k], ch = deg(tok), last = k === N - 1, swell = Math.round(14 * (k + 1) / N), seq = k - (N - 1); // each bar a step higher, the last at the tune's own pitch
      const groove = N >= 3 && k === 0; // a longer intro opens with the accompaniment alone
      if (on('pad')) { note('pad'); T.pad.block(4, t, bar - 40, [...triad(ch, -7).map((x) => P(x, tok)), ...(sev(tok) ? [P(triad(ch, -7)[0] + 6, tok)] : [])], 34 + swell); }
      if (on('bass')) {
        if (inCounter && !groove && call.length > 1) { // a line against the call: where the call rises it falls, then the root
          note('a counter-line in the bass');
          for (const n of call) T.bass.block(3, t + n.t, n.len - 20, [PB(ch - (n.d - first), tok)], 70 + swell);
          T.bass.block(3, t + half, half - 30, [PB(ch, tok)], 68 + swell);
        } else { note('a bass pedal'); T.bass.block(3, t, bar - 30, [PB(ch, tok)], 68 + swell); }
      }
      const v = triad(ch, -3), vr = [0, 1, 2].map((j) => v[0] + [0, 2, 4, 7, 9][rot + j]), low = accDown ? -12 : 0;
      if (last && inArp) { // now and then, quietly: up through two octaves of the chord and back
        note('an arpeggio through the chord'); const steps = [0, 2, 4, 7, 9, 11, 14], count = Math.floor(bar / sub);
        for (let i = 0; i < count; i++) { const up = i < count / 2 ? i : count - 1 - i; T.accomp.block(2, t + i * sub, sub - 10, [P(v[0] + steps[up % 7], tok) + low], 36 + Math.round(16 * i / count)); }
      } else if (groove) {
        note('the accompaniment figure'); const ev = [];
        accomp.forEach(([off, d, voice, dv], j) => { const ps = voice === 9 ? vr.map((x) => P(x, tok)) : voice === 10 ? [P(vr[0], tok), P(vr[0], tok) + 12] : voice === 3 ? [P(vr[0], tok) + 12] : [P(vr[voice], tok)], room = (j + 1 < accomp.length ? accomp[j + 1][0] : bar) - off, len = Math.max(30, Math.min(d, room) - 10);
          for (const x of ps) ev.push([t + off, 1, 0x90 | 2, x + low, Math.max(1, Math.min(127, 50 + swell + dv))], [t + off + len, 0, 0x80 | 2, x + low, 0]); });
        ev.sort((a, b2) => a[0] - b2[0] || a[1] - b2[1]); for (const [at, , ...msg] of ev) T.accomp.msg(at, ...msg);
      } else if (call.length) { // the response: the call again half a bar later, in the accompaniment's voice, at another pitch
        note('call and response between the lead and the accompaniment' + (inMirror ? ', the answer turned upside down' : ''));
        for (const n of call) T.accomp.block(2, t + half + n.t, n.len - gap(n.len), [P((inMirror ? first - (n.d - first) : n.d) + seq + inAnswer, tok)], 62 + swell);
      }
      if (!groove) for (const n of call) T.lead.block(0, t + n.t, n.len - gap(n.len), [P(n.d + seq, tok)], 70 + swell);
      if (last && inRun) { // now and then, quietly: a run that arrives a step from the tune
        note('a quiet run ' + (inUp ? 'up' : 'down') + ' into the tune');
        for (let i = 0; i < runLen; i++) T.lead.block(0, t + half + i * sub, sub - 15, [P(first - (runLen - i) * dir, tok)], 44 + Math.round(14 * i / runLen));
      }
      if (on('percussion')) {
        const beats = S.den === 8 ? [0, 720] : Array.from({ length: S.num }, (_, j) => j * 480);
        if (N > 1) { note('a soft count on the hat'); for (const off of beats.filter((x) => !last || x < half)) T.percussion.block(9, t + off, 100, [42], 34 + (swell >> 1)); }
        if (last) { note('a quiet drum fill'); const fill = [38, 38, 50, 48, 47, 45, 43, 41]; for (let i = 0; i < runLen; i++) T.percussion.block(9, t + half + i * sub, 100, [fill[Math.min(fill.length - 1, Math.floor(i * fill.length / runLen))]], 28 + Math.round(16 * i / runLen)); }
      }
    }
    t0 = N * bar;
  }
  const introTicks = t0;
  for (let s = 0; s < 4; s++) {
    const kind = kinds[s];
    const chords = sectionChords(kind);
    const m = kind === 3 ? melD : kind === 2 ? melC : (kind === 1) !== (knob === 1) ? melB : melA;
    for (const n of m) {
      const t = t0 + n.t, len = n.len - gap(n.len);
      const tok = chords[Math.floor(n.t / bar)]; // the bar's chord colours the lead
      const grace = orn > 0 && n.len >= 480 && (Math.floor((t - introTicks) / 240) * 7 + (n.d + 70) * 13 + ornSeed) % 100 < orn; // counted from the first tune, so an intro leaves the tunes as they were
      const voices = [kind === altKind ? [T.alt, ALT_CHANNEL, 0, n.t % bar ? 90 : 100] : [T.lead, 0, 0, n.t % bar ? 90 : 100]];
      if (mega) voices.push([T.mega, 5, 12, 70]);
      for (const [tr, ch, up, v] of voices) {
        if (grace && ornKind === 3) { tr.block(ch, t, 60, [P(n.d, tok) + up], v); tr.block(ch, t + 60, 60, [P(n.d + 1, tok) + up], v - 10); tr.block(ch, t + 120, len - 120, [P(n.d, tok) + up], v); }
        else if (grace) { tr.block(ch, t, 80, [P(n.d + [1, -1, -2][ornKind], tok) + up], v - 10); tr.block(ch, t + 80, len - 80, [P(n.d, tok) + up], v); }
        else tr.block(ch, t, len, [P(n.d, tok) + up], v);
      }
      if (doubled[s]) T.descant.block(1, t, len, [P(n.d + doubled[s], tok)], 70);
      else if (n.len >= 480 && on('descant') && !plainPass[s]) T.descant.block(1, t, len, [P(n.d + 2, tok)], 64);
    }
    for (let b = 0; b < 8; b++) {
      const t = t0 + b * bar, tok = chords[b], ch = deg(tok);
      const v = triad(ch, -3), vr = [0, 1, 2].map((k) => v[0] + [0, 2, 4, 7, 9][rot + k]);
      // a seventh chord adds its seventh to the whole-chord voicings and the pad
      const seventh = sev(tok) ? [P(v[0] + 6, tok)] : [];
      const how = spreadShare < 0 ? 0 : spreadOf(spreadSeed, SPREAD_SHARES[spreadShare], spreadLean, kind, b);
      if (accomp.some((x) => x[2] >= 9)) { chordBars++; if (how) spreadBars++; }
      const ev = [];
      accomp.forEach(([off, d, voice, dv], k) => {
        const ps = voice === 9 ? [...vr.map((x) => P(x, tok)), ...seventh] : voice === 10 ? [P(vr[0], tok), P(vr[0], tok) + 12] : voice === 3 ? [P(vr[0], tok) + 12] : [P(vr[voice], tok)];
        const room = (k + 1 < accomp.length ? accomp[k + 1][0] : bar) - off;
        let step = how >= 3 && voice >= 9 ? spreadStep(spreadSeed, kind, b, room) : 0;
        // thirty-seconds in one bar of one tune at most: elsewhere sixteenths, or a roll where those do not fit
        if (step === 60 && !fastBars.has(kind * 16 + b)) { if ((spreadSeed >>> 20) % 4 === 0 && fastBars.size < FAST_BARS) fastBars.add(kind * 16 + b); else step = room >= 240 ? 120 : 0; }
        if (voice >= 9 && how) { if (step && Math.floor(room / step) >= 2) stepsUsed.add(step); else rolledBars++; }
        for (const [nt, nl, p, nv] of spreadChord(voice >= 9 ? how : 0, t + off, d, room, accDown ? ps.map((x) => x - 12) : ps, 72 + dv, step)) ev.push([nt, 1, 0x90 | 2, p, Math.max(1, Math.min(127, nv))], [nt + nl, 0, 0x80 | 2, p, 0]);
      });
      ev.sort((a, b2) => a[0] - b2[0] || a[1] - b2[1]);
      for (const [at, , ...msg] of ev) T.accomp.msg(at, ...msg);
      if (walksIn(s)) {
        if (b === 0) {
          const nk = s < 3 ? kinds[s + 1] : -1;
          for (const n of walkBass(chords.map(deg), nk < 0 ? null : deg(sectionChords(nk)[0]), S.num, S.den, mix(mix(walkSeed, s), month === null ? 0 : month))) T.bass.block(3, t0 + n.t, n.len - (bassMode === 2 ? n.len >> 2 : 30), [PB(n.d, chords[n.bar])], n.beat ? 88 : 98);
        }
      } else for (const [off, d, tone, dv] of bassFig) {
        const ps = tone === 4 ? [PB(0, 0), PB(4, 0)] : [PB(ch + [0, -3, 4, 7][tone], tok)];
        if (bassMode === 1) { T.bass.block(3, t + off, (d >> 1) - 10, ps, 96 + dv); T.bass.block(3, t + off + (d >> 1), (d >> 1) - 10, ps, 96 + dv); }
        else T.bass.block(3, t + off, bassMode === 2 ? d >> 1 : d, ps, 96 + dv);
      }
      if (b % 2 === 0) { const pv = triad(ch, -7); T.pad.block(4, t, 2 * bar - 40, [...pv.map((x) => P(x, tok)), ...(sev(tok) ? [P(pv[0] + 6, tok)] : [])], 46); }
      // the last bar of a tune: the pattern, or a fill over its second half, or the drums cut out altogether
      const ending = b === 7 ? drumEnds[s] : 0;
      if (ending !== 2) for (const [off, note, dv] of perc) if (ending === 0 || off < halfBar) T.percussion.block(9, t + off, 120, [note], 100 + dv);
      if (ending === 1) { const count = Math.floor(halfBar / 120); for (let i = 0; i < count; i++) T.percussion.block(9, t + halfBar + i * 120, 100, [DRUM_FILL[Math.min(DRUM_FILL.length - 1, Math.floor(i * DRUM_FILL.length / count))]], 58 + Math.round(26 * i / count)); }
    }
    t0 += 8 * bar;
    const gl = glPlan.find((x) => x.spot === s);
    if (gl) {
      // in the last bar's chord colour, over its last half bar (a bar of 2/4)
      const tok = chords[7];
      for (const n of glissando(gl, t0, S.den === 8 ? 720 : Math.min(bar, 960), glSeed, s === 3 ? t0 : t0 + 480)) glEv.push([n.t, 1, 0x90 | GLISS_CHANNEL, P(n.d, tok), n.v], [n.t + n.len, 0, 0x80 | GLISS_CHANNEL, P(n.d, tok), 0]);
    }
  }
  glEv.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  T.gliss = new Track();
  for (const [at, , ...msg] of glEv) T.gliss.msg(at, ...msg);
  const ticks = t0;
  let us = Math.round(60e6 / bpm);
  if (knob >= 2 && knob <= 5) {
    const D = 60000000 + drift.delta * us;
    us = Math.min(1048575, Math.floor((2 * 60000000 * us + D) / (2 * D)));
  }
  const tempo = new Track();
  tempo.msg(0, 0xff, 0x51, 3, (us >> 16) & 255, (us >> 8) & 255, us & 255);
  tempo.msg(0, 0xff, 0x58, 4, S.num, S.den === 8 ? 3 : 2, 24, 8);
  const bodies = [tempo.finish(ticks)];
  const order2 = [['lead', 0], ['descant', 1], ['accomp', 2], ['bass', 3], ['pad', 4], ['percussion', 9]].filter(([name]) => name === 'lead' || name === 'accomp' || on(name) || (name === 'descant' && doubled.some(Boolean)));
  if (mega) order2.push(['mega', 5]);
  if (glEv.length) order2.push(['gliss', GLISS_CHANNEL]);
  if (altKind >= 0) order2.push(['alt', ALT_CHANNEL]);
  const progOf2 = (ch) => (ch === 9 ? 0 : ch === GLISS_CHANNEL || ch === ALT_CHANNEL ? pal[2] : pal[ch]);
  for (const [name, ch] of order2) {
    const head = new Track();
    head.msg(0, 0xc0 | ch, progOf2(ch)); head.msg(0, 0xb0 | ch, 7, volOf(S.key, ch, progOf2(ch))); head.msg(0, 0xb0 | ch, 10, PAN[ch]); head.msg(0, 0xb0 | ch, 91, 40);
    bodies.push([...head.b, ...T[name].finish(ticks)]);
  }
  const fig = (xs, x) => String.fromCharCode(65 + xs.indexOf(x));
  const info = {
    edition: e, month: g.month, name: g.name, engine: S.label, desc: S.desc, family: S.family ?? (g.style < 6 ? 'Realm of Common Tones' : 'Kingdom of Sweets'),
    key: NOTE[tonic] + ' ' + SCALE_NAMES[S.modes[0]], meter: S.num + '/' + S.den, bpm, form: form.split('').map((x) => (x === 'D' ? "A'" : x)).join(' ') + (formId >= 4 ? (newEnding ? " (A' new ending)" : " (A' decorated)") : ''),
    progA: NUM[0].join(' '), progB: NUM[1].join(' '), progC: formId % 4 === 3 ? NUM[2].join(' ') : null,
    accomp: S.source + ' ' + fig(S.accomps, accomp) + (accDown ? ' · an octave lower' : ''), accompLow: accDown,
    chords: !chordBars ? 'the figure has no chords' : plainChords ? 'struck' : SPREAD_LEANS[spreadLean] + ' in ' + spreadBars + ' of ' + chordBars + ' bars' + (stepsUsed.size ? ' · arpeggios in ' + SPREAD_STEPS.filter((x) => stepsUsed.has(x)).map((x) => STEP_NAMES[x]).join(', ') : ''),
    spread: { bars: spreadBars, rolled: rolledBars, steps: SPREAD_STEPS.filter((x) => stepsUsed.has(x)) }, bass: !on('bass') ? 'none' : S.source + ' ' + fig(S.basses, bassFig) + ['', ' doubled', ' detached'][bassMode] + (walking ? ' · walking in ' + WALK_SPAN_NAMES[walkSpan] : ''), walking: walking && on('bass'), walkTunes: walking && on('bass') ? WALK_SPANS[walkSpan] : [],
    drums: on('percussion') ? S.source + ' ' + fig(S.percs, perc) + [1, 2].map((k) => { const at = drumEnds.map((x, i) => (x === k ? i + 1 : 0)).filter(Boolean); return at.length ? ' · ' + ['', 'a fill', 'cut'][k] + ' at the end of tune' + (at.length > 1 ? 's ' : ' ') + at.join(', ') : ''; }).join('') : 'none', drumEnds: on('percussion') ? drumEnds : [0, 0, 0, 0], theme: THEMES[theme],
    secondLead: altKind < 0 ? 'none' : 'the ' + 'ABC'[altKind] + ' tune', altKind, quicker,
    intro: introBars ? introBars + (introBars > 1 ? ' bars: ' : ' bar: ') + introHas.join(', ') : 'none', introBars, introTicks,
    doubling: doubled.some(Boolean) ? doubled.map((iv, k) => (iv ? 'tune ' + (k + 1) + ' in ' + { 2: 'thirds above', [-3]: 'fourths below', [-4]: 'fifths below' }[iv] : '')).filter(Boolean).join(', ') : 'none', doubled,
    ornaments: orn ? orn + '% ' + ['upper graces', 'lower graces', 'slides', 'mordents'][ornKind] : 'none', phrasing: detached ? 'detached' : 'legato',
    parts: ['lead', 'accompaniment', ...PARTS.filter((x) => on(x))], channels: order2.map(([, ch]) => ch),
    programs: Object.fromEntries(order2.map(([name, ch]) => [name, ch === 9 ? 'drums' : progOf2(ch)])),
    glissandi: glPlan.length ? glPlan.map((x) => (x.up ? 'up' : 'down') + (x.high ? ', an octave higher,' : '') + (x.spot === 3 ? ' into the end' : ' into tune ' + (x.spot + 2))).join(', ') : 'none', gliss: glPlan,
    seconds: Math.round(ticks / TPQ * 60 / bpm),
  };
  return { bodies, bpm, ticks, info };
}

const u32be = (v) => [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
export function editionMidi(sp, mega, e, seedKey, drift = null, plainChords = false, walk = null, intro = null) {
  const tr = editionTrack(sp, mega, e, seedKey, drift, plainChords, walk, intro);
  const out = [0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, tr.bodies.length, TPQ >> 8, TPQ & 255];
  for (const b of tr.bodies) out.push(0x4d, 0x54, 0x72, 0x6b, ...u32be(b.length), ...b);
  return { midi: Uint8Array.from(out), info: tr.info };
}
