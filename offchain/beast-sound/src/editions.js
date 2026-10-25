// Monthly Track Editions (prototype). Every bought track takes the style of the UTC month it was
// minted in: an edition = a style engine + a genome (meter, tempo, harmony, accompaniment, bass,
// drums, preset palette). The Beast carries into every style (species tonic, the opening of its
// Genesis theme as a motif cameo, its type's palette shade, the mega lead when shiny); the track
// seed (the mint block hash) picks the song inside the style. Edition 0 is today's seeded canon and
// is composed by the existing engine (src/lab.js), not here.
//
//   editionGenome(e)                       -> the edition's style (curated 0-11, procedural after)
//   editionTrack(species, shiny, e, seed)  -> { notes, programs, bpm, meter, ticks, info }
//   editionMidi(...)                       -> the same as a self-contained format-0 SMF (Uint8Array)

export const TPQ = 480;
const EIGHTH = 240;

// ── randomness ───────────────────────────────────────────────────────────────────────────────────
export function hash32(...parts) {
  let h = 2166136261 >>> 0;
  for (const ch of parts.map(String).join('|')) { h ^= ch.charCodeAt(0); h = Math.imul(h, 16777619) >>> 0; }
  h ^= h >>> 13; h = Math.imul(h, 0x5bd1e995) >>> 0; h ^= h >>> 15;
  return h >>> 0;
}
export function rng(seed) {
  let a = seed >>> 0;
  const f = () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  f.int = (n) => Math.floor(f() * n);
  f.pick = (xs) => xs[f.int(xs.length)];
  f.chance = (p) => f() < p;
  f.range = (lo, hi) => lo + f.int(hi - lo + 1);
  return f;
}

// ── scales and chords ────────────────────────────────────────────────────────────────────────────
export const SCALES = {
  ionian: [0, 2, 4, 5, 7, 9, 11], dorian: [0, 2, 3, 5, 7, 9, 10], phrygian: [0, 1, 3, 5, 7, 8, 10],
  lydian: [0, 2, 4, 6, 7, 9, 11], mixolydian: [0, 2, 4, 5, 7, 9, 10], aeolian: [0, 2, 3, 5, 7, 8, 10],
  harmonic: [0, 2, 3, 5, 7, 8, 11], phrygdom: [0, 1, 4, 5, 7, 8, 10], locrian: [0, 1, 3, 5, 6, 8, 10],
};
const QUAL = {
  M: [0, 4, 7], m: [0, 3, 7], o: [0, 3, 6], '+': [0, 4, 8], 7: [0, 4, 7, 10], m7: [0, 3, 7, 10],
  M7: [0, 4, 7, 11], mM7: [0, 3, 7, 11], 'ø7': [0, 3, 6, 10], o7: [0, 3, 6, 9], sus: [0, 5, 7],
};
const DEG = { I: 0, II: 2, III: 4, IV: 5, V: 7, VI: 9, VII: 11 };
const NOTE = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

/** A Roman numeral ('bVI', 'ii7', 'V7/vi', 'IM7', 'iio') as { r: root semitones over the tonic, q, tones }. */
export function parseChord(tok) {
  const [main, of] = tok.split('/');
  const base = of ? parseChord(of).r : 0;
  const m = /^([b#]?)([ivIV]+)(.*)$/.exec(main);
  if (!m) throw new Error('chord ' + tok);
  const [, acc, rn, suf] = m, upper = rn === rn.toUpperCase();
  const r = (base + DEG[rn.toUpperCase()] + (acc === 'b' ? -1 : acc === '#' ? 1 : 0) + 24) % 12;
  const q = suf === '' ? (upper ? 'M' : 'm') : suf === '7' ? (upper ? '7' : 'm7') : suf === 'M7' ? (upper ? 'M7' : 'mM7') : suf;
  if (!QUAL[q]) throw new Error('quality ' + tok);
  return { r, q, tones: QUAL[q], name: tok };
}

export const GRAMMARS = {
  pop: { scale: 'ionian', label: 'pop diatonic', progs: ['I V vi IV', 'I vi IV V', 'vi IV I V', 'I IV vi V', 'I V IV V', 'IV I V vi'] },
  romantic: { scale: 'ionian', label: 'Romantic: secondary dominants, borrowed iv', progs: ['I vi ii7 V7', 'I V7/vi vi IV', 'I IV iv I', 'I V7/ii ii7 V7', 'I iii IV iv', 'ii7 V7 I V7/IV'] },
  minor: { scale: 'aeolian', label: 'natural minor', progs: ['i bVII bVI bVII', 'i iv bVII bIII', 'i bVI bIII bVII', 'i bVI iv V', 'i iv i V'] },
  harmonic: { scale: 'harmonic', label: 'harmonic minor', progs: ['i iv V7 i', 'i bVI iio V7', 'i V7/iv iv V', 'i bVI iv V7', 'iv i V7 i'] },
  dorian: { scale: 'dorian', label: 'Dorian vamp', progs: ['i IV i IV', 'i ii bIII IV', 'i bVII IV i', 'i IV bVII i'] },
  mixo: { scale: 'mixolydian', label: 'Mixolydian rock', progs: ['I bVII IV I', 'I bVII bVI bVII', 'I IV bVII IV', 'I v IV I'] },
  mediant: { scale: 'ionian', label: 'chromatic mediants (fantasy)', progs: ['I bVI I bIII', 'I III IV iv', 'I bVI bVII I', 'I iii bVI IV', 'I bIII IV I', 'vi IV I bVI'] },
  andalusian: { scale: 'phrygdom', label: 'Andalusian / Phrygian dominant', progs: ['i bVII bVI V', 'i bII i V', 'iv bIII bII i', 'i bII bIII bII'] },
  lydian: { scale: 'lydian', label: 'Lydian float', progs: ['I II I II', 'I II iii II', 'IV II I II', 'I II vii IV'] },
  blues: { scale: 'mixolydian', label: '12-bar blues', twelve: true, progs: ['I7 IV7 I7 I7 IV7 IV7 I7 I7 V7 IV7 I7 V7', 'I7 IV7 I7 I7 IV7 IV7 I7 V7/V V7 IV7 I7 V7'] },
  jazzy: { scale: 'ionian', label: 'bossa sevenths', progs: ['IM7 ii7 iii7 V7/ii', 'ii7 V7 IM7 VI7', 'IM7 bVII7 IM7 IV7', 'IM7 V7/V ii7 V7', 'IM7 IVM7 iii7 vi7'] },
  hymn: { scale: 'ionian', label: 'hymn', progs: ['I IV V I', 'I vi IV V', 'I ii V I', 'IV I ii V', 'I V vi iii', 'vi IV I V'] },
  hymnminor: { scale: 'harmonic', label: 'minor hymn', progs: ['i iv V i', 'i bVI iv V', 'i iio V i', 'bVI iv V i'] },
  dirge: { scale: 'phrygian', label: 'Phrygian dirge', progs: ['i bII i i', 'i bII bIII bII', 'i iv bII i', 'i bvii bII i'] },
};

// ── preset pools (TinyChip bank program numbers) ─────────────────────────────────────────────────
export const MEGA_LEADS = [50, 65];

// The engines. Each lists what its genome may take; the curated editions use the first option of
// each list, procedural ones pick. Palettes are [Magic, Hunter, Brute] per role.
export const ENGINES = {
  canon: { label: 'Canon / Fugue', noun: 'Canon', desc: "today's composer: the species theme in canon, seeded treatment" },
  waltz: {
    label: 'Waltz', noun: 'Waltz', desc: '3/4, oom-pah-pah, lyrical lead over a countermelody', meter: [3, 4], bpm: [140, 170],
    grammars: ['romantic', 'harmonic', 'minor', 'mediant'], forms: ['AABA', 'ABAB', 'AABB'], accomp: ['waltz'], bass: ['waltz'], drums: ['waltz', 'none'], feel: 'waltz', counter: 'line', chordBars: 1,
    palette: { lead: [0, 70, 64], counter: [15, 44, 13], accomp: [17, 18, 99], bass: [20, 27, 24], pad: [33, 75, 32] },
  },
  chorale: {
    label: 'Chorale / Hymn', noun: 'Hymnal', desc: 'four voices in block harmony, half-note chords, organ', meter: [4, 4], bpm: [66, 84],
    grammars: ['hymn', 'hymnminor', 'romantic'], forms: ['AABA', 'ABAB'], accomp: ['chorale'], bass: ['chorale'], drums: ['none'], feel: 'slow', counter: 'none', chordBars: 0.5,
    palette: { lead: [95, 43, 47], counter: [95, 43, 47], accomp: [95, 43, 47], bass: [95, 43, 47], pad: [33, 31, 29] },
  },
  groove: {
    label: 'Groove / Ostinato', noun: 'Groove', desc: 'bass riff from the species motif, offbeat stabs, call-and-response lead, rock drums', meter: [4, 4], bpm: [108, 126],
    grammars: ['dorian', 'mixo', 'minor'], forms: ['AABA', 'ABAB', 'AAB'], accomp: ['stab', 'strum'], bass: ['riff'], drums: ['rock', 'halftime'], feel: 'call', counter: 'none', chordBars: 1,
    palette: { lead: [59, 1, 84], counter: [94, 66, 5], accomp: [66, 14, 94], bass: [61, 79, 88], pad: [28, 30, 29] },
  },
  anthem: {
    label: 'Chip Anthem', noun: 'Anthem', desc: 'fast, 16th arpeggios, heroic lead in thirds, chromatic-mediant harmony, driving drums', meter: [4, 4], bpm: [150, 172],
    grammars: ['mediant', 'pop', 'mixo'], forms: ['ABAB', 'AABA', 'AABB'], accomp: ['arp16'], bass: ['octave8'], drums: ['drive', 'rock'], feel: 'heroic', counter: 'thirds', chordBars: 1,
    palette: { lead: [53, 62, 4], counter: [76, 82, 77], accomp: [34, 80, 35], bass: [21, 22, 23], pad: [31, 90, 30] },
  },
  phase: {
    label: 'Phase / Minimal', noun: 'Phases', desc: 'the motif looped in two voices of different lengths drifting apart, pedal bass, bells', meter: [4, 4], bpm: [112, 132],
    grammars: ['lydian', 'dorian', 'pop'], forms: ['AABB', 'ABAB'], accomp: ['phase'], bass: ['pedal'], drums: ['minimal', 'none'], feel: 'slow', counter: 'phase', chordBars: 2,
    palette: { lead: [97, 45, 78], counter: [17, 99, 44], accomp: [97, 74, 19], bass: [27, 20, 26], pad: [75, 33, 32] },
  },
  song: {
    label: 'Song (verse / chorus)', noun: 'Ballad', desc: 'verse low and sparse, chorus higher with full drums, piano strum, vocal-style lead', meter: [4, 4], bpm: [84, 100],
    grammars: ['pop', 'minor', 'mixo'], forms: ['VCVC', 'VVCC'], accomp: ['strum', 'block'], bass: ['rootfifth'], drums: ['halftime', 'rock'], feel: 'vocal', counter: 'line', chordBars: 1,
    palette: { lead: [42, 68, 89], counter: [7, 0, 6], accomp: [18, 46, 17], bass: [26, 93, 25], pad: [32, 54, 90] },
  },
  variations: {
    label: 'Theme & Variations', noun: 'Variations', desc: 'one 8-bar tune: plain, in 16ths, in minor, as a march, then home', meter: [4, 4], bpm: [96, 112],
    grammars: ['hymn', 'romantic', 'pop'], forms: ['TV'], accomp: ['alberti'], bass: ['root'], drums: ['none'], feel: 'lyric', counter: 'line', chordBars: 1,
    palette: { lead: [52, 69, 3], counter: [13, 15, 12], accomp: [18, 46, 17], bass: [20, 24, 22], pad: [33, 31, 29] },
  },
  lullaby: {
    label: 'Lullaby / Nocturne', noun: 'Lullaby', desc: '6/8, slow broken chords over two octaves, music-box lead, no drums', meter: [6, 8], bpm: [84, 100],
    grammars: ['pop', 'lydian', 'romantic', 'minor'], forms: ['AABA', 'ABAB'], accomp: ['musicbox'], bass: ['sixeight'], drums: ['none'], feel: 'compound', counter: 'line', chordBars: 1,
    palette: { lead: [45, 78, 17], counter: [33, 0, 70], accomp: [17, 44, 99], bass: [20, 27, 20], pad: [33, 75, 32] },
  },
  blues: {
    label: 'Shuffle Blues', noun: 'Blues', desc: '12-bar blues, swung eighths, boogie bass, call-and-response riffs', meter: [4, 4], bpm: [100, 124],
    grammars: ['blues'], forms: ['AAA', 'AA'], accomp: ['shuffle'], bass: ['boogie'], drums: ['shuffle'], feel: 'call', counter: 'response', chordBars: 1, swing: true,
    palette: { lead: [96, 51, 84], counter: [46, 18, 66], accomp: [46, 18, 66], bass: [93, 26, 79], pad: [43, 95, 29] },
  },
  bossa: {
    label: 'Bossa', noun: 'Bossa', desc: 'bossa nova groove, seventh chords, syncopated comping, gentle lead', meter: [4, 4], bpm: [128, 144],
    grammars: ['jazzy'], forms: ['AABA', 'ABAB'], accomp: ['bossa'], bass: ['bossa'], drums: ['bossa'], feel: 'lyric', counter: 'line', chordBars: 1,
    palette: { lead: [70, 42, 98], counter: [0, 7, 64], accomp: [46, 17, 99], bass: [26, 27, 93], pad: [32, 75, 54] },
  },
  dirge: {
    label: 'Dirge', noun: 'Requiem', desc: 'Phrygian, drone bass, tolling toms, long lead lines', meter: [4, 4], bpm: [120, 144],
    grammars: ['dirge', 'andalusian', 'harmonic'], forms: ['AABA', 'ABAB'], accomp: ['tolling'], bass: ['drone'], drums: ['dirge'], feel: 'slow', counter: 'line', chordBars: 2,
    palette: { lead: [64, 72, 62], counter: [8, 9, 6], accomp: [44, 71, 19], bass: [86, 85, 88], pad: [29, 30, 28] },
  },
  march: {
    label: 'March', noun: 'March', desc: 'snare-driven march, oom-pah bass, brass lead with a countermelody in thirds', meter: [4, 4], bpm: [112, 124],
    grammars: ['pop', 'romantic', 'harmonic'], forms: ['AABB', 'ABAB'], accomp: ['oompah'], bass: ['rootfifth'], drums: ['march'], feel: 'march', counter: 'thirds', chordBars: 1,
    palette: { lead: [47, 81, 53], counter: [5, 3, 2], accomp: [94, 14, 16], bass: [24, 22, 58], pad: [29, 28, 30] },
  },
};
export const ENGINE_LIST = Object.keys(ENGINES).filter((k) => k !== 'canon');

// Role pools for procedural editions: a new month can bring timbres from the whole bank.
const POOLS = {
  lead: [0, 1, 2, 3, 4, 7, 8, 9, 42, 51, 52, 53, 59, 62, 64, 68, 69, 70, 73, 76, 77, 82, 89, 96, 98],
  counter: [5, 6, 7, 12, 13, 15, 17, 44, 45, 63, 67, 74, 97, 99],
  accomp: [12, 14, 16, 17, 18, 19, 44, 46, 71, 74, 97, 99],
  bass: [20, 21, 22, 23, 24, 25, 26, 27, 58, 61, 79, 85, 88, 93],
  pad: [28, 29, 30, 31, 32, 33, 54, 75, 90],
};

// ── the calendar ─────────────────────────────────────────────────────────────────────────────────
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
/** Edition e's UTC month: edition 0 = October 2026. */
export const editionMonth = (e) => { const m = 9 + e; return MONTHS[m % 12] + ' ' + (2026 + Math.floor(m / 12)); };
/** The edition of a mint timestamp (seconds, UTC). */
export function editionOfTimestamp(ts) { const d = new Date(ts * 1000); return (d.getUTCFullYear() - 2026) * 12 + d.getUTCMonth() - 9; }

export const CURATED = [
  { engine: 'canon', name: 'The Genesis Canon' },
  { engine: 'waltz', name: 'Waltz of the Fallen' },
  { engine: 'chorale', name: 'Crypt Hymnal' },
  { engine: 'groove', name: 'Iron Groove' },
  { engine: 'anthem', name: 'Dungeon Anthem' },
  { engine: 'phase', name: 'Clockwork Phases' },
  { engine: 'song', name: 'Tavern Ballad' },
  { engine: 'variations', name: 'Variations on a Beast' },
  { engine: 'lullaby', name: 'Moonlit Lullaby' },
  { engine: 'blues', name: 'Boneyard Blues' },
  { engine: 'bossa', name: 'Sunken Bossa' },
  { engine: 'dirge', name: 'Requiem in Phrygian' },
];
const ADJ = ['Ember', 'Hollow', 'Gilded', 'Shattered', 'Sunken', 'Howling', 'Crimson', 'Frost', 'Ashen', 'Verdant', 'Obsidian', 'Wandering', 'Midnight', 'Thorned', 'Silver', 'Abyssal', 'Storm', 'Lantern'];

function genomeFrom(eng, R, curated) {
  const E = ENGINES[eng], first = (xs) => (curated ? xs[0] : R.pick(xs));
  if (eng === 'canon') return { engine: eng };
  const g = {
    engine: eng, meter: E.meter, grammar: first(E.grammars), form: first(E.forms), accomp: first(E.accomp), bass: first(E.bass),
    drums: first(E.drums), feel: E.feel, counter: E.counter, chordBars: E.chordBars, swing: !!E.swing,
    bpm: curated ? Math.round((E.bpm[0] + E.bpm[1]) / 2) : R.range(E.bpm[0], E.bpm[1]),
    palette: Object.fromEntries(Object.entries(E.palette).map(([role, opts]) => [role, curated || eng === 'chorale' ? opts : [0, 1, 2].map(() => R.pick(POOLS[role]))])),
  };
  if (eng === 'chorale' && !curated) { const org = R.pick([95, 43, 47, 81, 33]); for (const r of ['lead', 'counter', 'accomp', 'bass']) g.palette[r] = [org, org, org]; }
  return g;
}

const genomeCache = new Map();
/** Edition e's genome: curated for 0-11; after that hash(e) picks an engine (not the last 3 months') and its axes. */
export function editionGenome(e) {
  if (genomeCache.has(e)) return genomeCache.get(e);
  let g;
  if (e < CURATED.length) g = { ...genomeFrom(CURATED[e].engine, null, true), name: CURATED[e].name, curated: true };
  else {
    const R = rng(hash32('EDITION', e)), recent = [1, 2, 3].map((k) => editionGenome(e - k).engine);
    const eng = R.pick(ENGINE_LIST.filter((x) => !recent.includes(x)));
    g = { ...genomeFrom(eng, R, false), name: 'The ' + R.pick(ADJ) + ' ' + ENGINES[eng].noun, curated: false };
  }
  g.edition = e; g.month = editionMonth(e);
  genomeCache.set(e, g);
  return g;
}

// ── melody tools ─────────────────────────────────────────────────────────────────────────────────
const CELLS = {
  8: {
    lyric: [[4, 4], [2, 2, 4], [3, 1, 4], [2, 2, 2, 2], [6, 2], [4, 2, 2], [3, 1, 2, 2]],
    heroic: [[3, 3, 2], [2, 2, 4], [6, 2], [1, 1, 2, 4], [3, 1, 2, 2], [2, 1, 1, 4], [3, 3, 1, 1]],
    vocal: [[1, 1, 1, 1, 2, 2], [2, 1, 1, 2, 2], [1, 1, 2, 4], [2, 2, 1, 1, -2], [1, 1, 1, 1, 4], [-2, 1, 1, 2, 2]],
    call: [[2, 1, 1, -4], [1, 1, 2, -4], [3, 1, -4], [-2, 1, 1, 1, 1, -2], [1, 1, 1, 1, -4]],
    slow: [[8], [4, 4], [6, 2], [4, 4]],
    march: [[2, 1, 1, 2, 2], [3, 1, 2, 2], [2, 2, 4], [1, 1, 1, 1, 4], [3, 1, 3, 1]],
  },
  6: {
    waltz: [[4, 2], [2, 2, 2], [6], [3, 1, 2], [2, 1, 1, 2], [4, 1, 1]],
    compound: [[3, 3], [2, 1, 3], [3, 2, 1], [1, 1, 1, 3], [6], [2, 1, 2, 1]],
    lyric: [[4, 2], [2, 2, 2], [6], [3, 1, 2]], slow: [[6], [3, 3], [4, 2]],
  },
};
const cellsFor = (eighths, feel) => (CELLS[eighths] || CELLS[8])[feel] || (CELLS[eighths] || CELLS[8])[eighths === 6 ? 'lyric' : 'lyric'];

/** Pitch classes of the chord-scale: the scale, with each chord tone replacing the scale note it bends. */
function chordScale(tonicPc, scale, chord) {
  const pcs = scale.map((s) => (tonicPc + s) % 12), ct = chord.tones.map((t) => (tonicPc + chord.r + t) % 12);
  for (const c of ct) if (!pcs.includes(c)) {
    let best = -1, bd = 9;
    pcs.forEach((p, i) => { const d = Math.min((p - c + 12) % 12, (c - p + 12) % 12); if (d < bd && !ct.includes(p)) { bd = d; best = i; } });
    if (best >= 0 && bd <= 1) pcs[best] = c; else pcs.push(c);
  }
  return { pcs: new Set(pcs), ct: new Set(ct) };
}
const listPitches = (set, lo, hi) => { const out = []; for (let p = lo; p <= hi; p++) if (set.has(p % 12)) out.push(p); return out; };
function nearest(list, p) { let b = list[0]; for (const x of list) if (Math.abs(x - p) < Math.abs(b - p)) b = x; return b; }
function stepIn(list, p, k) { let i = list.indexOf(p); if (i < 0) i = list.indexOf(nearest(list, p)); return list[Math.max(0, Math.min(list.length - 1, i + k))]; }

/** The motif cameo: the species theme's scale degrees in this key's scale near `center`. */
function motifPitches(degrees, tonicPc, scale, center) {
  let base = center - ((center - tonicPc) % 12 + 12) % 12;
  const n = scale.length;
  return degrees.map((d) => base + scale[((d % n) + n) % n] + 12 * Math.floor(d / n));
}

// ── the song plan ────────────────────────────────────────────────────────────────────────────────
function makeCtx(sp, shiny, g, seedKey) {
  const R = rng(hash32('TRACK', g.edition, sp.id, seedKey));
  const gr = GRAMMARS[g.grammar], scale = SCALES[gr.scale];
  const shift = R.pick([0, 0, 0, 5, 7, -2, 2, 3]);
  const tonicPc = ((sp.tonicPc + shift) % 12 + 12) % 12;
  const [num, den] = g.meter, barTicks = num * (TPQ * 4 / den), eighths = barTicks / EIGHTH;
  const type = sp.type, pal = Object.fromEntries(Object.entries(g.palette).map(([r, o]) => [r, o[type % o.length]]));
  if (shiny) { pal.lead = MEGA_LEADS[(sp.id) % 2]; pal.mega = MEGA_LEADS[(sp.id + 1) % 2]; }
  const bpm = g.bpm + R.pick([-4, -2, 0, 0, 2, 4]);
  const progs = gr.progs.map((p) => p.split(' ').map(parseChord));
  const pA = R.int(progs.length); let pB = R.int(progs.length); if (pB === pA) pB = (pA + 1) % progs.length;
  return { R, g, sp, shiny, gr, scale, tonicPc, num, den, barTicks, eighths, pal, bpm, progA: progs[pA], progB: progs[pB], notes: [], strong: den === 8 ? [0, 3 * EIGHTH] : num === 4 ? [0, 2 * TPQ] : [0], tier: sp.tier };
}

/** A section's chord at each bar half: `prog` laid out at chordBars bars per chord. */
function chordsFor(c, prog, bars) {
  const per = c.g.chordBars, out = [];
  for (let b = 0; b < bars; b++) {
    if (per >= 1) out.push([prog[Math.floor(b / per) % prog.length]]);
    else out.push([prog[(b * 2) % prog.length], prog[(b * 2 + 1) % prog.length]]);
  }
  if (c.gr.twelve) for (let b = 0; b < bars; b++) out[b] = [prog[b % prog.length]];
  return out;
}
const chordAtTick = (c, chords, t) => { const bar = chords[Math.floor(t / c.barTicks)] || chords[chords.length - 1]; return bar.length === 1 ? bar[0] : bar[(t % c.barTicks) < c.barTicks / 2 ? 0 : 1]; };

function note(c, ch, t, d, p, v) { if (d > 0 && p >= 0 && p < 128) c.notes.push({ t: Math.round(t), d: Math.max(30, Math.round(d)), p, v: Math.max(1, Math.min(127, Math.round(v))), ch }); }

/** A melody over `bars` bars: two-bar ideas, the first carrying the motif when asked, an antecedent
 * (half cadence) and a consequent that repeats its first half and closes on the tonic. */
function melody(c, chords, bars, { lo, hi, feel, motif = null, cadence = 'full', R = c.R }) {
  const cells = cellsFor(c.eighths, feel), out = [];
  const half = Math.max(2, bars / 2), ideaCells = [R.pick(cells), R.pick(cells)];
  let prev = Math.round((lo + hi) / 2), motifQ = motif ? [...motif] : [];
  const writeBar = (bar, cell, phrasePos, endKind) => {
    let t = bar * c.barTicks;
    const last = cell.length - 1 - [...cell].reverse().findIndex((x) => x > 0);
    cell.forEach((u, i) => {
      const dur = Math.abs(u) * EIGHTH;
      if (u > 0) {
        const chord = chordAtTick(c, chords, t), cs = chordScale(c.tonicPc, c.scale, chord);
        const list = listPitches(cs.pcs, lo, hi), tones = listPitches(cs.ct, lo, hi);
        const strong = c.strong.includes(t % c.barTicks);
        let p;
        if (motifQ.length) { p = motifQ.shift(); while (p > hi) p -= 12; while (p < lo) p += 12; if (strong && !cs.ct.has(p % 12)) p = nearest(tones, p); }
        else {
          const target = lo + (hi - lo) * (0.35 + 0.45 * Math.sin(Math.PI * phrasePos));
          const dir = prev < target - 2 ? 1 : prev > target + 2 ? -1 : R.chance(0.5) ? 1 : -1;
          const r = R();
          const k = r < 0.12 ? 0 : r < 0.66 ? dir : r < 0.9 ? 2 * dir : 3 * dir * (R.chance(0.5) ? 1 : -1);
          p = stepIn(list, prev, k);
          if (strong || dur >= 3 * EIGHTH) p = nearest(tones, p);
        }
        if (endKind && i === last) {
          const goal = endKind === 'full' ? (c.tonicPc + chord.r) % 12 === c.tonicPc ? c.tonicPc : (c.tonicPc + chord.r) % 12 : (c.tonicPc + chord.r + chord.tones[Math.min(2, chord.tones.length - 1)]) % 12;
          p = nearest(listPitches(new Set([goal]), lo, hi), prev);
        }
        out.push({ t, d: dur, p }); prev = p;
      }
      t += dur;
    });
  };
  const plan = [];
  for (let b = 0; b < bars; b++) plan.push(b % half < 2 ? ideaCells[b % 2] : R.pick(cells));
  for (let b = 0; b < bars; b++) {
    const endHalf = b === half - 1, endAll = b === bars - 1;
    // the consequent's first two bars restate the antecedent's (re-fitted to the chords)
    if (b >= half && b < half + 2 && out.length) {
      const src = out.filter((n) => n.t >= (b - half) * c.barTicks && n.t < (b - half + 1) * c.barTicks);
      for (const n of src) {
        const t = n.t + half * c.barTicks, chord = chordAtTick(c, chords, t), cs = chordScale(c.tonicPc, c.scale, chord);
        let p = nearest(listPitches(cs.pcs, lo, hi), n.p); if (c.strong.includes(t % c.barTicks)) p = nearest(listPitches(cs.ct, lo, hi), p);
        out.push({ t, d: n.d, p }); prev = p;
      }
      continue;
    }
    const cell = endHalf || endAll ? R.pick(cellsFor(c.eighths, 'slow')) : plan[b];
    writeBar(b, cell, (b % half) / half, endAll ? cadence : endHalf ? 'half' : null);
  }
  return out;
}

/** The closest voicing of `chord` (3-4 tones) in [lo, hi] to `prev`. */
function voicing(c, chord, lo, hi, prev, size = 3) {
  const pcs = chord.tones.slice(0, Math.max(size, chord.tones.length)).map((t) => (c.tonicPc + chord.r + t) % 12);
  const cands = [];
  for (let base = lo; base <= hi; base++) {
    if (base % 12 !== pcs[0] && base % 12 !== pcs[1] && base % 12 !== pcs[2]) continue;
    const v = [base];
    let p = base;
    while (v.length < Math.min(size, pcs.length)) { p++; if (pcs.includes(p % 12) && !v.some((x) => x % 12 === p % 12)) v.push(p); if (p > hi + 12) break; }
    if (v.length === Math.min(size, pcs.length) && v[v.length - 1] <= hi + 2) cands.push(v);
  }
  if (!cands.length) return pcs.map((x) => lo + ((x - lo) % 12 + 12) % 12).sort((a, b) => a - b);
  if (!prev) return cands[Math.floor(cands.length / 2)];
  const cost = (v) => v.reduce((s, x, i) => s + Math.abs(x - (prev[i] ?? prev[prev.length - 1])), 0);
  return cands.reduce((a, b) => (cost(b) < cost(a) ? b : a));
}
const rootIn = (c, chord, lo) => lo + ((c.tonicPc + chord.r - lo) % 12 + 12) % 12;

// ── accompaniment, bass and drums ────────────────────────────────────────────────────────────────
function accompany(c, ch, chords, t0, bars, kind, vel = 70) {
  let prev = null;
  const beat = TPQ * 4 / c.den, B = c.barTicks;
  for (let b = 0; b < bars; b++) for (let h = 0; h < chords[b].length; h++) {
    const chord = chords[b][h], len = B / chords[b].length, t = t0 + b * B + h * len;
    const lo = kind === 'musicbox' ? 64 : kind === 'arp16' ? 60 : 55, v = voicing(c, chord, lo, lo + 14, prev, chord.tones.length > 3 ? 4 : 3); prev = v;
    const at = (off, d, ps, vv = vel) => ps.forEach((p) => note(c, ch, t + off, d, p, vv));
    switch (kind) {
      case 'block': at(0, len / 2 - 20, v); at(len / 2, len / 2 - 20, v, vel - 8); break;
      case 'strum': [0, 3, 5, 6].forEach((e, i) => { if (e * EIGHTH < len) at(e * EIGHTH, (i === 3 ? 2 : 2) * EIGHTH - 20, v, i ? vel - 10 : vel); }); break;
      case 'stab': [3, 7].forEach((e) => { if (e * EIGHTH < len) at(e * EIGHTH, 100, v, vel + 6); }); if (c.R.chance(0.3)) at(5.5 * EIGHTH, 60, v, vel - 10); break;
      case 'waltz': at(beat, beat * 0.6, v, vel - 6); at(2 * beat, beat * 0.6, v, vel - 12); break;
      case 'oompah': for (let k = 1; k < len / beat; k += 2) at(k * beat, beat * 0.5, v, vel - 4); break;
      case 'arp16': { const seq = [...v, v[0] + 12, v[1] + 12, ...[...v].reverse().map((x) => x + 12).slice(1), ...[...v].reverse().slice(1, -1)]; for (let k = 0; k * 120 < len; k++) note(c, ch, t + k * 120, 110, seq[k % seq.length], vel - (k % 4 ? 12 : 0)); break; }
      case 'alberti': { const [a, b2, cc] = v, seq = [a, cc, b2, cc]; for (let k = 0; k * EIGHTH < len; k++) note(c, ch, t + k * EIGHTH, EIGHTH - 20, seq[k % 4], vel - (k % 2 ? 10 : 0)); break; }
      case 'musicbox': { const seq = [v[0], v[1], v[2], v[0] + 12, v[2], v[1]]; for (let k = 0; k * EIGHTH < len; k++) note(c, ch, t + k * EIGHTH, EIGHTH * 1.6, seq[k % seq.length], vel - (k % 3 ? 14 : 0)); break; }
      case 'shuffle': for (let k = 0; k < len / beat; k++) { at(k * beat, beat * 0.55, v.slice(0, 3), vel - 6); at(k * beat + beat * 2 / 3, beat / 3 - 10, v.slice(0, 3), vel - 18); } break;
      case 'bossa': [0, 3, 6, 10, 13].forEach((s) => { if (s * 120 < len) at(s * 120, 200, v, vel - (s % 2 ? 4 : 0)); }); break;
      case 'tolling': at(0, len * 0.9, [v[0], v[0] + 12], vel - 10); break;
      default: break;
    }
  }
}

function bassLine(c, ch, chords, t0, bars, kind, vel = 96) {
  const beat = TPQ * 4 / c.den, B = c.barTicks;
  for (let b = 0; b < bars; b++) for (let h = 0; h < chords[b].length; h++) {
    const chord = chords[b][h], len = B / chords[b].length, t = t0 + b * B + h * len, root = rootIn(c, chord, 36);
    const fifth = root + (chord.tones[2] - chord.tones[0]), third = root + chord.tones[1];
    const nextChord = h + 1 < chords[b].length ? chords[b][h + 1] : (chords[b + 1] || chords[0])[0];
    switch (kind) {
      case 'root': note(c, ch, t, len - 30, root, vel); break;
      case 'rootfifth': for (let k = 0; k * 2 * beat < len; k++) { note(c, ch, t + k * 2 * beat, beat * 1.4, k % 2 ? fifth - 12 * (fifth > 50 ? 1 : 0) : root, vel - (k % 2) * 8); } break;
      case 'waltz': note(c, ch, t, beat * 0.9, root, vel); break;
      case 'octave8': for (let k = 0; k * EIGHTH < len; k++) note(c, ch, t + k * EIGHTH, EIGHTH - 30, root + (k % 2 ? 12 : 0), vel - (k % 2) * 10); break;
      case 'boogie': { const st = [0, 0, 4, 4, 7, 7, 9, 10].map((x, i) => [0, 4, 7, 9, 10, 9, 7, 4][i]); for (let k = 0; k < 8; k++) note(c, ch, t + Math.floor(k / 2) * beat + (k % 2 ? beat * 2 / 3 : 0), k % 2 ? beat / 3 - 10 : beat * 2 / 3 - 10, root + st[k], vel - (k % 2) * 12); break; }
      case 'pedal': if (b % 2 === 0 && h === 0) note(c, ch, t, Math.min(2 * B, (bars - b) * B) - 40, rootIn(c, chord, 36), vel - 10); break;
      case 'bossa': note(c, ch, t, beat * 1.4, root, vel); note(c, ch, t + beat * 1.5, beat / 2 - 20, fifth > 50 ? fifth - 12 : fifth, vel - 12); note(c, ch, t + beat * 2, beat * 1.4, fifth > 50 ? fifth - 12 : fifth, vel - 6); note(c, ch, t + beat * 3.5, beat / 2 - 20, rootIn(c, nextChord, 36), vel - 12); break;
      case 'sixeight': note(c, ch, t, 3 * EIGHTH - 30, root, vel - 10); note(c, ch, t + 3 * EIGHTH, 3 * EIGHTH - 30, fifth > 50 ? fifth - 12 : fifth, vel - 18); break;
      case 'drone': if (h === 0) { note(c, ch, t, len - 40, rootIn(c, { r: 0, tones: [0] }, 36), vel - 10); note(c, ch, t, len - 40, rootIn(c, { r: 7, tones: [0] }, 36) + (rootIn(c, { r: 7, tones: [0] }, 36) < rootIn(c, { r: 0, tones: [0] }, 36) ? 12 : 0), vel - 30); } break;
      case 'riff': {
        const m = c.riff;
        m.forEach(([off, d, deg]) => { if (off < len) note(c, ch, t + off, d, root + deg, vel - (off % TPQ ? 12 : 0)); });
        break;
      }
      default: break;
    }
    void third;
  }
}

const GROOVES = {
  rock: { K: 'x.......x.x.....', S: '....X.......X...', H: 'x.x.x.x.x.x.x.x.' },
  halftime: { K: 'x.........x.....', S: '........X.......', H: 'x.x.x.x.x.x.x.x.' },
  drive: { K: 'X...x...X...x...', S: '....X.......X..o', H: '..x...x...x...x.', O: '..x...x...x...x.' },
  shuffle: { K: 'x.....x.....', S: '...X.....X..', H: 'x.xx.xx.xx.x' },
  march: { K: 'x.......x.......', S: 'X.oxX.o.x.oxX.xo', H: '' },
  waltz: { K: 'x...........', S: '', H: '....x...x...' },
  bossa: { K: 'x..xx..xx..xx..x', R: 'x..x..x...x..x..', H: 'oooooooooooooooo' },
  dirge: { K: 'X...............', T: '........x.......' },
  minimal: { K: 'x.......x.......', H: '..o...o...o...o.' },
};
const DRUM = { K: 36, S: 38, H: 42, O: 46, T: 43, R: 41 };
const VEL = { X: 112, x: 88, o: 52 };
function drums(c, t0, bars, groove, { fill = true, crash = true, quiet = false } = {}) {
  const G = GROOVES[groove]; if (!G) return;
  const B = c.barTicks;
  for (let b = 0; b < bars; b++) {
    const t = t0 + b * B;
    for (const [k, pat] of Object.entries(G)) {
      if (!pat) continue;
      const step = B / pat.length;
      [...pat].forEach((s, i) => { if (VEL[s]) note(c, 9, t + i * step, 60, DRUM[k], VEL[s] - (quiet ? 24 : 0)); });
    }
    if (crash && b === 0) note(c, 9, t, 200, 49, quiet ? 70 : 96);
    if (fill && b === bars - 1 && groove !== 'waltz' && groove !== 'minimal') {
      const toms = [50, 48, 47, 45, 43, 41], start = B - TPQ * (c.den === 8 ? 1.5 : 2), n = c.den === 8 ? 6 : 8;
      c.notes = c.notes.filter((x) => !(x.ch === 9 && x.t >= t + start && x.t < t + B && x.p !== 36));
      for (let i = 0; i < n; i++) note(c, 9, t + start + i * (B - start) / n, 60, i === n - 1 ? 38 : toms[Math.floor(i * toms.length / n)], 80 + i * 3);
    }
  }
}

// ── sections ─────────────────────────────────────────────────────────────────────────────────────
const CH = { lead: 0, counter: 1, accomp: 2, bass: 3, pad: 4, tenor: 5, mega: 6 };

function sectionPlan(g) {
  const bars = g.engine === 'blues' ? 12 : g.engine === 'phase' ? 8 : 8;
  return [...g.form].map((k) => ({ kind: k, bars }));
}

function counterLine(c, mel, chords, bars, t0, lo, hi, vel) {
  // half-note line, chord tones, moving against the melody
  const B = c.barTicks, step = c.num === 3 || c.den === 8 ? B : B / 2;
  let prev = Math.round((lo + hi) / 2);
  for (let t = 0; t < bars * B; t += step) {
    const chord = chordAtTick(c, chords, t), cs = chordScale(c.tonicPc, c.scale, chord), tones = listPitches(cs.ct, lo, hi);
    const m = mel.find((n) => n.t <= t && n.t + n.d > t);
    let p = m ? (m.p > prev ? stepIn(tones, prev, -1) : stepIn(tones, prev, 1)) : nearest(tones, prev);
    if (m && Math.abs(m.p - p) < 3) p = stepIn(tones, p, -1);
    note(c, CH.counter, t0 + t, step - 30, p, vel); prev = p;
  }
}
function thirdsBelow(c, mel, chords, t0, vel) {
  for (const n of mel) {
    if (n.d < EIGHTH) continue;
    const chord = chordAtTick(c, chords, n.t), cs = chordScale(c.tonicPc, c.scale, chord), list = listPitches(cs.pcs, n.p - 12, n.p);
    note(c, CH.counter, t0 + n.t, n.d - 20, stepIn(list, n.p, -2), vel);
  }
}

function writeSection(c, sec, t0, idx, mel0) {
  const g = c.g, B = c.barTicks, isB = sec.kind === 'B' || sec.kind === 'C';
  const prog = isB ? c.progB : c.progA, chords = chordsFor(c, prog, sec.bars);
  const center = isB ? 74 : 69, lo = center - 8, hi = center + 8;
  const motif = !isB && idx === 0 ? motifPitches(c.sp.degrees.slice(0, c.eighths === 6 ? 6 : 8), c.tonicPc, c.scale, 69) : null;
  let mel = (!isB && mel0.A) || (isB && mel0.B);
  if (!mel) {
    mel = melody(c, chords, sec.bars, { lo, hi, feel: sec.kind === 'V' ? 'vocal' : g.feel, motif, cadence: isB ? 'half' : 'full', R: rng(hash32('MEL', c.R.int(1e9), sec.kind)) });
    if (isB) mel0.B = mel; else mel0.A = mel;
  }
  const quietDrums = sec.kind === 'V';
  for (const n of mel) {
    let { t, d } = n;
    if (g.swing && t % TPQ === EIGHTH) { t += 80; d -= 80; } else if (g.swing && d === EIGHTH) d += 80;
    note(c, CH.lead, t0 + t, d - 20, n.p, 100 - (t % B ? 10 : 0));
    if (c.shiny) note(c, CH.mega, t0 + t, d - 20, n.p + 12, 70);
  }
  if (g.counter === 'line' && c.tier <= 3) counterLine(c, mel, chords, sec.bars, t0, 52, 64, 70);
  if (g.counter === 'thirds') thirdsBelow(c, mel, chords, t0, 76);
  if (g.counter === 'response') { // answer each call in its rests, an octave down
    for (const n of mel) if (Math.floor(n.t / (2 * B)) % 2 === 0) note(c, CH.counter, t0 + n.t + B, n.d - 20, n.p - 12, 72);
  }
  accompany(c, CH.accomp, chords, t0, sec.bars, g.accomp, sec.kind === 'V' ? 60 : 72);
  bassLine(c, CH.bass, chords, t0, sec.bars, g.bass);
  if (g.drums !== 'none' && !(sec.kind === 'V' && g.engine === 'song' && idx === 0)) drums(c, t0, sec.bars, sec.kind === 'V' ? 'minimal' : g.drums, { quiet: quietDrums, crash: !quietDrums });
  if (c.tier <= 2 && g.engine !== 'blues') for (let b = 0; b < sec.bars; b += 2) { const ch = chords[b][0], v = voicing(c, ch, 52, 66, null); v.forEach((p) => note(c, CH.pad, t0 + b * B, Math.min(2, sec.bars - b) * B - 40, p, 46)); }
}

function writeChorale(c) {
  const g = c.g, B = c.barTicks, out = [];
  let t0 = 0;
  const mel0 = {};
  for (const [idx, sec] of sectionPlan(g).entries()) {
    const isB = sec.kind === 'B', chords = chordsFor(c, isB ? c.progB : c.progA, sec.bars);
    let sop = isB ? mel0.B : mel0.A;
    if (!sop) {
      sop = [];
      let prev = isB ? 74 : 71;
      const motif = !isB && idx === 0 ? motifPitches(c.sp.degrees.slice(0, 4), c.tonicPc, c.scale, 70) : [];
      for (let b = 0; b < sec.bars; b++) for (let h = 0; h < 2; h++) {
        const t = b * B + h * B / 2, chord = chords[b][h % chords[b].length], tones = listPitches(chordScale(c.tonicPc, c.scale, chord).ct, 64, 79);
        let p = motif.length ? nearest(tones, motif.shift()) : stepIn(tones, nearest(tones, prev), c.R.pick([-1, 0, 1, 1, -1]));
        if (b === sec.bars - 1 && h === 1) p = nearest(listPitches(new Set([(c.tonicPc + chord.r) % 12]), 64, 79), prev);
        sop.push({ t, d: B / 2, p, chord }); prev = p;
      }
      if (isB) mel0.B = sop; else mel0.A = sop;
    }
    let pa = null, pt = null;
    for (const s of sop) {
      const chord = s.chord, pcs = chord.tones.slice(0, 3).map((x) => (c.tonicPc + chord.r + x) % 12);
      const bass = rootIn(c, chord, 40), need = pcs.filter((x) => x !== s.p % 12);
      const pickBelow = (top, lo, prevP, want) => { const cands = []; for (let p = lo; p < top; p++) if (want.includes(p % 12)) cands.push(p); return cands.length ? cands.reduce((a, b) => (Math.abs(b - (prevP ?? top - 5)) < Math.abs(a - (prevP ?? top - 5)) ? b : a)) : top - 5; };
      const alto = pickBelow(s.p, Math.max(55, s.p - 9), pa, need.length ? need : pcs);
      const tenor = pickBelow(alto, Math.max(48, alto - 9), pt, pcs.filter((x) => x !== alto % 12).length ? pcs.filter((x) => x !== alto % 12) : pcs);
      pa = alto; pt = tenor;
      const t = t0 + s.t, d = s.d - 30;
      note(c, CH.lead, t, d, s.p, 92); note(c, CH.counter, t, d, alto, 76); note(c, CH.tenor, t, d, tenor, 74); note(c, CH.bass, t, d, bass, 88);
      if (c.shiny) note(c, CH.mega, t, d, s.p + 12, 64);
    }
    if (c.tier <= 2) for (let b = 0; b < sec.bars; b += 4) note(c, CH.pad, t0 + b * B, 4 * B - 60, rootIn(c, { r: 0, tones: [0] }, 36), 50);
    t0 += sec.bars * B;
    out.push(sec);
  }
  return t0;
}

function writePhase(c) {
  const g = c.g, B = c.barTicks, cellNotes = motifPitches(c.sp.degrees.slice(0, 6), c.tonicPc, c.scale, 72);
  const lenA = 6 + c.R.int(2), lenB = lenA + 1 + c.R.int(2), S = 120 * 2; // eighths
  let t0 = 0;
  const mel0 = {};
  for (const [idx, sec] of sectionPlan(g).entries()) {
    const isB = sec.kind === 'B', chords = chordsFor(c, isB ? c.progB : c.progA, sec.bars), end = sec.bars * B;
    for (let k = 0; k * S < end; k++) {
      const t = k * S, chord = chordAtTick(c, chords, t), list = listPitches(chordScale(c.tonicPc, c.scale, chord).pcs, 60, 90);
      const a = k % lenA; if (a < cellNotes.length) note(c, CH.accomp, t0 + t, S - 30, nearest(list, cellNotes[a]), a === 0 ? 86 : 70);
      const bb = k % lenB; if (bb < cellNotes.length && (isB || idx > 0)) note(c, CH.counter, t0 + t, S - 30, stepIn(list, nearest(list, cellNotes[bb] + 12), 0) , bb === 0 ? 76 : 62);
    }
    if (isB || idx === sectionPlan(g).length - 1) {
      let mel = mel0.m || (mel0.m = melody(c, chords, sec.bars, { lo: 64, hi: 79, feel: 'slow', R: rng(hash32('PH', c.R.int(1e9))) }));
      for (const n of mel) { note(c, CH.lead, t0 + n.t, n.d - 20, n.p, 88); if (c.shiny) note(c, CH.mega, t0 + n.t, n.d - 20, n.p + 12, 60); }
    }
    bassLine(c, CH.bass, chords, t0, sec.bars, 'pedal');
    for (let b = 0; b < sec.bars; b += 2) voicing(c, chords[b][0], 52, 66, null).forEach((p) => note(c, CH.pad, t0 + b * B, 2 * B - 40, p, 44));
    if (g.drums !== 'none' && idx > 0) drums(c, t0, sec.bars, g.drums, { fill: false, crash: false, quiet: true });
    t0 += end;
  }
  return t0;
}

function writeVariations(c) {
  const g = c.g, B = c.barTicks, bars = 8;
  const chordsMaj = chordsFor(c, c.progA, bars);
  const theme = melody(c, chordsMaj, bars, { lo: 64, hi: 79, feel: 'lyric', motif: motifPitches(c.sp.degrees.slice(0, 8), c.tonicPc, c.scale, 69), R: rng(hash32('VAR', c.R.int(1e9))) });
  // the parallel minor: I/IV minor, ii diminished, iii/vi/vii flattened majors; dominants stay
  const MINOR = { 0: [0, 'm'], 2: [2, 'o'], 4: [3, 'M'], 5: [5, 'm'], 9: [8, 'M'], 11: [10, 'M'] };
  const toMinor = (ch) => { if (ch.q === '7' || ch.r === 7 || !MINOR[ch.r]) return ch; const [r, q0] = MINOR[ch.r], q = ch.tones.length > 3 && q0 !== 'o' ? (q0 === 'm' ? 'm7' : 'M7') : q0; return { r, q, tones: QUAL[q], name: ch.name }; };
  const minorScale = SCALES.harmonic;
  const sections = [
    { label: 'Theme', chords: chordsMaj, scale: c.scale, f: (n) => [n], accomp: 'block', bass: 'root', drums: null },
    { label: 'Var. I: in sixteenths', chords: chordsMaj, scale: c.scale, f: 'div', accomp: 'alberti', bass: 'root', drums: null },
    { label: 'Var. II: minor', chords: chordsMaj.map((bar) => bar.map(toMinor)), scale: minorScale, f: (n) => [n], accomp: 'arp16', bass: 'root', drums: null },
    { label: 'Var. III: march', chords: chordsMaj, scale: c.scale, f: (n) => [{ ...n, d: Math.min(n.d, EIGHTH) }], accomp: 'oompah', bass: 'rootfifth', drums: 'march' },
    { label: 'Finale', chords: chordsMaj, scale: c.scale, f: (n) => [n], accomp: 'arp16', bass: 'octave8', drums: 'rock' },
  ];
  let t0 = 0;
  for (const s of sections) {
    const saved = c.scale; c.scale = s.scale;
    for (const n of theme) {
      const chord = chordAtTick(c, s.chords, n.t), cs = chordScale(c.tonicPc, c.scale, chord), list = listPitches(cs.pcs, 55, 91);
      const p = nearest(list, n.p);
      if (s.f === 'div' && n.d >= TPQ) {
        const seq = [p, stepIn(list, p, 1), p, stepIn(list, p, -1)];
        for (let k = 0; k * 120 < n.d; k++) note(c, CH.lead, t0 + n.t + k * 120, 110, seq[k % 4], 92 - (k % 4 ? 10 : 0));
      } else for (const m of (s.f === 'div' ? [n] : s.f(n))) { note(c, CH.lead, t0 + m.t, m.d - 20, p + (s.label === 'Finale' ? 0 : 0), 96); if (s.label === 'Finale' || c.shiny) note(c, CH.mega, t0 + m.t, m.d - 20, p + 12, 66); }
    }
    accompany(c, CH.accomp, s.chords, t0, bars, s.accomp, 66);
    bassLine(c, CH.bass, s.chords, t0, bars, s.bass);
    if (s.drums) drums(c, t0, bars, s.drums, {});
    c.scale = saved;
    t0 += bars * B;
  }
  c.varLabels = sections.map((s) => s.label);
  return t0;
}

function makeRiff(c) {
  // the species motif's first 4 degrees as a 16th-note syncopated bass figure (semitones over the root)
  const n = c.scale.length, deg = c.sp.degrees.slice(0, 5).map((d) => c.scale[((d % n) + n) % n] + 12 * Math.floor(d / n));
  const base = deg[0], rel = deg.map((x) => Math.max(-5, Math.min(12, x - base)));
  const slots = c.R.pick([[0, 3, 6, 8, 11], [0, 2, 3, 6, 10], [0, 3, 4, 7, 10], [0, 4, 6, 8, 12]]);
  const riff = slots.map((s, i) => [s * 120, (i < slots.length - 1 ? (slots[i + 1] - s) : 4) * 120 - 20, rel[i]]);
  const second = riff.map(([o, d, x]) => [o + 960, d, x]);
  return [...riff, ...second];
}

/** The track: notes plus the setup, for edition `e`'s genome. `sp` = a species record (id, tier, type, tonicPc, degrees). */
export function editionTrack(sp, shiny, e, seedKey) {
  const g = editionGenome(e);
  if (g.engine === 'canon') throw new Error('edition 0 is composed by the canon engine');
  const c = makeCtx(sp, shiny, g, seedKey);
  c.riff = makeRiff(c);
  let ticks;
  if (g.engine === 'chorale') ticks = writeChorale(c);
  else if (g.engine === 'phase') ticks = writePhase(c);
  else if (g.engine === 'variations') ticks = writeVariations(c);
  else {
    let t0 = 0; const mel0 = {};
    for (const [idx, sec] of sectionPlan(g).entries()) { writeSection(c, sec, t0, idx, mel0); t0 += sec.bars * c.barTicks; }
    ticks = t0;
  }
  const programs = { [CH.lead]: c.pal.lead, [CH.counter]: c.pal.counter, [CH.accomp]: c.pal.accomp, [CH.bass]: c.pal.bass, [CH.pad]: c.pal.pad, [CH.tenor]: c.pal.accomp };
  if (shiny) programs[CH.mega] = c.pal.mega;
  const prog = (p) => p.map((x) => x.name).join(' ');
  const info = {
    edition: e, month: g.month, name: g.name, engine: ENGINES[g.engine].label, desc: ENGINES[g.engine].desc,
    key: NOTE[c.tonicPc] + ' ' + c.gr.scale, grammar: c.gr.label, meter: g.meter.join('/'), bpm: c.bpm, form: g.engine === 'variations' ? c.varLabels.join(' · ') : g.form.split('').join(' '),
    progA: prog(c.progA), progB: prog(c.progB), accomp: g.accomp, bass: g.bass, drums: g.drums, seconds: Math.round(ticks / TPQ * 60 / c.bpm),
  };
  return { notes: c.notes, programs, bpm: c.bpm, meter: g.meter, ticks, info };
}

// ── SMF ──────────────────────────────────────────────────────────────────────────────────────────
const VOL = { 0: 100, 1: 78, 2: 74, 3: 100, 4: 58, 5: 74, 6: 62, 9: 96 };
const PAN = { 0: 64, 1: 46, 2: 82, 3: 64, 4: 64, 5: 40, 6: 88, 9: 64 };
/** A format-0 SMF: tempo, meter, programs, volume/pan, the notes (same-pitch overlaps cut), End of Track at `ticks`. */
export function toSmf({ notes, programs, bpm, meter, ticks }) {
  const ev = [];
  const us = Math.round(60e6 / bpm);
  ev.push([0, 0, [0xff, 0x51, 3, (us >> 16) & 255, (us >> 8) & 255, us & 255]]);
  ev.push([0, 0, [0xff, 0x58, 4, meter[0], Math.log2(meter[1]), 24, 8]]);
  for (const [ch, p] of Object.entries(programs)) { ev.push([0, 1, [0xc0 | +ch, p]]); ev.push([0, 1, [0xb0 | +ch, 7, VOL[ch] ?? 90]]); ev.push([0, 1, [0xb0 | +ch, 10, PAN[ch] ?? 64]]); ev.push([0, 1, [0xb0 | +ch, 91, 40]]); }
  ev.push([0, 1, [0xb9, 7, VOL[9]]]);
  const byKey = new Map();
  const sorted = notes.filter((n) => n.t < ticks).sort((a, b) => a.t - b.t);
  for (const n of sorted) {
    const k = n.ch * 128 + n.p, prev = byKey.get(k);
    if (prev && prev.t + prev.d > n.t) prev.d = Math.max(20, n.t - prev.t - 1);
    byKey.set(k, n);
  }
  for (const n of sorted) { const end = Math.min(n.t + n.d, ticks); ev.push([n.t, 3, [0x90 | n.ch, n.p, n.v]]); ev.push([end, 2, [0x80 | n.ch, n.p, 0]]); }
  ev.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const body = [];
  const vlq = (v) => { const s = [v & 127]; while ((v >>= 7)) s.unshift((v & 127) | 128); body.push(...s); };
  let last = 0;
  for (const [t, , bytes] of ev) { vlq(t - last); last = t; body.push(...bytes); }
  vlq(ticks - last); body.push(0xff, 0x2f, 0);
  const head = [0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 0, 0, 1, TPQ >> 8, TPQ & 255, 0x4d, 0x54, 0x72, 0x6b, (body.length >>> 24) & 255, (body.length >> 16) & 255, (body.length >> 8) & 255, body.length & 255];
  return Uint8Array.from([...head, ...body]);
}
export const editionMidi = (sp, shiny, e, seedKey) => { const tr = editionTrack(sp, shiny, e, seedKey); return { midi: toSmf(tr), info: tr.info }; };
