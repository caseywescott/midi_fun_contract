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
//   - Progressions are written in Roman numerals (src/loot_styles.js), 32 a style, 4 or 8 chords long.
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
const LYDIAN = { I: [0, 0], II: [1, 0], iii: [2, 0], V: [4, 0], vi: [5, 0], vii: [6, 0] };
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

const VOL = [100, 64, 74, 100, 58, 62, 70, 0, 0, 70];
export const RARE_LEADS = [47];
/** CC 7 as a mix level (the Beasts mix notes): see editions_lite.js volOf. */
export function volOf(styleKey, ch, prog) {
  const k = styleKey === 'arabian' && ch === 3 ? 837 : styleKey === 'overworld' && ch === 2 ? 837
    : (ch === 0 || ch === 1) && prog === 72 ? 725 : (ch === 0 || ch === 1) && prog === 62 ? 949 : ch === 2 && prog === 99 ? 837 : ch === 4 && prog === 33 ? 1072 : 1000;
  return Math.floor((VOL[ch] * k + 500) / 1000);
}
const PAN = [64, 46, 82, 64, 64, 88, 100, 0, 0, 64];

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
export function editionTrack(sp, mega, e, seedKey, drift = null) {
  const knob = drift ? drift.dayKnob : 6;
  const g = editionGenome(e);
  const S = STYLES[g.style], progs = PROGS[g.style];
  const seed = BigInt(String(seedKey).replace(/^seed:/, ''));
  const fold = Number((seed & 0xffffffffn) ^ ((seed >> 32n) & 0xffffffffn));
  const R = rng((fold ^ imul(e, 0x9e3779b1) ^ imul(sp.id, 0x85ebca77)) >>> 0);
  let tonic = (sp.tonicPc + R.pick([0, 0, 0, 5, 7, 10, 2, 3])) % 12;
  const bpm = g.bpm + R.pick([-4, -2, 0, 0, 2, 4]);
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
  const on = (part) => playing.includes(PARTS.indexOf(part));
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
  const accDown = pal[2] === 99 && Math.floor(ornSeed / 8) % 3 === 0;
  const T = { lead: new Track(), descant: new Track(), accomp: new Track(), bass: new Track(), pad: new Track(), percussion: new Track(), mega: new Track() };
  let t0 = 0;
  let motif = sp.degrees.slice(0, 6);
  if (theme === 1) motif = motif.map((d) => -d); else if (theme === 2) motif = motif.reverse(); else if (theme === 3) motif = motif.map((d) => d + 2);
  const MR = drift && drift.rhythm !== null ? rng(Number(BigInt(drift.rhythm) & 0xffffffffn)) : R;
  const progOf = [pA, pB, pC, pA];
  const kinds = form.split('').map((x) => x.charCodeAt(0) - 65);
  const lastKind = kinds[3];
  // each tune's 8 bars of chords: the progression and its answer (sectionNumerals), drawn from a stream
  // of their own so the purchase's other draws stay as they were; a tune closes on the tonic when its
  // melody ends there (A, C and A' always, B when the form ends on it)
  const H = rng((fold ^ imul(e, 0x27d4eb2d) ^ imul(sp.id, 0x165667b1)) >>> 0);
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
  for (let s = 0; s < 4; s++) {
    const kind = kinds[s];
    const chords = sectionChords(kind);
    const m = kind === 3 ? melD : kind === 2 ? melC : (kind === 1) !== (knob === 1) ? melB : melA;
    for (const n of m) {
      const t = t0 + n.t, len = n.len - gap(n.len);
      const tok = chords[Math.floor(n.t / bar)]; // the bar's chord colours the lead
      const grace = orn > 0 && n.len >= 480 && (Math.floor(t / 240) * 7 + (n.d + 70) * 13 + ornSeed) % 100 < orn;
      const voices = [[T.lead, 0, 0, n.t % bar ? 90 : 100]];
      if (mega) voices.push([T.mega, 5, 12, 70]);
      for (const [tr, ch, up, v] of voices) {
        if (grace && ornKind === 3) { tr.block(ch, t, 60, [P(n.d, tok) + up], v); tr.block(ch, t + 60, 60, [P(n.d + 1, tok) + up], v - 10); tr.block(ch, t + 120, len - 120, [P(n.d, tok) + up], v); }
        else if (grace) { tr.block(ch, t, 80, [P(n.d + [1, -1, -2][ornKind], tok) + up], v - 10); tr.block(ch, t + 80, len - 80, [P(n.d, tok) + up], v); }
        else tr.block(ch, t, len, [P(n.d, tok) + up], v);
      }
      if (n.len >= 480) T.descant.block(1, t, len, [P(n.d + 2, tok)], 64);
    }
    for (let b = 0; b < 8; b++) {
      const t = t0 + b * bar, tok = chords[b], ch = deg(tok);
      const v = triad(ch, -3), vr = [0, 1, 2].map((k) => v[0] + [0, 2, 4, 7, 9][rot + k]);
      // a seventh chord adds its seventh to the whole-chord voicings and the pad
      const seventh = sev(tok) ? [P(v[0] + 6, tok)] : [];
      for (const [off, d, voice, dv] of accomp) {
        const ps = voice === 9 ? [...vr.map((x) => P(x, tok)), ...seventh] : voice === 10 ? [P(vr[0], tok), P(vr[0], tok) + 12] : voice === 3 ? [P(vr[0], tok) + 12] : [P(vr[voice], tok)];
        T.accomp.block(2, t + off, d, accDown ? ps.map((x) => x - 12) : ps, 72 + dv);
      }
      for (const [off, d, tone, dv] of bassFig) {
        const ps = tone === 4 ? [PB(0, 0), PB(4, 0)] : [PB(ch + [0, -3, 4, 7][tone], tok)];
        if (bassMode === 1) { T.bass.block(3, t + off, (d >> 1) - 10, ps, 96 + dv); T.bass.block(3, t + off + (d >> 1), (d >> 1) - 10, ps, 96 + dv); }
        else T.bass.block(3, t + off, bassMode === 2 ? d >> 1 : d, ps, 96 + dv);
      }
      if (b % 2 === 0) { const pv = triad(ch, -7); T.pad.block(4, t, 2 * bar - 40, [...pv.map((x) => P(x, tok)), ...(sev(tok) ? [P(pv[0] + 6, tok)] : [])], 46); }
      for (const [off, note, dv] of perc) T.percussion.block(9, t + off, 120, [note], 100 + dv);
    }
    t0 += 8 * bar;
  }
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
  const order2 = [['lead', 0], ['descant', 1], ['accomp', 2], ['bass', 3], ['pad', 4], ['percussion', 9]].filter(([name]) => name === 'lead' || name === 'accomp' || on(name));
  if (mega) order2.push(['mega', 5]);
  for (const [name, ch] of order2) {
    const head = new Track();
    head.msg(0, 0xc0 | ch, ch === 9 ? 0 : pal[ch]); head.msg(0, 0xb0 | ch, 7, volOf(S.key, ch, ch === 9 ? 0 : pal[ch])); head.msg(0, 0xb0 | ch, 10, PAN[ch]); head.msg(0, 0xb0 | ch, 91, 40);
    bodies.push([...head.b, ...T[name].finish(ticks)]);
  }
  const fig = (xs, x) => String.fromCharCode(65 + xs.indexOf(x));
  const info = {
    edition: e, month: g.month, name: g.name, engine: S.label, desc: S.desc, family: g.style < 6 ? 'Realm of Common Tones' : 'Kingdom of Sweets',
    key: NOTE[tonic] + ' ' + SCALE_NAMES[S.modes[0]], meter: S.num + '/' + S.den, bpm, form: form.split('').map((x) => (x === 'D' ? "A'" : x)).join(' ') + (formId >= 4 ? (newEnding ? " (A' new ending)" : " (A' decorated)") : ''),
    progA: NUM[0].join(' '), progB: NUM[1].join(' '), progC: formId % 4 === 3 ? NUM[2].join(' ') : null,
    accomp: S.source + ' ' + fig(S.accomps, accomp), bass: on('bass') ? S.source + ' ' + fig(S.basses, bassFig) + ['', ' doubled', ' detached'][bassMode] : 'none',
    drums: on('percussion') ? S.source + ' ' + fig(S.percs, perc) : 'none', theme: THEMES[theme],
    ornaments: orn ? orn + '% ' + ['upper graces', 'lower graces', 'slides', 'mordents'][ornKind] : 'none', phrasing: detached ? 'detached' : 'legato',
    parts: ['lead', 'accompaniment', ...PARTS.filter((x) => on(x))], channels: order2.map(([, ch]) => ch),
    programs: Object.fromEntries(order2.map(([name, ch]) => [name, ch === 9 ? 'drums' : pal[ch]])),
    seconds: Math.round(ticks / TPQ * 60 / bpm),
  };
  return { bodies, bpm, ticks, info };
}

const u32be = (v) => [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
export function editionMidi(sp, mega, e, seedKey, drift = null) {
  const tr = editionTrack(sp, mega, e, seedKey, drift);
  const out = [0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, tr.bodies.length, TPQ >> 8, TPQ & 255];
  for (const b of tr.bodies) out.push(0x4d, 0x54, 0x72, 0x6b, ...u32be(b.length), ...b);
  return { midi: Uint8Array.from(out), info: tr.info };
}
