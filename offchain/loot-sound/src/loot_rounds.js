// Loot Dungeon Rounds: canons over a chord loop.
//
// The Beasts composer writes a theme first and then repairs every follower note against what is
// sounding. A Round goes the other way: the harmony comes first, and the canon fits it by construction.
//
//   1. A chord loop in the Beast's mode (LOOPS4, LOOPS8: scale-degree roots), in the family's meter
//      (METERS: 4/4, 6/8 or 3/4; a slot is half a bar, or a bar in 3/4).
//   2. One line per canon voice over the loop. At every slot each line holds one member of
//      the slot's chord (root, third or fifth), and the lines' members are dealt so that together they
//      sound the whole chord and no line keeps the root or the fifth across a chord change: no parallel
//      fifths or octaves between the lines, or with a bass on the roots.
//      Each line has a shape (falling, rising, an arch, held, a valley) that the deal leans toward.
//   3. The lines end to end are the theme. Its first bar is the species motif, and every line opens with
//      the motif's rhythm and its two steps.
//   4. Between the slots a line is decorated from rhythm cells (passing notes, neighbours, chord skips).
//      Each time a voice comes round to a line again it plays a busier level of it. Where a line steps down
//      across a chord change it may hold its note over the bar line and resolve late: a suspension.
//   5. Every voice plays the theme exactly, one loop after the voice before it.
//   6. Half way, an episode: a sequence canon (EPISODES) with entries a slot
//      apart, each a step of the sequence away, closing on the mode's cadence chord.
//   7. The round comes back over a second loop, with lines of its own and the motif again.
//
// Nothing is searched: every choice is a draw or the best of at most 12 candidates. Integer-only and
// table-driven, so a Cairo port can reproduce it byte for byte.
//
//   roundScore(species, mega, seedKey, drift) -> the notes, slots and readout
//   roundMidi(species, mega, seedKey, drift)  -> { midi: Uint8Array (format 1), info, score }
// `species` = { id, tier, type, tonicPc, mode, degrees }. Seed 0 is the species' own Round; any other
// seed is a bought track (its own key, mode, loop and lines, the species motif kept). `drift` is a Casey
// Drift value ({ rhythm, rotate, dayKnob, delta, day }) or null.

import { rng, TPQ, glissPlan, glissando, GLISS_CHANNEL } from './loot_editions.js';

const imul = Math.imul;
export const SLOT = 960, BAR = 1920;
export const MODE_SCALES = { 4: [0, 2, 3, 5, 7, 9, 10], 5: [0, 1, 3, 5, 7, 8, 10], 6: [0, 1, 3, 5, 6, 8, 10], 7: [0, 2, 3, 5, 7, 8, 10], 8: [0, 2, 3, 5, 7, 8, 11], 26: [0, 2, 3, 6, 7, 9, 10] };
export const MODE_NAMES = { 4: 'Dorian', 5: 'Phrygian', 6: 'Locrian', 7: 'Aeolian', 8: 'harmonic minor', 26: 'Dorian #4' };
export const ROUND_MODES = [4, 5, 6, 7, 8, 26];
const NOTE = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

const mod7 = (d) => ((d % 7) + 7) % 7;
const sign = (x) => (x > 0 ? 1 : x < 0 ? -1 : 0);
const pitchOf = (base, scale, d) => base + 12 * Math.floor(d / 7) + scale[mod7(d)];
function mix(h, x) { const m = imul((h ^ x) >>> 0, 0x9e3779b1) >>> 0; return (m ^ (m >>> 15)) >>> 0; }

// ── harmony ──
/** The triad on scale degree r: 'M', 'm', 'd' (diminished) or 'A' (augmented). */
export function quality(scale, r) {
  const a = scale[mod7(r)], third = (scale[mod7(r + 2)] - a + 12) % 12, fifth = (scale[mod7(r + 4)] - a + 12) % 12;
  return fifth === 7 ? (third === 4 ? 'M' : 'm') : fifth === 6 ? 'd' : 'A';
}
const MAJOR = [0, 2, 4, 5, 7, 9, 11], RN = ['i', 'ii', 'iii', 'iv', 'v', 'vi', 'vii'];
export function numeral(scale, r) {
  r = mod7(r);
  const q = quality(scale, r), acc = scale[r] - MAJOR[r];
  return (acc < 0 ? 'b' : acc > 0 ? '#' : '') + (q === 'M' || q === 'A' ? RN[r].toUpperCase() : RN[r]) + (q === 'd' ? '°' : q === 'A' ? '+' : '');
}
// Chord loops as scale-degree roots. Each starts on the tonic, never repeats a chord side by side and
// does not end on the tonic, so the loop turns over with a change of chord.
const BASE4 = [
  [0, 6, 5, 6], [0, 5, 2, 6], [0, 3, 6, 2], [0, 6, 5, 4], [0, 3, 4, 3], [0, 2, 3, 4], [0, 5, 3, 4], [0, 4, 5, 2],
  [0, 1, 0, 6], [0, 1, 2, 1], [0, 3, 0, 4], [0, 6, 3, 4], [0, 2, 5, 4], [0, 5, 6, 4], [0, 3, 5, 4], [0, 6, 2, 5],
  [0, 2, 6, 3], [0, 5, 4, 3], [0, 2, 1, 4], [0, 4, 1, 4], [0, 1, 0, 4], [0, 2, 4, 1], [0, 6, 0, 3], [0, 3, 2, 6],
  [0, 5, 0, 6], [0, 1, 6, 5], [0, 6, 1, 2], [0, 4, 3, 5], [0, 5, 0, 3], [0, 4, 0, 3], [0, 3, 0, 5], [0, 2, 0, 1],
  [0, 4, 5, 4], [0, 5, 3, 5], [0, 4, 5, 3], [0, 1, 4, 1], [0, 4, 2, 1], [0, 2, 1, 2], [0, 4, 0, 1], [0, 1, 2, 4],
  // the rest of what harmonic minor (iv, V, VI) and Dorian #4 (II, III, v) can use
  [0, 3, 4, 5], [0, 3, 5, 3], [0, 4, 0, 5], [0, 4, 3, 4], [0, 5, 0, 4], [0, 5, 4, 5],
  [0, 1, 0, 2], [0, 1, 4, 2], [0, 2, 0, 4], [0, 2, 4, 2], [0, 4, 0, 2], [0, 4, 1, 2], [0, 4, 2, 4],
];
/** The four-chord loops: the written ones first, then every other loop of four chords that starts on the
 * tonic, never repeats a chord side by side, does not end on the tonic and is not two chords twice (180). */
export const LOOPS4 = (() => {
  const seen = new Set(BASE4.map(String)), out = BASE4.slice();
  for (let a = 1; a < 7; a++) for (let b = 0; b < 7; b++) for (let c = 1; c < 7; c++) {
    if (b === a || c === b || (b === 0 && c === a) || seen.has(String([0, a, b, c]))) continue;
    out.push([0, a, b, c]);
  }
  return out;
})();
const BASE8 = [
  [0, 4, 5, 2, 3, 0, 3, 4], [0, 6, 5, 4, 0, 3, 4, 6], [0, 3, 6, 2, 5, 3, 4, 6], [0, 4, 0, 6, 2, 6, 0, 4],
  [0, 6, 0, 4, 2, 6, 0, 4], [0, 5, 3, 6, 2, 5, 3, 4], [0, 1, 2, 1, 0, 6, 5, 6], [0, 3, 4, 0, 5, 3, 4, 3],
  [0, 1, 2, 1, 0, 4, 1, 4], [0, 6, 5, 6, 0, 3, 2, 6], [0, 2, 3, 6, 5, 2, 3, 1], [0, 5, 0, 3, 5, 3, 0, 4],
  [0, 1, 0, 2, 1, 2, 0, 1], [0, 3, 0, 5, 3, 5, 0, 3], [0, 2, 1, 0, 4, 2, 1, 4], [0, 6, 2, 5, 0, 6, 5, 3],
  [0, 5, 4, 3, 0, 3, 5, 4], [0, 4, 3, 5, 4, 5, 3, 4], [0, 1, 4, 2, 1, 2, 4, 1], [0, 4, 2, 1, 0, 2, 1, 4],
];
/** The eight-chord loops: the written ones first, then a four-chord loop and its answer, the same three
 * chords closing on the fifth or the seventh degree where the loop itself closes elsewhere. */
export const LOOPS8 = (() => {
  const seen = new Set(BASE8.map(String)), out = BASE8.slice();
  for (const [, a, b, c] of LOOPS4) for (const turn of [4, 6]) {
    const l = [0, a, b, c, 0, a, b, turn];
    if (c === 4 || c === 6 || b === turn || seen.has(String(l))) continue;
    seen.add(String(l)); out.push(l);
  }
  return out;
})();
const loopCache = new Map();
/** A mode's loops: those whose chords, the tonic aside, are all major or minor. */
export function loopsFor(mode, eight = false) {
  const key = mode * 2 + (eight ? 1 : 0);
  if (!loopCache.has(key)) { const scale = MODE_SCALES[mode]; loopCache.set(key, (eight ? LOOPS8 : LOOPS4).filter((l) => l.every((r) => r === 0 || 'Mm'.includes(quality(scale, r))))); }
  return loopCache.get(key);
}
/** The chord before the tonic at a cadence: the dominant, or where that is diminished the mode's own (bII, bVII). */
export function cadenceRoot(mode) {
  const scale = MODE_SCALES[mode], ok = (r) => 'Mm'.includes(quality(scale, r));
  return mode === 5 ? 1 : ok(4) ? 4 : ok(6) ? 6 : 1;
}

// ── the lines: which member of the chord (0 root, 1 third, 2 fifth) each line holds at each slot ──
function assignments(K) {
  const out = [];
  for (let n = 0; n < 3 ** K; n++) {
    const a = []; for (let x = 0, m = n; x < K; x++, m = Math.floor(m / 3)) a.push(m % 3);
    if ([0, 1, 2].every((r) => a.includes(r))) out.push(a);
  }
  return out;
}
/** Every deal of the chord's three members to K lines with all three present: 6 for three lines, 36 for four. */
export const ASSIGN = { 3: assignments(3), 4: assignments(4) };
/** A deal's own cost: 1 when it doubles the third, 1 for each member of the chord it leaves out. */
const dealCost = (b) => (b.filter((r) => r === 1).length > 1 ? 1 : 0) + [0, 1, 2].filter((r) => !b.includes(r)).length;
// every deal of three voices, whole chord or not: the close of the episode may leave a member out
const TRIPLES = Array.from({ length: 27 }, (_, n) => [n % 3, Math.floor(n / 3) % 3, Math.floor(n / 9)]);
/**
 * What moving from one slot's deal to the next costs. Across a chord change: 8 for every line that keeps
 * the root or the fifth (parallel octaves or fifths with a bass on the roots, and with the line that
 * holds the other of the two), 8 for a pair that stays doubled, `swap` for a pair that trades the root and the
 * fifth (fifths again if the two cross: 2 inside a loop, where the turn may need it, 8 at a join). Within a chord: 1 if nothing moves.
 */
export function dealPenalty(a, b, changed, swap = 2) {
  let p = 0, same = true;
  for (let x = 0; x < a.length; x++) if (a[x] !== b[x]) same = false;
  if (!changed) return same ? 1 : 0;
  for (let x = 0; x < a.length; x++) {
    if (a[x] === b[x] && a[x] !== 1) p += 8;
    for (let y = x + 1; y < a.length; y++) {
      if (a[x] === a[y] && b[x] === b[y]) p += 8;
      if (a[x] !== 1 && a[y] !== 1 && a[x] !== a[y] && b[x] === a[y] && b[y] === a[x]) p += swap;
    }
  }
  return p;
}
/** The deals of a loop's slots: slot 0 gives line 0 the root (the motif starts on the tonic); each later
 * slot takes the cheapest deal, scanning from a drawn start. The last slot also answers for the turn of
 * the loop, where every voice moves on to the next line, and the slot before it looks one slot ahead so
 * that the turn can always be made. `forced` = line 0's member at slot 1. */
export function dealRoles(K, chords, H, forced, shapes = null) {
  const A = ASSIGN[K], S = chords.length, first = A.filter((a) => a[0] === 0 && dealCost(a) === 0), roles = [first[H.int(first.length)]];
  const turn = roles[0].map((_, j) => roles[0][(j + 1) % K]);
  // what the lines' moves cost against their shapes: always less than one fault (16)
  const moves = (a, b, s) => (shapes ? a.reduce((p, r, j) => p + moveCost(shapes[j], chords[s - 1] + 2 * r, chords[s] + 2 * b[j], s, S), 0) : 0);
  const step = (a, b, s) => 16 * dealPenalty(a, b, chords[s] !== chords[s - 1]) + dealCost(b) + moves(a, b, s);
  const last = (a, b) => step(a, b, S - 1) + 16 * dealPenalty(b, turn, chords[0] !== chords[S - 1]);
  for (let s = 1; s < S; s++) {
    const start = H.int(A.length);
    let best = null, bestP = 1 << 30;
    for (let k = 0; k < A.length; k++) {
      const b = A[(start + k) % A.length];
      if (s === 1 && forced !== null && b[0] !== forced) continue;
      let p = s === S - 1 ? last(roles[s - 1], b) : step(roles[s - 1], b, s);
      if (s === S - 2) { let ahead = 1 << 30; for (const c of A) ahead = Math.min(ahead, last(b, c)); p += ahead; }
      if (p < bestP) { best = b; bestP = p; }
    }
    roles.push(best);
  }
  return roles;
}
// a line's shape: where it wants to go from slot to slot
export const SHAPE_NAMES = ['falling', 'rising', 'an arch', 'close', 'a valley'];
// the shapes of a theme's lines (the first line, which opens on the tonic with the motif, rises or arches)
export const SHAPES = { 3: [[2, 0, 1], [2, 3, 0], [1, 0, 2], [2, 4, 1]], 4: [[2, 0, 1, 3], [2, 3, 0, 1], [1, 0, 2, 4], [2, 4, 1, 0]] };
// where a line starts about its centre, by shape: a falling line and a valley from above, a rising line and an arch from below
const SHAPE_START = [2, -2, -2, 0, 2];
/** Which way a line of this shape moves into slot s of S: 1 up, -1 down, 0 the nearest way. An arch
 * rises to the middle and falls; a valley is its mirror. */
export const shapeWant = (shape, s, S) => (shape === 0 ? -1 : shape === 1 ? 1 : shape === 3 ? 0 : (2 * s <= S) === (shape === 2) ? 1 : -1);
/** A long falling or rising line goes in two waves: it starts again at the middle of an 8-slot loop. */
export const shapeRestart = (shape, s, S) => shape < 2 && S === 8 && s === 4;
/** The move from scale-degree class c1 to c2 for a line going `want`: that way if it is no more than a
 * fifth, else the step or third the other way; the nearest way for 0. */
export function shapeDelta(want, c1, c2) {
  const up = mod7(c2 - c1);
  if (want === 0) return up > 3 ? up - 7 : up;
  if (up === 0) return 0;
  return want > 0 ? (up <= 4 ? up : up - 7) : up >= 3 ? up - 7 : up;
}
/** What the move into slot s costs a line of this shape: 0 a step or third its way (a close line: a step),
 * 1 a fourth or fifth its way or a move against it (a close line: a third or a repeated note), 2 a repeated
 * note (a close line: a fourth). */
export function moveCost(shape, c1, c2, s, S) {
  if (shapeRestart(shape, s, S)) return 0;
  const want = shapeWant(shape, s, S), d = shapeDelta(want, c1, c2);
  if (want === 0) return Math.abs(d) === 1 ? 0 : Math.abs(d) === 3 ? 2 : 1;
  return d === 0 ? 2 : Math.sign(d) !== want || Math.abs(d) > 2 ? 1 : 0;
}
/** The cheapest deal between two others (a join: the close of the episode, the cadence). */
export function joinDeal(A, prev, changedPrev, next, changedNext, start = 0) {
  let best = null, bestP = 1 << 30;
  for (let k = 0; k < A.length; k++) {
    const b = A[(start + k) % A.length], p = dealPenalty(prev, b, changedPrev, 8) + (next ? dealPenalty(b, next, changedNext, 8) : 0) + dealCost(b);
    if (p < bestP) { best = b; bestP = p; }
  }
  return best;
}
/** The degree of scale-degree class `cls` nearest to `prev`. */
export function nearest(prev, cls) { let d = mod7(cls - prev); if (d > 3) d -= 7; return prev + d; }
const passing = (a, b) => { const d = b - a; return Math.abs(d) >= 2 ? a + sign(d) : d === 0 ? a + 1 : b; };
const skip = (a, role, up) => a + (up ? [2, 2, 3][role] : [-3, -2, -2][role]);

// where each line sits (its centre, in scale degrees above the tonic): the theme's contour
export const CONTOURS = { 3: [[2, 4, 6], [2, 5, 3], [2, 0, 5], [2, 6, 3]], 4: [[2, 4, 6, 3], [2, 5, 1, 6], [2, 0, 4, 6], [2, 6, 3, 5]] };
export const CONTOUR_NAMES = ['rising', 'arch', 'dip then peak', 'peak in the middle'];

// ── rhythm cells: a slot's notes as (offset, length, source) ──
// A the slot's chord tone, P a step toward the next slot's, U and L the neighbours above and below,
// S the next member of the chord toward the next slot's tone, R a rest.
export const CELLS = [
  [[0, 960, 'A']], [[0, 720, 'A'], [720, 240, 'P']], [[0, 480, 'A'], [480, 480, 'P']], [[0, 480, 'A'], [480, 480, 'S']],
  [[0, 480, 'A'], [480, 240, 'P'], [720, 240, 'P']], [[0, 240, 'A'], [240, 240, 'U'], [480, 480, 'A']],
  [[0, 240, 'A'], [240, 240, 'P'], [480, 240, 'P'], [720, 240, 'P']], [[0, 240, 'A'], [240, 240, 'S'], [480, 240, 'A'], [720, 240, 'P']],
  [[0, 480, 'A'], [480, 480, 'R']], [[0, 240, 'A'], [240, 240, 'L'], [480, 240, 'A'], [720, 240, 'P']],
  [[0, 240, 'A'], [240, 480, 'S'], [720, 240, 'P']], [[0, 720, 'A'], [720, 240, 'S']],
];
// cells by family (Magic flowing, Hunter driving, Brute heavy) and activity (calm, walking, running)
const CELL_FAMILY = [
  [[0, 1, 8, 0], [2, 1, 5, 3], [4, 7, 9, 6]],
  [[0, 8, 1, 0], [2, 3, 4, 10], [6, 4, 10, 7]],
  [[0, 0, 1, 8], [2, 3, 2, 11], [4, 5, 6, 3]],
];
// a line's activity by level: the lines complement each other, and each level is busier
const ACTIVITY = [[1, 0, 1, 0], [1, 1, 2, 0], [2, 1, 2, 1]];
export const LEVEL_NAMES = ['plain', 'moving', 'divisions'];
const levelAt = (u, K) => (u < K ? 0 : u < K + 2 ? 1 : 2);

// ── the parts around the canon ──
// bass figures (offset, length, source) for a chord that lasts two slots, and for one that lasts one:
// R the root, O the root an octave up, T the chord's third, F its fifth, N a step from the next chord's root.
// Every figure has the root (R or O) wherever a slot starts: the lines are dealt against a bass on the roots.
const BASS_BAR = [[[0, 1920, 'R']], [[0, 960, 'R'], [960, 960, 'O']], [[0, 1440, 'R'], [1440, 480, 'R']], [[0, 480, 'R'], [480, 480, 'R'], [960, 480, 'O'], [1440, 480, 'R']],
  [[0, 480, 'R'], [480, 480, 'F'], [960, 480, 'O'], [1440, 480, 'N']], [[0, 720, 'R'], [720, 240, 'F'], [960, 480, 'R'], [1440, 480, 'N']]];
const BASS_HALF = [[[0, 960, 'R']], [[0, 480, 'R'], [480, 480, 'O']], [[0, 720, 'R'], [720, 240, 'R']], [[0, 480, 'R'], [480, 480, 'R']],
  [[0, 480, 'R'], [480, 480, 'N']], [[0, 480, 'R'], [480, 240, 'F'], [720, 240, 'N']]];
export const BASS_NAMES = ['held', 'octaves', 'dotted', 'pulse', 'walking', 'root and fifth'];
// percussion a bar: (offset, key, velocity)
const PERC = [
  [[0, 36, 100], [480, 42, 60], [960, 38, 80], [1440, 42, 60]],
  [[0, 36, 100], [240, 42, 50], [720, 42, 50], [960, 36, 84], [1200, 42, 50], [1680, 42, 56]],
  [[0, 36, 104], [960, 41, 84], [1440, 43, 80], [1680, 45, 84]],
];
export const PERC_NAMES = ['backbeat', 'offbeat hats', 'toms'];
export const ROUND_DRUMS = [36, 38, 41, 42, 43, 45, 49];
// the episode: a sequence, the roots a fixed step apart, the leader's chord member turning each chord
export const EPISODES = [
  { name: 'falling fifths, the line rising', step: 3, cycle: [0, 2, 1] },
  { name: 'falling fifths, the line falling', step: 3, cycle: [0, 1, 2] },
  { name: 'falling thirds, held tones', step: 5, cycle: [0, 1, 2] },
  { name: 'rising fifths on the motif', step: 4, cycle: [0, 2, 1], motif: true },
  { name: 'rising steps, the line falling', step: 1, cycle: [0, 2, 1] },
  { name: 'rising fifths, the line climbing', step: 4, cycle: [0, 1, 2] },
];
const EP_UNITS = 7, EP_SLOTS = 8;
// the motif's rhythm, by species: each half of its bar is even, dotted or snapped
const HEAD = [[480, 480], [720, 240], [240, 720]];
export const HEAD_NAMES = ['even', 'dotted', 'snapped'];
// ── meters: 4/4 on a half-bar slot, 6/8 on a half-bar slot (a dotted quarter), 3/4 on a whole-bar slot ──
// Each has its own cells (cell 8 is always "the tone, then a rest"), heads, bass figures and percussion.
const CELLS68 = [
  [[0, 720, 'A']], [[0, 480, 'A'], [480, 240, 'P']], [[0, 240, 'A'], [240, 240, 'P'], [480, 240, 'P']], [[0, 480, 'A'], [480, 240, 'S']],
  [[0, 240, 'A'], [240, 240, 'U'], [480, 240, 'A']], [[0, 240, 'A'], [240, 240, 'S'], [480, 240, 'P']],
  [[0, 360, 'A'], [360, 120, 'P'], [480, 240, 'P']], [[0, 240, 'A'], [240, 240, 'L'], [480, 240, 'A']],
  [[0, 480, 'A'], [480, 240, 'R']], [[0, 240, 'A'], [240, 240, 'S'], [480, 240, 'A']],
  [[0, 240, 'A'], [240, 480, 'P']], [[0, 120, 'A'], [120, 120, 'U'], [240, 240, 'A'], [480, 240, 'P']],
];
const FAMILY68 = [
  [[0, 1, 8, 0], [1, 3, 6, 10], [2, 4, 6, 5]],
  [[0, 8, 1, 0], [1, 10, 3, 5], [2, 5, 7, 11]],
  [[0, 0, 1, 8], [1, 3, 1, 10], [2, 4, 9, 5]],
];
const CELLS34 = [
  [[0, 1440, 'A']], [[0, 960, 'A'], [960, 480, 'P']], [[0, 480, 'A'], [480, 480, 'P'], [960, 480, 'P']], [[0, 960, 'A'], [960, 480, 'S']],
  [[0, 480, 'A'], [480, 480, 'S'], [960, 480, 'P']], [[0, 720, 'A'], [720, 240, 'P'], [960, 480, 'P']],
  [[0, 480, 'A'], [480, 480, 'U'], [960, 480, 'A']], [[0, 480, 'A'], [480, 240, 'P'], [720, 240, 'P'], [960, 480, 'P']],
  [[0, 960, 'A'], [960, 480, 'R']], [[0, 480, 'A'], [480, 240, 'S'], [720, 240, 'A'], [960, 480, 'P']],
  [[0, 480, 'A'], [480, 240, 'L'], [720, 240, 'A'], [960, 480, 'P']], [[0, 720, 'A'], [720, 240, 'S'], [960, 480, 'P']],
];
const FAMILY34 = [
  [[0, 1, 8, 0], [2, 1, 5, 3], [7, 4, 9, 5]],
  [[0, 8, 1, 0], [2, 3, 4, 11], [7, 9, 10, 4]],
  [[0, 0, 1, 8], [2, 3, 1, 11], [4, 5, 2, 10]],
];
const BASS68_BAR = [[[0, 1440, 'R']], [[0, 720, 'R'], [720, 720, 'O']], [[0, 960, 'R'], [960, 480, 'R']], [[0, 480, 'R'], [480, 240, 'R'], [720, 480, 'O'], [1200, 240, 'R']],
  [[0, 480, 'R'], [480, 240, 'T'], [720, 480, 'O'], [1200, 240, 'N']], [[0, 480, 'R'], [480, 240, 'F'], [720, 480, 'R'], [1200, 240, 'N']]];
const BASS68_HALF = [[[0, 720, 'R']], [[0, 480, 'R'], [480, 240, 'O']], [[0, 480, 'R'], [480, 240, 'R']], [[0, 240, 'R'], [240, 240, 'R'], [480, 240, 'R']],
  [[0, 480, 'R'], [480, 240, 'N']], [[0, 240, 'R'], [240, 240, 'F'], [480, 240, 'N']]];
const BASS34 = [[[0, 1440, 'R']], [[0, 480, 'R'], [480, 480, 'O'], [960, 480, 'O']], [[0, 960, 'R'], [960, 480, 'R']], [[0, 480, 'R'], [480, 480, 'R'], [960, 480, 'O']],
  [[0, 480, 'R'], [480, 480, 'T'], [960, 480, 'N']], [[0, 480, 'R'], [480, 480, 'F'], [960, 480, 'N']]];
const PERC68 = [
  [[0, 36, 100], [480, 42, 56], [720, 38, 80], [1200, 42, 56]],
  [[0, 36, 100], [240, 42, 50], [480, 42, 50], [720, 36, 84], [960, 42, 50], [1200, 42, 56]],
  [[0, 36, 104], [720, 41, 84], [960, 43, 80], [1200, 45, 84]],
];
const PERC34 = [
  [[0, 36, 100], [480, 42, 60], [960, 38, 76]],
  [[0, 36, 100], [240, 42, 50], [720, 42, 50], [1200, 42, 56]],
  [[0, 36, 104], [480, 41, 80], [960, 43, 84]],
];
/** slot and bar in ticks, the time signature's bytes, how late a suspension resolves, a cadence chord's length. */
export const METERS = [
  { name: '4/4', slot: 960, bar: 1920, sig: [4, 2, 24, 8], late: 480, cad: 1920, cells: CELLS, family: CELL_FAMILY, head: HEAD, bass2: BASS_BAR, bass1: BASS_HALF, perc: PERC },
  { name: '6/8', slot: 720, bar: 1440, sig: [6, 3, 36, 8], late: 240, cad: 1440, cells: CELLS68, family: FAMILY68, head: [[480, 240], [600, 120], [240, 480]], bass2: BASS68_BAR, bass1: BASS68_HALF, perc: PERC68 },
  { name: '3/4', slot: 1440, bar: 1440, sig: [3, 2, 24, 8], late: 480, cad: 1440, cells: CELLS34, family: FAMILY34, head: [[960, 480], [1200, 240], [480, 960]], bass2: BASS34, bass1: BASS34, perc: PERC34 },
];
/** The meter by family: Magic mostly lilts (6/8, 3/4), Hunters run in 4/4 or 6/8, Brutes tread in 4/4 or 3/4. */
export const meterFor = (type, draw) => (type === 0 ? (draw < 50 ? 1 : draw < 75 ? 2 : 0) : draw < 60 ? 0 : type === 1 ? 1 : 2);
// TinyChip programs by family (the Beasts composer's): leads and plucks; the mega leads
export const FAMILIES = [{ leads: [0, 9, 7], plucks: [15, 17, 13] }, { leads: [2, 1, 8], plucks: [12, 19, 6] }, { leads: [3, 4, 5], plucks: [16, 14, 18] }];
export const MEGA_LEADS = [50, 65];
const OCTAVE = [0, -1, 0, -1], PAN = [64, 40, 88, 52, 64, 76];
export const DAY_KNOBS = ['the episode takes the next sequence', 'the voices enter in reverse order', 'tempo -4 BPM, tenuto', 'tempo -2 BPM, tenuto', 'tempo +2 BPM, staccato', 'tempo +4 BPM, staccato'];
export const ORNAMENT_NAMES = ['upper graces', 'lower graces', 'mordents', 'turns', 'trills', 'runs into the next note'];
const low32 = (x) => Number(BigInt(x) & 0xffffffffn);

/** The Round as notes. */
export function roundScore(sp, mega, seedKey, drift = null) {
  const seed = BigInt(String(seedKey).replace(/^seed:/, ''));
  const fold = Number((seed & 0xffffffffn) ^ ((seed >> 32n) & 0xffffffffn));
  const R = rng((fold ^ imul(sp.id, 0x85ebca77) ^ 0x524f554e) >>> 0);
  const K = sp.tier <= 2 ? 4 : 3;
  // the purchase's draws, in a fixed order
  const shift = R.pick([0, 0, 0, 5, 7, 10, 2, 3]), keepMode = R.int(2), modePick = R.int(ROUND_MODES.length);
  const bpm0 = [96, 110, 84][sp.type] + R.int(29);
  let loopDraw = R.int(65536), hr = R.int(3), contour = R.int(4), roleSeed = R(), cellSeed = R();
  let bassFig = R.int(6), bassOn = sp.tier <= 3 || R.int(100) < 70, percI = R.int(3), percOn = R.int(100) < (sp.tier <= 2 ? 70 : 40);
  let epKind = R.int(EPISODES.length), epLeader = R.int(K), ornI = R.pick([0, 0, 1, 2]);
  const ornSeed = R.int(100), ornKind = R.int(3);
  let shape = R.int(4), susI = R.int(3);
  const loopDrawB = R.int(65536);
  // the meter is the purchase's, like its key: no clock of drift changes it
  const glDraw = R.int(20), glSeed0 = R();
  const mi = meterFor(sp.type, R.int(100)), meter = METERS[mi], SL = meter.slot, BR = meter.bar, late = meter.late, CADL = meter.cad;
  const own = seed === 0n;
  const tonic = own ? sp.tonicPc : (sp.tonicPc + shift) % 12, mode = own || keepMode ? sp.mode : ROUND_MODES[modePick];
  // drift: the month brings a new loop and new lines, the week re-voices and re-dresses them, the day turns one knob
  const changes = [];
  let rot = 0, level0 = 0, reverse = false, bpmDelta = 0, art = 0, loopStep = 0;
  if (drift && drift.rhythm !== null) {
    const m = low32(drift.rhythm);
    loopStep = 1 + (m % 5); hr = (hr + 1 + ((m >>> 8) % 2)) % 3; roleSeed = (roleSeed ^ m) >>> 0; cellSeed = (cellSeed ^ imul(m, 0x9e3779b1)) >>> 0;
    shape = (shape + 1 + ((m >>> 12) % 3)) % 4;
    changes.push('month: new loops and new lines');
  }
  if (drift && drift.rotate !== null) {
    const w = low32(drift.rotate);
    rot = 1 + (w % (K - 1)); contour = (contour + 1 + ((w >>> 4) % 3)) % 4;
    const part = (w >>> 8) % 3; if (part === 0) bassOn = !bassOn; else if (part === 1) percOn = !percOn;
    bassFig = (bassFig + 1 + ((w >>> 10) % 5)) % 6; percI = (percI + 1 + ((w >>> 20) % 2)) % 3; level0 = (w >>> 12) % 2;
    ornI = (w >>> 14) % 3; susI = (w >>> 22) % 3;
    epLeader = (epLeader + 1 + ((w >>> 18) % (K - 1))) % K;
    changes.push('week: the instruments trade voices, the contour is ' + CONTOUR_NAMES[contour] + (part === 0 ? ', the bass ' + (bassOn ? 'joins' : 'rests') : part === 1 ? ', the percussion ' + (percOn ? 'joins' : 'rests') : '') + (level0 ? ', it starts moving' : ''));
  }
  if (drift) {
    const k = drift.dayKnob;
    if (k === 0) epKind = (epKind + 1) % EPISODES.length; else if (k === 1) reverse = true; else { bpmDelta = drift.delta; art = k >= 4 ? 2 : 1; }
    changes.push('day: ' + DAY_KNOBS[k]);
  }
  // ornaments grow with the track's age: 5% more of the notes every 25 days of drift (60% more at most, from day 301, on
  // top of the purchase's or the week's share), a new figure at days 60, 120, 180 and 270, and more notes
  // that may carry one (the chord tones first, every note of a beat or longer from day 60, eighths from 180)
  const age = drift ? drift.day : 1, stage = age < 60 ? 0 : age < 120 ? 1 : age < 180 ? 2 : age < 270 ? 3 : 4;
  const orn = Math.min(85, [0, 12, 24][ornI] + Math.min(60, Math.floor((age - 1) / 25) * 5));
  const palette = [1 + ornKind, ...[3, 4, 5, 6].slice(0, stage)];
  const ornament = (notes, key, after) => notes.map((n, k) => {
    if (!orn || n.len < (stage >= 3 ? 240 : 480) || (stage < 1 && !n.anchor)) return n;
    const h = mix(ornSeed, key * 8 + k);
    return h % 100 < orn ? { ...n, grace: palette[(h >>> 8) % palette.length], to: k + 1 < notes.length ? notes[k + 1].d : after } : n;
  });
  if (drift && age >= 26) changes.push('age: ornaments on ' + orn + '% of the notes, ' + new Set(palette).size + (new Set(palette).size === 1 ? ' kind' : ' kinds') + ' of figure');
  const scale = MODE_SCALES[mode];
  // the loop and its slots
  const l8 = loopsFor(mode, true), l4 = loopsFor(mode, false);
  if (mi === 2) hr = 1; // in 3/4 a slot is a bar: four chords, a bar each
  if (hr === 2 && !l8.length) hr = 0;
  // a month's loop is always another one: its step is 1 to the pool's size less one; the second loop is
  // always another one than the first
  const pool = hr === 2 ? l8 : l4, loopI = (loopDraw + (loopStep ? 1 + ((loopStep - 1) % (pool.length - 1)) : 0)) % pool.length;
  const S = hr === 1 ? 4 : 8, cyc = S * SL;
  // the species motif, from the tonic, and its rhythm
  const motif = sp.degrees.slice(0, 4).map((d) => d - sp.degrees[0]);
  const headI = [sp.id % 3, Math.floor(sp.id / 3) % 3], headR = headI.map((h) => meter.head[h]);
  const centre = CONTOURS[K][contour], shapes = SHAPES[K][shape], susShare = [35, 55, 75][susI];
  // a slot's notes from a cell: { t, len, d, anchor }
  const cellNotes = (cell, t0, a, next, role) => {
    const out = [];
    let p = a;
    for (const [off, len, src] of meter.cells[cell]) {
      if (src === 'R') continue;
      const d = src === 'A' ? a : src === 'P' ? passing(p, next) : src === 'U' ? a + 1 : src === 'L' ? a - 1 : skip(a, role, next >= a);
      out.push({ t: t0 + off, len, d, anchor: off === 0 }); p = d;
    }
    return out;
  };
  /** A round over a loop: its deals, its theme and its lines. `tag` keeps the two rounds' draws apart. */
  const makeRound = (loop, tag) => {
    const chords = hr === 0 ? loop.flatMap((r) => [r, r]) : loop.slice();
    const allowed = chords[1] === chords[0] ? [0, 1, 2] : [1, 2];
    let forced = allowed[0];
    for (const r of allowed) if (Math.abs(nearest(motif[2], mod7(chords[1] + 2 * r)) - motif[2]) < Math.abs(nearest(motif[2], mod7(chords[1] + 2 * forced)) - motif[2])) forced = r;
    const roles = dealRoles(K, chords, rng(mix(roleSeed, tag)), forced, shapes), cseed = mix(cellSeed, tag);
    // the theme's chord tones: a line starts above or below its centre by its shape (the first on the tonic)
    // and then moves the way of its shape, an octave over when that would take it too far from its centre
    const theme = [];
    for (let j = 0; j < K; j++) {
      theme.push([]);
      for (let s = 0, prev = 0; s < S; s++) {
        const cls = mod7(chords[s] + 2 * roles[s][j]);
        let d;
        if (j === 0 && s === 0) d = 0;
        else if (j === 0 && s === 1) d = nearest(motif[2], cls);
        else if (s === 0 || shapeRestart(shapes[j], s, S)) d = nearest(centre[j] + SHAPE_START[shapes[j]], cls);
        else {
          d = prev + shapeDelta(shapeWant(shapes[j], s, S), prev, cls);
          if (Math.abs(d - centre[j]) > 6) d += d > centre[j] ? -7 : 7;
        }
        theme[j].push(d); prev = d;
      }
    }
    const anchorAfter = (j, s) => (s + 1 < S ? theme[j][s + 1] : theme[(j + 1) % K][0]);
    // suspensions: past its opening bar, where a line steps down across a chord change and no other line
    // holds the tone it steps to, it may hold its note over the change and step down a beat late
    const sus = theme.map((line, j) => line.map((a, s) => s >= 2 && s + 1 < S && chords[s + 1] !== chords[s] && line[s + 1] === a - 1
      && roles[s + 1].filter((r) => r === roles[s + 1][j]).length === 1 && mix(cseed ^ 0x5355, j * 16 + s) % 100 < susShare));
    const lineCache = {};
    /** Line j at a level: its first bar is the motif (line 0) or the motif's rhythm and steps, the rest cells by the line's activity. */
    const lineNotes = (j, level) => {
      const key = j * 4 + level;
      if (lineCache[key]) return lineCache[key];
      const fam = meter.family[sp.type][ACTIVITY[level][j]], h = mix(cseed, j * 8 + level + 1);
      const pick = (k) => fam[(h >>> (2 * k)) % 4];
      const end = level === 0 ? (h >>> 10) % 2 : pick(4);
      const plan = S === 8 ? [pick(0), pick(1), pick(0), pick(2), pick(0), pick(1), pick(3), end] : [pick(0), pick(1), pick(2), end];
      const out = [];
      for (let s = 0; s < S; s++) {
        const a = theme[j][s], next = anchorAfter(j, s), okey = tag * 1024 + j * 64 + s * 4 + level, held = s > 0 && sus[j][s - 1];
        let notes;
        if (s < 2) {
          // the motif's weak notes stay when they move by step, and pass by step when they do not
          const want = a + (s === 0 ? motif[1] - motif[0] : motif[3] - motif[2]), [l0, l1] = headR[s];
          const weak = Math.abs(want - a) <= 1 || Math.abs(want - next) <= 1 ? want : passing(a, next);
          notes = [{ t: s * SL, len: l0, d: a, anchor: true }, { t: s * SL + l0, len: l1, d: weak, anchor: false }];
          if (j === 0) { out.push(...notes); continue; }
        } else if (held || sus[j][s]) {
          // the slot's tone arrives a beat late under the note held over, and is held over in its turn
          notes = [{ t: s * SL + (held ? late : 0), len: (held ? SL - late : SL) + (sus[j][s] ? late : 0), d: a, anchor: !held }];
        } else notes = cellNotes(plan[s], s * SL, a, next, roles[s][j]);
        out.push(...ornament(notes, okey, next));
      }
      return (lineCache[key] = out);
    };
    return { loop, chords, roles, theme, lineNotes, suspensions: sus.flat().filter(Boolean).length };
  };
  const RA = makeRound(pool[loopI], 1), RB = makeRound(pool[(loopI + 1 + (loopDrawB % (pool.length - 1))) % pool.length], 2);
  const { loop, chords, roles, theme } = RA;
  // the form: the round, the episode, the round again, the cadence
  // (fewer turns where a turn is long: four voices over eight chords, and 3/4)
  const CA = S === 8 ? (K === 4 ? 4 : K + 1) : mi === 2 ? K + 1 : 2 * K, CB = S === 8 ? 3 : mi === 2 ? K : K + 2;
  const epStart = CA * cyc, bStart = epStart + EP_SLOTS * SL, cadStart = bStart + CB * cyc, end = cadStart + 2 * CADL;
  const cad = cadenceRoot(mode), tonicDim = quality(scale, 0) === 'd';
  const slots = [];
  for (let g = 0; g < CA + CB; g++) for (let s = 0; s < S; s++) slots.push({ t: (g < CA ? g * cyc : bStart + (g - CA) * cyc) + s * SL, root: (g < CA ? RA : RB).chords[s], sect: g < CA ? 'A' : 'B' });
  const E = EPISODES[epKind];
  for (let i = 0; i < EP_UNITS; i++) slots.push({ t: epStart + i * SL, root: mod7(E.step * i), sect: 'episode' });
  slots.push({ t: epStart + EP_UNITS * SL, root: cad, sect: 'join' }, { t: cadStart, root: cad, sect: 'join' }, { t: cadStart + CADL, root: 0, sect: 'join' });
  slots.sort((a, b) => a.t - b.t);
  // the episode leader's line: one cell on every chord of the sequence
  const epCell = meter.family[sp.type][1 + (mix(cellSeed, 977) % 2)][(mix(cellSeed, 978) >>> 3) % 4];
  const epAnchors = [];
  let ep = 0;
  for (let i = 0; i < EP_UNITS; i++) {
    const cls = mod7(E.step * i + 2 * E.cycle[i % 3]);
    ep = i === 0 ? nearest(2, cls) : nearest(ep, cls);
    if (ep > 9) ep -= 7; else if (ep < -5) ep += 7;
    epAnchors.push(ep);
  }
  const epClose = (from, role) => nearest(from, mod7(cad + 2 * role));
  // which line a voice (by entry) plays in round cycle g, and its chord member at a slot of it
  const roleAt = (i, g, s) => (g < CA ? RA : RB).roles[s][(g - i) % K];
  // the leader starts the episode on the tonic: a voice that did not end the round on its last chord's root
  while (roleAt(epLeader, CA - 1, S - 1) === 0) epLeader = (epLeader + 1) % K;
  const epVoices = [0, 1, 2].map((q) => (epLeader + q) % K);
  // the episode's close and the cadence: deals that keep no root or fifth from the chord before or into the one after
  const epDeal = joinDeal(TRIPLES, epVoices.map((_, q) => E.cycle[(EP_UNITS - 1 - q) % 3]), mod7(E.step * (EP_UNITS - 1)) !== cad, epVoices.map((i) => roleAt(i, CA, 0)), true, mix(roleSeed, 31) % 27);
  const before = [...Array(K).keys()].map((i) => roleAt(i, CA + CB - 1, S - 1));
  const noFifth = (f) => (tonicDim ? f.map((r) => (r === 2 ? 0 : r)) : f);
  let cadDeal = null, endDeal = null, cadP = 1 << 30;
  for (let k = 0; k < ASSIGN[K].length; k++) {
    const b = ASSIGN[K][(mix(roleSeed, 32) + k) % ASSIGN[K].length], f = joinDeal(ASSIGN[K].filter((x) => x[0] === 0).map(noFifth), b, true, null, false);
    const p = dealPenalty(before, b, RB.chords[S - 1] !== cad) + dealPenalty(b, f, true);
    if (p < cadP) { cadDeal = b; endDeal = f; cadP = p; }
  }
  const epLead = [];
  for (let i = 0; i < EP_UNITS; i++) {
    const a = epAnchors[i], next = i + 1 < EP_UNITS ? epAnchors[i + 1] : epClose(a, 0);
    let notes;
    if (E.motif) {
      // the motif's first half bar on every chord of the sequence
      const want = a + motif[1] - motif[0], weak = Math.abs(want - a) <= 1 || Math.abs(want - next) <= 1 ? want : passing(a, next);
      notes = [{ t: i * SL, len: headR[0][0], d: a, anchor: true }, { t: i * SL + headR[0][0], len: headR[0][1], d: weak, anchor: false }];
    } else notes = cellNotes(epCell, i * SL, a, next, E.cycle[i % 3]);
    epLead.push(...(stage >= 2 ? ornament(notes, 500 + i, next) : notes)); // the episode joins in from day 120
  }
  // voices by order of entry; the week turns which instrument (channel) takes which entry
  const chanOf = (i) => ((reverse ? K - 1 - i : i) + rot) % K;
  const voices = [];
  for (let i = 0; i < K; i++) {
    const notes = [];
    let last = 0;
    for (let g = i; g < CA + CB; g++) {
      const u = g - i, level = Math.min(2, level0 + levelAt(u, K)), t0 = g < CA ? g * cyc : bStart + (g - CA) * cyc;
      for (const n of (g < CA ? RA : RB).lineNotes(u % K, level)) notes.push({ ...n, t: t0 + n.t, sect: g < CA ? 'A' : 'B' });
      if (g === CA - 1) {
        // the episode: the leader, then two voices half a bar apart, each a step of the sequence on; a fourth voice rests
        const q = (i - epLeader + K) % K;
        last = notes[notes.length - 1].d;
        if (q < 3) {
          let tr = mod7(E.step * q); if (tr > 3) tr -= 7;
          for (const n of epLead) if (n.t + q * SL < EP_UNITS * SL) { notes.push({ ...n, t: epStart + q * SL + n.t, d: n.d + tr, sect: 'episode' }); last = n.d + tr; }
          notes.push({ t: epStart + EP_UNITS * SL, len: SL, d: epClose(last, epDeal[q]), anchor: true, sect: 'join' });
        }
      }
    }
    // the cadence: the mode's cadence chord, then the tonic chord (no fifth on a diminished tonic)
    last = notes[notes.length - 1].d;
    const c1 = nearest(last, mod7(cad + 2 * cadDeal[i]));
    notes.push({ t: cadStart, len: CADL, d: c1, anchor: true, sect: 'join' }, { t: cadStart + CADL, len: CADL, d: nearest(c1, mod7(2 * endDeal[i])), anchor: true, sect: 'join' });
    voices.push({ entry: i, ch: chanOf(i), notes });
  }
  // the bass on the roots, and the percussion
  const bass = [], perc = [];
  const root = (r) => (mod7(r) > 3 ? mod7(r) - 7 : mod7(r));
  if (bassOn) {
    // every chord's span [time, root, slots it lasts (0: a held note), length]; a figure's last note may step to the next root
    const spans = [];
    for (let g = 0; g < CA + CB; g++) {
      const base = g < CA ? g * cyc : bStart + (g - CA) * cyc, rd = g < CA ? RA : RB;
      if (hr === 0) for (let b = 0; b < 4; b++) spans.push([base + 2 * b * SL, rd.loop[b], 2]);
      else for (let s = 0; s < S; s++) spans.push([base + s * SL, rd.chords[s], 1]);
    }
    for (let i = 0; i < EP_UNITS; i++) spans.push([epStart + i * SL, E.step * i, 1]);
    spans.push([epStart + EP_UNITS * SL, cad, 0, SL], [cadStart, cad, 0, CADL], [cadStart + CADL, 0, 0, CADL]);
    spans.sort((a, b) => a[0] - b[0]);
    spans.forEach(([t, r, n, len], k) => {
      const d = root(r);
      if (!n) { bass.push({ t, len, d, anchor: true }); return; }
      const nd = root(spans[k + 1][1]), toward = nd > d ? nd - 1 : nd < d ? nd + 1 : d;
      for (const [off, l, src] of (n === 2 ? meter.bass2 : meter.bass1)[bassFig]) bass.push({ t: t + off, len: l, d: src === 'R' ? d : src === 'O' ? d + 7 : src === 'T' ? d + 2 : src === 'F' ? d + 4 : toward, anchor: off === 0 });
    });
  }
  if (percOn) {
    // from the second voice's entry; a cymbal where the round comes back and on the last chord
    for (let t = cyc; t < cadStart; t += BR) for (const [off, key, v] of meter.perc[percI]) perc.push({ t: t + off, key, v });
    perc.push({ t: bStart, key: 49, v: 84 }, { t: cadStart + CADL, key: 49, v: 90 }, { t: cadStart + CADL, key: 36, v: 104 });
    perc.sort((a, b) => a.t - b.t);
  }
  // harp glissandi: into the episode, the return, the cadence or the last chord; the week moves them
  const glSeed = drift && drift.rotate !== null ? mix(glSeed0, low32(drift.rotate)) : glSeed0;
  const glAt = [[epStart, 'the episode'], [bStart, 'the return'], [cadStart, 'the cadence'], [cadStart + CADL, 'the last chord']];
  const glPlan = glissPlan(glDraw, glSeed, [0, 1, 3, 3, 2]);
  const gliss = glPlan.flatMap((x) => glissando(x, glAt[x.spot][0], SL === 1440 ? 960 : SL, glSeed));
  const bpm = bpm0, base = tonic < 6 ? 60 + tonic : 48 + tonic;
  let us = Math.round(60e6 / bpm);
  if (bpmDelta) { const D = 60000000 + bpmDelta * us; us = Math.min(1048575, Math.floor((2 * 60000000 * us + D) / (2 * D))); }
  const fam = FAMILIES[sp.type], lead = sp.id % 3;
  const programs = [fam.leads[lead], fam.leads[(lead + 1) % 3], fam.plucks[1], fam.plucks[2], fam.plucks[0]];
  if (mega) { programs[0] = MEGA_LEADS[sp.id % 2]; programs[5] = MEGA_LEADS[(sp.id + 1) % 2]; }
  const info = {
    key: NOTE[tonic] + ' ' + MODE_NAMES[mode], bpm: Math.round(60e6 / us), voices: K, meter: meter.name,
    loop: loop.map((r) => numeral(scale, r)).join(' – ') + (hr === 0 || mi === 2 ? ' · a bar each' : ' · half a bar each'), loopBars: cyc / BR,
    form: 'round ' + CA + ' turns · episode · round ' + CB + ' turns · cadence',
    loopB: RB.loop.map((r) => numeral(scale, r)).join(' – '),
    theme: theme.map((l) => l.join(' ')).join(' | '), themeB: RB.theme.map((l) => l.join(' ')).join(' | '), themeBars: (K * cyc) / BR, contour: CONTOUR_NAMES[contour],
    shapes: shapes.map((g) => SHAPE_NAMES[g]).join(', '), motifRhythm: headI.map((h) => HEAD_NAMES[h]).join(' then '),
    suspensions: RA.suspensions + ' in the first theme, ' + RB.suspensions + ' in the second',
    episode: E.name + ', led by voice ' + (epLeader + 1), cadence: numeral(scale, cad) + ' – ' + numeral(scale, 0),
    bass: bassOn ? BASS_NAMES[bassFig] : 'none', percussion: percOn ? PERC_NAMES[percI] : 'none',
    ornaments: orn ? orn + '% of the notes: ' + [...new Set(palette)].map((g) => ORNAMENT_NAMES[g - 1]).join(', ') : 'none',
    glissandi: glPlan.length ? glPlan.map((x) => (x.up ? 'up' : 'down') + (x.high ? ', an octave higher,' : '') + ' into ' + glAt[x.spot][1]).join(', ') : 'none',
    entries: voices.map((v) => 'ch' + (v.ch + 1)).join(' → '), drift: changes.length ? changes.join(' · ') : 'as written',
    seconds: Math.round((end / TPQ) * (us / 1e6)),
  };
  return { gliss, glPlan, glAt: glAt.map((x) => x[0]), K, S, cyc, slot: SL, bar: BR, late, cadLen: CADL, meter: mi, sig: meter.sig, CA, CB, epStart, bStart, cadStart, end, slots, voices, bass, perc, scale, base, tonic, mode, us, art, mega, programs, chords, loop, hr, roles, theme, second: RB, first: RA, epKind, info };
}

// ── the file ──
const u32be = (v) => [(v >>> 24) & 255, (v >>> 16) & 255, (v >>> 8) & 255, v & 255];
const vlq = (n) => { const b = [n & 127]; while ((n >>= 7)) b.unshift((n & 127) | 128); return b; };
/** A track's bytes from [time, order, ...message] events (note-offs before note-ons at the same tick). */
function trackBytes(events, end) {
  events.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const out = [];
  let t = 0;
  for (const [time, , ...msg] of events) { out.push(...vlq(time - t), ...msg); t = time; }
  out.push(...vlq(Math.max(end, t) - t), 0xff, 0x2f, 0);
  return out;
}
/** A voice's sounding notes [time, length, pitch, velocity], graces written out. */
export function soundingNotes(score, part, octave) {
  const pitch = (d) => pitchOf(score.base + 12 * octave, score.scale, d), out = [];
  for (const n of part) {
    // staccato halves the short notes, tenuto closes the gap
    const len = score.art === 2 && n.len <= 480 ? n.len >> 1 : n.len - (score.art === 1 ? 5 : 20), v = (n.anchor ? (n.t % score.bar === 0 ? 96 : 88) : 76);
    let g = n.grace || 0;
    const step = Math.sign((n.to ?? n.d) - n.d);
    // a figure that does not fit its note gives way: a run or trill to a mordent, a mordent to the plain note
    if (g === 6 && (n.len < 480 || Math.abs(n.to - n.d) < 3)) g = 3;
    if ((g === 5 && len < 360) || (g === 4 && len < 300)) g = 3;
    if ((g === 3 && len < 180) || ((g === 1 || g === 2) && len < 120)) g = 0;
    const fig = (ds, unit) => { ds.forEach((d, k) => out.push([n.t + k * unit, unit, pitch(n.d + d), k ? v - 10 : v])); out.push([n.t + ds.length * unit, len - ds.length * unit, pitch(n.d), v]); };
    if (g === 1 || g === 2) out.push([n.t, 80, pitch(n.d + (g === 1 ? 1 : -1)), v - 10], [n.t + 80, len - 80, pitch(n.d), v]);
    else if (g === 3) fig([0, 1], 60);
    else if (g === 4) fig([1, 0, -1], 60);
    else if (g === 5) fig(len >= 700 ? [0, 1, 0, 1, 0, 1] : [0, 1, 0, 1], 60);
    else if (g === 6) out.push([n.t, n.len - 260, pitch(n.d), v], [n.t + n.len - 240, 120, pitch(n.d + step), v - 12], [n.t + n.len - 120, 100, pitch(n.d + 2 * step), v - 8]);
    else out.push([n.t, len, pitch(n.d), v]);
  }
  return out;
}
/** The harp glissandi's sounding notes [time, length, pitch, velocity]. */
export const glissNotes = (score) => score.gliss.map((n) => [n.t, n.len, pitchOf(score.base, score.scale, n.d), n.v]);
export function roundMidi(sp, mega, seedKey, drift = null) {
  const sc = roundScore(sp, mega, seedKey, drift);
  const tempo = trackBytes([[0, 0, 0xff, 0x51, 3, (sc.us >> 16) & 255, (sc.us >> 8) & 255, sc.us & 255], [0, 1, 0xff, 0x58, 4, ...sc.sig]], sc.end);
  const bodies = [tempo];
  const track = (ch, program, vol, pan, notes) => {
    const ev = ch === 9 ? [] : [[0, 0, 0xc0 | ch, program], [0, 1, 0xb0 | ch, 7, vol], [0, 2, 0xb0 | ch, 10, pan], [0, 3, 0xb0 | ch, 91, 40]];
    for (const [t, len, p, v] of notes) {
      if (p < 0 || p > 127 || len <= 0) throw new Error(`round: note ${p} of ${len} ticks on channel ${ch}`);
      ev.push([t, 5, 0x90 | ch, p, v], [t + len, 4, 0x80 | ch, p, 0]);
    }
    bodies.push(trackBytes(ev, sc.end));
  };
  const isLead = (p) => p < 12 || MEGA_LEADS.includes(p);
  const byChan = [...sc.voices].sort((a, b) => a.ch - b.ch);
  for (const v of byChan) track(v.ch, sc.programs[v.ch], isLead(sc.programs[v.ch]) ? 72 : 118, PAN[v.ch], soundingNotes(sc, v.notes, OCTAVE[v.ch]));
  if (sc.bass.length) track(4, sc.programs[4], 118, PAN[4], soundingNotes(sc, sc.bass, -2));
  if (mega) track(5, sc.programs[5], 56, PAN[5], soundingNotes(sc, byChan[0].notes, OCTAVE[0] + 1));
  if (sc.gliss.length) track(GLISS_CHANNEL, sc.programs[2], 100, 100, glissNotes(sc));
  if (sc.perc.length) track(9, 0, 0, 0, sc.perc.map((h) => [h.t, 120, h.key, h.v]));
  const out = [0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, bodies.length, TPQ >> 8, TPQ & 255];
  for (const b of bodies) out.push(0x4d, 0x54, 0x72, 0x6b, ...u32be(b.length), ...b);
  const channels = [...byChan.map((v) => v.ch), ...(sc.bass.length ? [4] : []), ...(mega ? [5] : []), ...(sc.gliss.length ? [GLISS_CHANNEL] : []), ...(sc.perc.length ? [9] : [])];
  return { midi: Uint8Array.from(out), info: { ...sc.info, channels }, score: sc };
}
/** A format-1 file: a tempo track, then one track per part { ch, program, vol, pan, notes: [time, length,
 * pitch, velocity] } (channel 9, the kit, takes no program). The Sound Checks write theirs with it. */
export function smfFile(us, sig, end, parts) {
  const bodies = [trackBytes([[0, 0, 0xff, 0x51, 3, (us >> 16) & 255, (us >> 8) & 255, us & 255], [0, 1, 0xff, 0x58, 4, ...sig]], end)];
  for (const { ch, program, vol, pan, notes } of parts) {
    const ev = ch === 9 ? [] : [[0, 0, 0xc0 | ch, program], [0, 1, 0xb0 | ch, 7, vol], [0, 2, 0xb0 | ch, 10, pan], [0, 3, 0xb0 | ch, 91, 40]];
    for (const [t, len, p, v] of notes) {
      if (p < 0 || p > 127 || len <= 0 || v < 1 || v > 127) throw new Error(`smf: note ${p} of ${len} ticks at velocity ${v} on channel ${ch}`);
      ev.push([t, 5, 0x90 | ch, p, v], [t + len, 4, 0x80 | ch, p, 0]);
    }
    bodies.push(trackBytes(ev, end));
  }
  const out = [0x4d, 0x54, 0x68, 0x64, 0, 0, 0, 6, 0, 1, 0, bodies.length, TPQ >> 8, TPQ & 255];
  for (const b of bodies) out.push(0x4d, 0x54, 0x72, 0x6b, ...u32be(b.length), ...b);
  return Uint8Array.from(out);
}
