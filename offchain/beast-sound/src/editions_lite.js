// Monthly Track Editions, onchain size. The four styles that fit beside the Genesis Track in
// BeastMidiProvider (waltz, chorale, lullaby, dirge), as ONE data-driven engine that its Cairo port
// (beasts/beast_composer/src/composition/editions.cairo) reproduces byte for byte. Integer-only:
// scale-degree harmony (diatonic triads), pattern tables for the accompaniment and bass, one track
// per channel written in time order (no sort), mulberry32 seeded by integer mixing.
//
//   editionGenome(e)                        -> the edition's style (e >= 1; 0 is the seeded canon)
//   editionMidi(species, shiny, e, seedKey) -> { midi: Uint8Array (format 1), info }
// `species` = { id, tier, type, tonicPc, degrees } (the Genesis theme's scale degrees); `seedKey`
// = a track seed (an integer, or 'seed:<n>' as the editions page passes it).

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

// ionian, aeolian, harmonic minor, lydian, phrygian
export const SCALES = [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 8, 10], [0, 2, 3, 5, 7, 8, 11], [0, 2, 4, 6, 7, 9, 11], [0, 1, 3, 5, 7, 8, 10]];
export const SCALE_NAMES = ['major', 'minor', 'harmonic minor', 'Lydian', 'Phrygian'];
const NOTE = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];
export const MEGA_LEADS = [50, 65];

// A purchase picks one of its style's accompaniment figures, bass figures and percussion figures.
// Accompaniment events [offset, duration, voice, velocity delta]; voice 0-2 = one tone of the
// triad, 3 = its lowest an octave up, 9 = the whole triad, 10 = the lowest + its octave. Each
// event ends before the next begins (one channel, written in time order).
// Bass events [offset, duration, tone, velocity delta]; tone 0 = root, 1 = fifth below, 2 = fifth
// above, 3 = the root's octave, 4 = tonic and dominant (a drone).
// Percussion events [offset, drum note, velocity delta] on channel 10, 120 ticks each.
export const STYLES = [
  {
    key: 'waltz', label: 'Waltz', noun: 'Waltz', desc: '3/4, oom-pah-pah under a lyrical lead',
    num: 3, den: 4, bpm: [140, 170], modes: [0, 1, 2], chordBars: 1,
    cells: [[4, 2], [2, 2, 2], [6], [3, 1, 2], [2, 1, 1, 2], [1, 1, 2, 2], [2, 4], [1, 1, 1, 1, 2]], end: [[6], [4, 2]],
    accomps: [
      [[480, 288, 9, -6], [960, 288, 9, -12]],
      [[480, 288, 9, -6], [1200, 200, 9, -14]],
      [[480, 220, 0, -8], [720, 220, 1, -12], [960, 220, 2, -10], [1200, 220, 1, -14]],
      [[480, 900, 9, -14]],
    ],
    basses: [[[0, 432, 0, 0]], [[0, 432, 0, 0], [960, 432, 2, -12]], [[0, 1400, 0, -6]]],
    percs: [[[0, 36, -10], [480, 42, -20], [960, 42, -24]], [[0, 36, -10], [960, 42, -20]]],
    palette: [[0, 70, 64], [15, 44, 13], [17, 18, 99], [20, 27, 24], [33, 75, 32]],
    progs: [[0, 5, 3, 4], [0, 3, 4, 0], [0, 4, 5, 3], [5, 3, 0, 4], [0, 1, 4, 0], [0, 2, 5, 4], [3, 4, 0, 5], [0, 5, 1, 4]],
  },
  {
    key: 'chorale', label: 'Chorale / Hymn', noun: 'Hymnal', desc: 'half-note block harmony under a hymn tune, organ',
    num: 4, den: 4, bpm: [66, 84], modes: [0, 2], chordBars: 1,
    cells: [[4, 4], [2, 2, 4], [4, 2, 2], [6, 2], [2, 2, 2, 2]], end: [[8], [4, 4]],
    accomps: [
      [[0, 930, 9, 0], [960, 930, 9, -4]],
      [[0, 1880, 9, -2]],
      [[0, 450, 9, -2], [480, 450, 9, -8], [960, 450, 9, -4], [1440, 450, 9, -8]],
      [[0, 450, 0, -2], [480, 450, 1, -8], [960, 450, 2, -4], [1440, 450, 1, -8]],
    ],
    basses: [[[0, 930, 0, -8], [960, 930, 0, -8]], [[0, 1880, 0, -8]], [[0, 930, 0, -8], [960, 930, 1, -10]]],
    percs: [[[0, 41, -24], [960, 41, -28]], [[0, 45, -24]]],
    palette: [[95, 43, 47], [95, 43, 47], [95, 43, 47], [95, 43, 47], [33, 31, 29]],
    progs: [[0, 3, 4, 0], [0, 5, 3, 4], [0, 1, 4, 0], [3, 0, 1, 4], [0, 4, 5, 3], [5, 1, 4, 0], [0, 3, 1, 4], [0, 2, 3, 4]],
  },
  {
    key: 'lullaby', label: 'Lullaby / Nocturne', noun: 'Lullaby', desc: '6/8, music-box arpeggios, slow lead',
    num: 6, den: 8, bpm: [84, 100], modes: [0, 3, 1], chordBars: 1,
    cells: [[3, 3], [2, 1, 3], [3, 2, 1], [1, 1, 1, 3], [6], [1, 2, 3], [3, 1, 1, 1], [2, 2, 2]], end: [[6], [3, 3]],
    accomps: [
      [[0, 220, 0, 0], [240, 220, 1, -14], [480, 220, 2, -14], [720, 220, 3, 0], [960, 220, 2, -14], [1200, 220, 1, -14]],
      [[0, 220, 0, 0], [240, 220, 2, -14], [480, 220, 1, -14], [720, 220, 3, 0], [960, 220, 1, -14], [1200, 220, 2, -14]],
      [[0, 700, 9, -10], [720, 700, 9, -16]],
      [[0, 220, 0, 0], [240, 220, 1, -14], [480, 220, 2, -14], [720, 220, 0, -4], [960, 220, 1, -14], [1200, 220, 2, -14]],
    ],
    basses: [[[0, 690, 0, -10], [720, 690, 1, -18]], [[0, 1400, 0, -12]], [[0, 690, 0, -10], [720, 690, 2, -18]]],
    percs: [[[0, 42, -30], [720, 42, -30]], [[0, 42, -30], [480, 42, -36], [720, 42, -30], [1200, 42, -36]]],
    palette: [[45, 78, 17], [33, 0, 70], [17, 44, 99], [20, 27, 20], [33, 75, 32]],
    progs: [[0, 3, 0, 4], [0, 5, 3, 4], [0, 4, 5, 3], [3, 4, 0, 0], [0, 1, 4, 0], [0, 3, 5, 4], [5, 3, 4, 0], [0, 2, 3, 4]],
  },
  {
    key: 'dirge', label: 'Dirge', noun: 'Requiem', desc: 'Phrygian, drone bass, tolling bells, long lead lines',
    num: 4, den: 4, bpm: [120, 144], modes: [4, 2], chordBars: 2,
    cells: [[8], [4, 4], [6, 2], [2, 6], [4, 2, 2]], end: [[8], [6, 2]],
    accomps: [
      [[0, 1728, 10, -10]],
      [[0, 900, 10, -10], [960, 900, 9, -16]],
      [[0, 1880, 9, -14]],
      [[0, 400, 3, -8], [480, 400, 0, -14], [960, 400, 3, -10], [1440, 400, 0, -16]],
    ],
    basses: [[[0, 1880, 4, -20]], [[0, 1880, 0, -16]], [[0, 900, 0, -16], [960, 900, 1, -20]]],
    percs: [[[0, 41, -10]], [[0, 43, -12], [960, 41, -18]]],
    palette: [[64, 72, 62], [8, 9, 6], [44, 71, 19], [86, 85, 88], [29, 30, 28]],
    progs: [[0, 1, 0, 0], [0, 3, 0, 1], [0, 5, 3, 0], [0, 3, 6, 0], [0, 6, 5, 0], [0, 1, 3, 0], [5, 6, 0, 0], [0, 4, 1, 0]],
  },
];
/** The drum notes the percussion figures play (their TinyChip drums are in every edition's settings). */
export const EDITION_DRUMS = [...new Set(STYLES.flatMap((S) => S.percs.flat().map((x) => x[1])))].sort((a, b) => a - b);
// a purchase's form: the sections' tunes (A, B, C)
export const FORMS = ['AABA', 'ABAB', 'AABB', 'ABAC'];
const THEMES = ['as written', 'inverted', 'reversed', 'a third up'];
// the parts a purchase may add to its lead and accompaniment, in channel order
export const PARTS = ['descant', 'bass', 'pad', 'percussion'];
const PART_CH = { descant: 1, bass: 3, pad: 4, percussion: 9 };
// a canon entry so the page can label edition 0 (composed by src/lab.js)
export const ENGINES = Object.fromEntries([['canon', { label: 'Canon / Fugue', desc: "today's composer: the species theme in canon, seeded treatment" }], ...STYLES.map((s, i) => [i, s])]);

// ── the calendar ──
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
export const editionMonth = (e) => { const m = 9 + e; return MONTHS[m % 12] + ' ' + (2026 + Math.floor(m / 12)); };
const NAMES = ['Waltz of the Fallen', 'Crypt Hymnal', 'Moonlit Lullaby', 'Requiem in Phrygian'];
const ADJ = ['Ember', 'Hollow', 'Gilded', 'Shattered', 'Sunken', 'Howling', 'Crimson', 'Frost', 'Ashen', 'Verdant', 'Obsidian', 'Wandering', 'Midnight', 'Thorned', 'Silver', 'Abyssal', 'Storm', 'Lantern'];

/** Edition e's style: the four styles in turn from November 2026; each pass through them moves on the mode, tempo and form. */
export function editionGenome(e) {
  if (e === 0) return { engine: 'canon', name: 'The Genesis Canon', month: editionMonth(0), edition: 0, curated: true };
  const style = (e - 1) % 4, S = STYLES[style];
  // each pass of the four styles takes the next mode, a tempo stepping by 7 BPM and the other form
  const pass = Math.floor((e - 1) / 4);
  const mode = S.modes[pass % S.modes.length], bpm = S.bpm[0] + ((pass * 7 + style * 3) % (S.bpm[1] - S.bpm[0] + 1)), form = pass % 2;
  const name = e <= 4 ? NAMES[e - 1] : 'The ' + ADJ[(e * 7) % ADJ.length] + ' ' + S.noun;
  return { engine: style, style, mode, bpm, form, name, month: editionMonth(e), edition: e, curated: e <= 4 };
}

// ── pitch ──
const mod7 = (d) => ((d % 7) + 7) % 7;
const pitch = (base, scale, d) => base + 12 * Math.floor(d / 7) + scale[mod7(d)];
const SNAP = [0, -1, 0, -1, 0, -1, 1]; // to the nearest chord tone, by degree above the root
const snap = (d, c) => d + SNAP[mod7(d - c)];

/** The triad on `c` (degrees) in root position, its root in [lo, lo + 6]. */
function triad(c, lo) {
  const r = lo + mod7(c - lo);
  return [r, r + 2, r + 4];
}

// ── tracks: each channel's notes, written in time order as blocks (all on, then all off) ──
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
const PAN = [64, 46, 82, 64, 64, 88, 100, 0, 0, 64];

/** The track's melody over one section's chords (scale degrees), from `R`. */
function melody(c, chords, lo, hi, motif, full, R) {
  const S = c.S, half = 4, bars = 8, out = [];
  const plan = [], idea = [R.pick(S.cells), R.pick(S.cells)];
  for (let b = 0; b < bars; b++) plan.push(b % half < 2 ? idea[b % 2] : b % half === half - 1 ? R.pick(S.end) : R.pick(S.cells));
  let prev = lo + 3, mi = 0;
  for (let b = 0; b < bars; b++) {
    const ch = chords[b];
    if (b >= half && b < half + 2) { // the consequent restates the antecedent's first two bars
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
 * Edition `e`'s track for a species, shiny or not, and a track seed. The edition sets the style
 * and its tempo; the purchase seed rolls the rest: key, mode, form, the A, B (and C) progressions,
 * the accompaniment, bass and percussion figures, how the tune opens on the species theme, the
 * ornaments and phrasing, and which parts join the lead and accompaniment (descant, bass, pad,
 * percussion: one to four, one more on tiers 1 and 2).
 * On a day of drift `drift` ({ rhythm, rotate, dayKnob, delta }: lab.js drift2, the song layers):
 * the month's new melodies (drawn from its hash; same key, chords and tempo), the week's part swap
 * (one part in or out) and accompaniment voicing (its triads in first or second inversion), and
 * the day's knob (0 the A and B progressions swap, 1 the A and B tunes swap, 2-5 the tempo nudged).
 * `echo` (sound_effects 2 and 3): the chip echo, the lead again 360 ticks later at half velocity
 * on the accompaniment's preset (channel 7). editions.cairo edition_tracks_on byte for byte.
 */
export function editionTrack(sp, shiny, e, seedKey, drift = null, echo = false) {
  const knob = drift ? drift.dayKnob : 6;
  const g = editionGenome(e);
  if (g.engine === 'canon') throw new Error('edition 0 is composed by the canon engine');
  const S = STYLES[g.style];
  const seed = BigInt(String(seedKey).replace(/^seed:/, ''));
  const fold = Number((seed & 0xffffffffn) ^ ((seed >> 32n) & 0xffffffffn));
  const R = rng((fold ^ imul(e, 0x9e3779b1) ^ imul(sp.id, 0x85ebca77)) >>> 0);
  const tonic = (sp.tonicPc + R.pick([0, 0, 0, 5, 7, 10, 2, 3])) % 12;
  const bpm = g.bpm + R.pick([-4, -2, 0, 0, 2, 4]);
  let pA = R.int(8), pB = R.int(8); if (pB === pA) pB = (pA + 1) % 8;
  let pC = (pA + 1 + R.int(6)) % 8; if (pC === pB) pC = (pC + 1) % 8;
  if (knob === 0) [pA, pB] = [pB, pA];
  const mode = S.modes[R.int(S.modes.length)], scale = SCALES[mode];
  const formId = R.int(4), form = FORMS[formId];
  const accomp = S.accomps[R.int(4)], bassFig = S.basses[R.int(3)], perc = S.percs[R.int(2)];
  const theme = R.int(4);
  const orn = [0, 0, 15, 30][R.int(4)], ornSeed = R.int(100), detached = R.int(2) === 1;
  // the parts beside the lead and accompaniment: a seeded order, the first `count` play
  const roll = R.int(100);
  let count = (roll < 20 ? 1 : roll < 60 ? 2 : roll < 88 ? 3 : 4) + (sp.tier <= 2 ? 1 : 0);
  if (count > 4) count = 4;
  const order = [0, 1, 2, 3];
  for (let i = 3; i > 0; i--) { const j = R.int(i + 1); [order[i], order[j]] = [order[j], order[i]]; }
  const playing = order.slice(0, count);
  // the week's drift swaps one part in (or out, when all four play) and inverts the accompaniment
  let rot = 0;
  if (drift && drift.rotate !== null) {
    const h = Number(BigInt(drift.rotate) & 0xffffffffn);
    if (count === 4) playing.splice(h % 4, 1);
    else playing[h % count] = order[count + Math.floor(h / 4) % (4 - count)];
    rot = 1 + Math.floor(h / 16) % 2;
  }
  const on = (part) => playing.includes(PARTS.indexOf(part));
  const bar = S.num * (1920 / S.den);
  const strong2 = S.den === 8 ? 720 : S.num === 4 ? 960 : 0;
  const c = { S, bar, strong: (t) => t % bar === 0 || (strong2 > 0 && t % bar === strong2) };
  const base = tonic < 6 ? 60 + tonic : 48 + tonic, bassBase = base - 24;
  const P = (d) => pitch(base, scale, d), PB = (d) => pitch(bassBase, scale, d);
  const pal = S.palette.map((r) => r[sp.type]);
  if (shiny) { pal[0] = MEGA_LEADS[sp.id % 2]; pal.push(MEGA_LEADS[(sp.id + 1) % 2]); }
  pal[1] = pal[0]; // the descant plays the lead's preset
  pal[6] = pal[2]; // the echo the accompaniment's
  const T = { lead: new Track(), descant: new Track(), accomp: new Track(), bass: new Track(), pad: new Track(), percussion: new Track(), mega: new Track(), echo: new Track() };
  let t0 = 0;
  // the theme as the A tune opens with it: as written, inverted, reversed or a third up
  let motif = sp.degrees.slice(0, 6);
  if (theme === 1) motif = motif.map((d) => -d); else if (theme === 2) motif = motif.reverse(); else if (theme === 3) motif = motif.map((d) => d + 2);
  // the tunes, A (with the theme), B and C: the month's drift draws them from its own hash
  const MR = drift && drift.rhythm !== null ? rng(Number(BigInt(drift.rhythm) & 0xffffffffn)) : R;
  const progOf = [pA, pB, pC];
  const kinds = form.split('').map((x) => x.charCodeAt(0) - 65);
  const sectionChords = (kind) => { const prog = S.progs[progOf[kind]]; return Array.from({ length: 8 }, (_, b) => prog[Math.floor(b / S.chordBars) % 4]); };
  const lastKind = kinds[3];
  const melA = melody(c, sectionChords(0), -1, 9, motif, true, MR);
  const melB = melody(c, sectionChords(1), 1, 11, [], lastKind === 1, MR);
  const melC = formId === 3 ? melody(c, sectionChords(2), 1, 11, [], true, MR) : [];
  const gap = (len) => (detached && len <= 240 ? len >> 1 : 20);
  for (let s = 0; s < 4; s++) {
    const kind = kinds[s];
    const chords = sectionChords(kind);
    const m = kind === 2 ? melC : (kind === 1) !== (knob === 1) ? melB : melA;
    for (const n of m) {
      const t = t0 + n.t, len = n.len - gap(n.len);
      // an upper-neighbour grace note before some long notes
      const grace = orn > 0 && n.len >= 480 && (Math.floor(t / 240) * 7 + (n.d + 70) * 13 + ornSeed) % 100 < orn;
      const voices = [[T.lead, 0, 0, n.t % bar ? 90 : 100]];
      if (shiny) voices.push([T.mega, 5, 12, 70]);
      for (const [tr, ch, up, v] of voices) {
        if (grace) { tr.block(ch, t, 80, [P(n.d + 1) + up], v - 10); tr.block(ch, t + 80, len - 80, [P(n.d) + up], v); }
        else tr.block(ch, t, len, [P(n.d) + up], v);
      }
      // the echo: the lead (no grace notes) 360 ticks later, half as loud, inside the form
      const te = t + 360;
      if (te < 32 * bar) T.echo.block(6, te, Math.min(len, 32 * bar - te), [P(n.d)], (n.t % bar ? 90 : 100) >> 1);
      // the descant: a third above the lead's long notes
      if (n.len >= 480) T.descant.block(1, t, len, [P(n.d + 2)], 64);
    }
    for (let b = 0; b < 8; b++) {
      const t = t0 + b * bar, ch = chords[b];
      const v = triad(ch, -3), vr = [0, 1, 2].map((k) => v[0] + [0, 2, 4, 7, 9][rot + k]);
      for (const [off, d, voice, dv] of accomp) {
        const ps = voice === 9 ? vr.map(P) : voice === 10 ? [P(vr[0]), P(vr[0]) + 12] : voice === 3 ? [P(vr[0]) + 12] : [P(vr[voice])];
        T.accomp.block(2, t + off, d, ps, 72 + dv);
      }
      for (const [off, d, tone, dv] of bassFig) {
        const ps = tone === 4 ? [PB(0), PB(4)] : [PB(ch + [0, -3, 4, 7][tone])];
        T.bass.block(3, t + off, d, ps, 96 + dv);
      }
      if (b % 2 === 0) T.pad.block(4, t, 2 * bar - 40, triad(ch, -7).map(P), 46);
      for (const [off, note, dv] of perc) T.percussion.block(9, t + off, 120, [note], 100 + dv);
    }
    t0 += 8 * bar;
  }
  const ticks = t0;
  // the file: a tempo track, then one track per playing channel (program, volume, pan, reverb, notes)
  let us = Math.round(60e6 / bpm);
  if (knob >= 2 && knob <= 5) { // the day's tempo nudge (drift.cairo nudge_tempo)
    const D = 60000000 + drift.delta * us;
    us = Math.min(1048575, Math.floor((2 * 60000000 * us + D) / (2 * D)));
  }
  const tempo = new Track();
  tempo.msg(0, 0xff, 0x51, 3, (us >> 16) & 255, (us >> 8) & 255, us & 255);
  tempo.msg(0, 0xff, 0x58, 4, S.num, S.den === 8 ? 3 : 2, 24, 8);
  const bodies = [tempo.finish(ticks)];
  const order2 = [['lead', 0], ['descant', 1], ['accomp', 2], ['bass', 3], ['pad', 4], ['percussion', 9]].filter(([name]) => name === 'lead' || name === 'accomp' || on(name));
  if (shiny) order2.push(['mega', 5]);
  if (echo) order2.push(['echo', 6]);
  for (const [name, ch] of order2) {
    const head = new Track();
    head.msg(0, 0xc0 | ch, ch === 9 ? 0 : pal[ch]); head.msg(0, 0xb0 | ch, 7, VOL[ch]); head.msg(0, 0xb0 | ch, 10, PAN[ch]); head.msg(0, 0xb0 | ch, 91, 40);
    bodies.push([...head.b, ...T[name].finish(ticks)]);
  }
  const fig = (xs, x) => String.fromCharCode(65 + xs.indexOf(x));
  const info = {
    edition: e, month: g.month, name: g.name, engine: S.label, desc: S.desc,
    key: NOTE[tonic] + ' ' + SCALE_NAMES[mode], meter: S.num + '/' + S.den, bpm, form: form.split('').join(' '),
    grammar: 'diatonic triads', progA: S.progs[pA].map((d) => ROMAN[d]).join(' '), progB: S.progs[pB].map((d) => ROMAN[d]).join(' '),
    progC: formId === 3 ? S.progs[pC].map((d) => ROMAN[d]).join(' ') : null,
    accomp: S.key + ' ' + fig(S.accomps, accomp), bass: on('bass') ? S.key + ' ' + fig(S.basses, bassFig) : 'none',
    drums: on('percussion') ? S.key + ' ' + fig(S.percs, perc) : 'none', theme: THEMES[theme],
    ornaments: orn ? orn + '% grace notes' : 'none', phrasing: detached ? 'detached' : 'legato',
    parts: ['lead', 'accompaniment', ...PARTS.filter((x) => on(x))], channels: order2.map(([, ch]) => ch),
    seconds: Math.round(ticks / TPQ * 60 / bpm),
  };
  return { bodies, bpm, ticks, info };
}

const u32be = (v) => [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
export function editionMidi(sp, shiny, e, seedKey, drift = null, echo = false) {
  const tr = editionTrack(sp, shiny, e, seedKey, drift, echo);
  const out = [0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, tr.bodies.length, TPQ >> 8, TPQ & 255];
  for (const b of tr.bodies) out.push(0x4d, 0x54, 0x72, 0x6b, ...u32be(b.length), ...b);
  return { midi: Uint8Array.from(out), info: tr.info };
}
