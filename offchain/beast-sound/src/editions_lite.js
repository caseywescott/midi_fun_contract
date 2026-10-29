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

import { nudgeTempo } from './evolution.js';

export const TPQ = 480;
const MAX_TEMPO_US = 1048575;
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

// Accompaniment events [offset, duration, voice, velocity delta]; voice 0-2 = one tone of the
// triad, 3 = its lowest an octave up, 9 = the whole triad, 10 = the lowest + its octave.
// Bass events [offset, duration, tone, velocity delta]; tone 0 = root, 1 = fifth below, 4 = tonic
// and dominant (a drone). No drums or counter line: they did not fit beside the Genesis Track.
export const STYLES = [
  {
    key: 'waltz', label: 'Waltz', noun: 'Waltz', desc: '3/4, oom-pah-pah under a lyrical lead',
    num: 3, den: 4, bpm: [140, 170], modes: [0, 1, 2], chordBars: 1,
    cells: [[4, 2], [2, 2, 2], [6], [3, 1, 2], [2, 1, 1, 2]], end: [[6], [4, 2]],
    accomp: [[480, 288, 9, -6], [960, 288, 9, -12]], bass: [[0, 432, 0, 0]],
    palette: [[0, 70, 64], [15, 44, 13], [17, 18, 99], [20, 27, 24], [33, 75, 32]],
    progs: [[0, 5, 3, 4], [0, 3, 4, 0], [0, 4, 5, 3], [5, 3, 0, 4]],
  },
  {
    key: 'chorale', label: 'Chorale / Hymn', noun: 'Hymnal', desc: 'half-note block harmony under a hymn tune, organ',
    num: 4, den: 4, bpm: [66, 84], modes: [0, 2], chordBars: 1,
    cells: [[4, 4]], end: [[8]],
    accomp: [[0, 930, 9, 0], [960, 930, 9, -4]], bass: [[0, 930, 0, -8], [960, 930, 0, -8]],
    palette: [[95, 43, 47], [95, 43, 47], [95, 43, 47], [95, 43, 47], [33, 31, 29]],
    progs: [[0, 3, 4, 0], [0, 5, 3, 4], [0, 1, 4, 0], [3, 0, 1, 4]],
  },
  {
    key: 'lullaby', label: 'Lullaby / Nocturne', noun: 'Lullaby', desc: '6/8, music-box arpeggios, slow lead, no drums',
    num: 6, den: 8, bpm: [84, 100], modes: [0, 3, 1], chordBars: 1,
    cells: [[3, 3], [2, 1, 3], [3, 2, 1], [1, 1, 1, 3], [6]], end: [[6], [3, 3]],
    accomp: [[0, 220, 0, 0], [240, 220, 1, -14], [480, 220, 2, -14], [720, 220, 3, 0], [960, 220, 2, -14], [1200, 220, 1, -14]],
    bass: [[0, 690, 0, -10], [720, 690, 1, -18]],
    palette: [[45, 78, 17], [33, 0, 70], [17, 44, 99], [20, 27, 20], [33, 75, 32]],
    progs: [[0, 3, 0, 4], [0, 5, 3, 4], [0, 4, 5, 3], [3, 4, 0, 0]],
  },
  {
    key: 'dirge', label: 'Dirge', noun: 'Requiem', desc: 'Phrygian, drone bass, tolling bells, long lead lines',
    num: 4, den: 4, bpm: [120, 144], modes: [4, 2], chordBars: 2,
    cells: [[8], [4, 4], [6, 2]], end: [[8]],
    accomp: [[0, 1728, 10, -10]], bass: [[0, 1880, 4, -20]],
    palette: [[64, 72, 62], [8, 9, 6], [44, 71, 19], [86, 85, 88], [29, 30, 28]],
    progs: [[0, 1, 0, 0], [0, 3, 0, 1], [0, 5, 3, 0], [0, 3, 6, 0]],
  },
];
export const FORMS = ['AABA', 'ABAB'];
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

// ── tracks: each channel's notes as blocks (all on, then all off), kept until the file is written,
// track by track as editions.cairo writes them, so a staff's note performance (`perf`) draws in the
// same order ──
class Track {
  constructor() { this.b = []; this.time = 0; this.blocks = []; }
  delta(t) { if (t < this.time) throw new Error('time goes backwards'); let v = t - this.time; this.time = t; const s = [v & 127]; while ((v >>= 7)) s.unshift((v & 127) | 128); this.b.push(...s); }
  msg(t, ...bytes) { this.delta(t); this.b.push(...bytes); }
  block(ch, t, d, ps, v) {
    if (d <= 0) return;
    this.blocks.push([ch, t, d, ps.filter((p) => p >= 0 && p < 128), Math.max(1, Math.min(127, v))]);
  }
  /** The blocks, on `pf` (editions.cairo `Perf`): each note's velocity moved within +-extent (1..127)
   * and, by chance (basis points), a note of an eighth or longer's second half an octave away. */
  write(pf) {
    for (const [ch, t, d, qs, v] of this.blocks) {
      const vel = [], split = [];
      for (const _ of qs) {
        const r = lcg(pf) % (2 * pf.extent + 1), x = v + r;
        vel.push(x <= pf.extent ? 1 : x - pf.extent > 127 ? 127 : x - pf.extent);
        split.push(d >= 120 && lcg(pf) % 10000 < pf.chance);
      }
      const half = Math.floor(d / 2);
      qs.forEach((p, i) => this.msg(t, 0x90 | ch, p, vel[i]));
      qs.forEach((p, i) => { if (split[i]) { this.msg(t + half, 0x80 | ch, p, 0); this.msg(t + half, 0x90 | ch, octave(p), vel[i]); } });
      qs.forEach((p, i) => this.msg(t + d, 0x80 | ch, split[i] ? octave(p) : p, 0));
    }
  }
  finish(t) { this.msg(Math.max(t, this.time), 0xff, 0x2f, 0); return this.b; }
}
const lcg = (pf) => (pf.state = (1664525 * pf.state + 1013904223) % 4294967296);
const octave = (p) => (p > 96 ? p - 12 : p + 12);

const VOL = [100, 78, 74, 100, 58, 62];
const PAN = [64, 46, 82, 64, 64, 88];

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
 * Edition `e`'s track for a species, shiny or not, and a track seed. On a staff (`staff`: the
 * controls of evolution.js `resolveEvolution`, with one extra role, the pad of tiers 3 to 5) the
 * pad joins when unlocked, the notes are performed and the tempo nudged: editions.cairo
 * `edition_tracks_on` byte for byte.
 */
export function editionTrack(sp, shiny, e, seedKey, staff = null) {
  const g = editionGenome(e);
  if (g.engine === 'canon') throw new Error('edition 0 is composed by the canon engine');
  const S = STYLES[g.style], scale = SCALES[g.mode];
  const seed = BigInt(String(seedKey).replace(/^seed:/, ''));
  const fold = Number((seed & 0xffffffffn) ^ ((seed >> 32n) & 0xffffffffn));
  const R = rng((fold ^ imul(e, 0x9e3779b1) ^ imul(sp.id, 0x85ebca77)) >>> 0);
  const tonic = (sp.tonicPc + R.pick([0, 0, 0, 5, 7, 10, 2, 3])) % 12;
  const bpm = g.bpm + R.pick([-4, -2, 0, 0, 2, 4]);
  const pA = R.int(4); let pB = R.int(4); if (pB === pA) pB = (pA + 1) % 4;
  const bar = S.num * (1920 / S.den);
  const strong2 = S.den === 8 ? 720 : S.num === 4 ? 960 : 0;
  const c = { S, bar, strong: (t) => t % bar === 0 || (strong2 > 0 && t % bar === strong2) };
  const base = tonic < 6 ? 60 + tonic : 48 + tonic, bassBase = base - 24;
  const P = (d) => pitch(base, scale, d), PB = (d) => pitch(bassBase, scale, d);
  const pal = S.palette.map((r) => r[sp.type]);
  if (shiny) { pal[0] = MEGA_LEADS[sp.id % 2]; pal.push(MEGA_LEADS[(sp.id + 1) % 2]); }
  const T = { lead: new Track(), accomp: new Track(), bass: new Track(), pad: new Track(), mega: new Track() };
  const form = FORMS[g.form], mel = {};
  let t0 = 0;
  const pad = sp.tier <= 2 || (staff !== null && staff.unlocked_extra_mask % 2 === 1);
  for (let s = 0; s < 4; s++) {
    const isB = form[s] === 'B', prog = isB ? S.progs[pB] : S.progs[pA];
    const chords = Array.from({ length: 8 }, (_, b) => prog[Math.floor(b / S.chordBars) % 4]);
    const lo = isB ? 1 : -1, hi = lo + 10;
    const m = mel[form[s]] || (mel[form[s]] = melody(c, chords, lo, hi, s === 0 ? sp.degrees.slice(0, 6) : [], !isB, R));
    for (const n of m) {
      T.lead.block(0, t0 + n.t, n.len - 20, [P(n.d)], n.t % bar ? 90 : 100);
      if (shiny) T.mega.block(5, t0 + n.t, n.len - 20, [P(n.d) + 12], 70);
    }
    for (let b = 0; b < 8; b++) {
      const t = t0 + b * bar, ch = chords[b];
      const v = triad(ch, -3);
      for (const [off, d, voice, dv] of S.accomp) {
        const ps = voice === 9 ? v.map(P) : voice === 10 ? [P(v[0]), P(v[0]) + 12] : voice === 3 ? [P(v[0]) + 12] : [P(v[voice])];
        T.accomp.block(2, t + off, d, ps, 72 + dv);
      }
      for (const [off, d, tone, dv] of S.bass) {
        const ps = tone === 4 ? [PB(0), PB(4)] : [PB(tone === 1 ? ch - 3 : ch)];
        T.bass.block(3, t + off, d, ps, 96 + dv);
      }
      if (pad && b % 2 === 0) T.pad.block(4, t, 2 * bar - 40, triad(ch, -7).map(P), 46);
    }
    t0 += 8 * bar;
  }
  const ticks = t0;
  // the file: a tempo track, then one track per channel (program, volume, pan, reverb, notes)
  let us = Math.round(60e6 / bpm);
  const pf = { state: 0, extent: 0, chance: 0 };
  if (staff) {
    us = Math.min(MAX_TEMPO_US, nudgeTempo(us, staff.tempo_delta));
    Object.assign(pf, { state: Number(BigInt(staff.note_seed) % 4294967296n), extent: staff.max_velocity_delta, chance: staff.ornament_chance_bps });
  }
  const tempo = new Track();
  tempo.msg(0, 0xff, 0x51, 3, (us >> 16) & 255, (us >> 8) & 255, us & 255);
  tempo.msg(0, 0xff, 0x58, 4, S.num, S.den === 8 ? 3 : 2, 24, 8);
  const bodies = [tempo.finish(ticks)];
  const order = [['lead', 0], ['accomp', 2], ['bass', 3], ['pad', 4]];
  if (shiny) order.push(['mega', 5]);
  for (const [name, ch] of order) {
    T[name].write(pf);
    const head = new Track();
    head.msg(0, 0xc0 | ch, pal[ch]); head.msg(0, 0xb0 | ch, 7, VOL[ch]); head.msg(0, 0xb0 | ch, 10, PAN[ch]); head.msg(0, 0xb0 | ch, 91, 40);
    bodies.push([...head.b, ...T[name].finish(ticks)]);
  }
  const info = {
    edition: e, month: g.month, name: g.name, engine: S.label, desc: S.desc,
    key: NOTE[tonic] + ' ' + SCALE_NAMES[g.mode], meter: S.num + '/' + S.den, bpm, form: form.split('').join(' '),
    grammar: 'diatonic triads', progA: S.progs[pA].map((d) => ROMAN[d]).join(' '), progB: S.progs[pB].map((d) => ROMAN[d]).join(' '),
    accomp: S.key, bass: S.key, drums: 'none', seconds: Math.round(ticks / TPQ * 60 / bpm),
  };
  return { bodies, bpm, ticks, info };
}

const u32be = (v) => [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
export function editionMidi(sp, shiny, e, seedKey, staff = null) {
  const tr = editionTrack(sp, shiny, e, seedKey, staff);
  const out = [0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, tr.bodies.length, TPQ >> 8, TPQ & 255];
  for (const b of tr.bodies) out.push(0x4d, 0x54, 0x72, 0x6b, ...u32be(b.length), ...b);
  return { midi: Uint8Array.from(out), info: tr.info };
}
