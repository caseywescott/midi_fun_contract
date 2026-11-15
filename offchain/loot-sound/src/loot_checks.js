// Loot Dungeon Sound Checks: the Beast's band warms up.
//
// The Beasts composer's Sound Check is one preset playing a scale pattern, a held note and an arpeggio
// three times, then the drum kit. A Loot Sound Check is a routine for the Beast's whole band (two
// leads, two plucks, a bass, the kit; the mega double on top), ten bars of 4/4 in the Beast's key:
//
//   an opening (tuning over a drone, a count-in, or the motif alone)
//   three drills, drawn without repeats from nine (DRILLS), each two bars and each showing something
//     else: the motif called and answered, the mode's scale in thirds, the note that gives the mode its
//     colour, an arpeggio through the cadence, a canon a beat apart, leaps with a swell, a drum break,
//     trills and graces, the motif handed round the band
//   a close (a run into a stinger, a scale that settles, or the motif as a tag)
//
// Every pitched note is in the Beast's mode. Take 0 is the species' own Sound Check; any other take is
// another routine in the same key with the same motif. Integer-only and table-driven.
//
//   soundCheckScore(species, mega, take) -> the notes and the readout
//   soundCheckMidi(species, mega, take)  -> { midi: Uint8Array (format 1), info, score }

import { rng, TPQ, glissPlan, glissando } from './loot_editions.js';
import { MODE_SCALES, MODE_NAMES, cadenceRoot, numeral, quality, FAMILIES, MEGA_LEADS, smfFile } from './loot_rounds.js';

const imul = Math.imul;
const NOTE = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const mod7 = (d) => ((d % 7) + 7) % 7;
const sign = (x) => (x > 0 ? 1 : x < 0 ? -1 : 0);
export const BAR = 1920, SEG = 2 * BAR;
// channels: the two leads, the two plucks, the bass, the mega double; their octaves and pans
export const PART_NAMES = ['lead', 'second lead', 'pluck', 'second pluck', 'bass', 'mega double', 'harp glissando'];
const OCTAVE = [0, -1, 0, -1, -2, 1, 0], PAN = [64, 40, 88, 52, 64, 76, 100];
/** The degree that gives each mode its colour: Dorian's sixth, Phrygian's second, Locrian's fifth,
 * Aeolian's sixth, harmonic minor's seventh, Dorian #4's fourth. */
export const COLOUR = { 4: 5, 5: 1, 6: 4, 7: 5, 8: 6, 26: 3 };
// the motif's six notes in a bar, by the species' rhythm (even, dotted, snapped)
const MOTIF_RHYTHM = [[240, 240, 240, 240, 480, 480], [360, 120, 360, 120, 480, 480], [120, 360, 120, 360, 480, 480]];
// a bar of the kit by family: (offset, key, velocity)
const GROOVE = [
  [[0, 36, 100], [480, 42, 60], [720, 42, 50], [960, 38, 84], [1440, 42, 60], [1680, 42, 50]],
  [[0, 36, 100], [240, 42, 56], [480, 38, 84], [720, 36, 80], [960, 36, 96], [1200, 42, 56], [1440, 38, 88], [1680, 42, 56]],
  [[0, 36, 108], [480, 41, 84], [960, 36, 100], [1200, 36, 84], [1440, 43, 88]],
];
export const CHECK_DRUMS = [36, 38, 41, 42, 43, 45, 49];

// Each piece of the routine writes two bars from tick t. `c` is the band: c.put(part, t, len, degree,
// velocity), c.hit(t, key, velocity), the motif c.m and its rhythm c.mr, the cadence root c.cad, the
// colour degree c.colour, the fifth above the tonic or the octave where that fifth is diminished
// (c.fifth), the family c.type. `v` is the piece's own draw (0-3).
const motifOn = (c, part, t, f, vel) => { let at = t; c.m.forEach((d, k) => { c.put(part, at, c.mr[k] - 20, f(d), vel); at += c.mr[k]; }); };
const roll = (c, part, t, len, vel) => [0, 2, 4, 7].forEach((d, k) => c.put(part, t + k * 60, len - k * 60, d, vel));

export const OPENINGS = [
  { name: 'tuning over a drone', fn(c, t) {
    c.put(4, t, SEG - 20, 0, 70); c.put(3, t + 480, SEG - 500, c.fifth, 60);
    // the lead slides up to the fifth, turns on it and comes down to the tonic
    c.put(0, t + 960, 70, 2, 70); c.put(0, t + 1040, 70, 3, 74); c.put(0, t + 1120, 780, 4, 88);
    [5, 4, 3, 4].forEach((d, k) => c.put(0, t + 1920 + k * 120, 110, d, 80));
    c.put(0, t + 2400, 460, 4, 88); c.put(0, t + 2880, 460, 2, 84); c.put(0, t + 3360, 460, 0, 92); c.put(1, t + 3360, 460, 0, 70);
  } },
  { name: 'a count-in', fn(c, t) {
    [70, 70, 90, 90].forEach((v, k) => c.hit(t + k * 480, 42, v)); c.hit(t + 1680, 45, 84); c.hit(t + 1800, 43, 92);
    c.hit(t + BAR, 36, 104); c.hit(t + BAR, 49, 84);
    roll(c, 2, t + BAR, 1500, 86); c.put(4, t + BAR, 1880, 0, 84);
    c.put(0, t + BAR + 960, 460, c.fifth === 4 ? 4 : 2, 72); c.put(0, t + BAR + 1440, 460, 7, 80);
  } },
  { name: 'the motif alone, and its echo', fn(c, t) { motifOn(c, 0, t, (d) => d, 92); motifOn(c, 1, t + BAR, (d) => d, 62); } },
];

export const DRILLS = [
  { name: 'the motif called and answered', fn(c, t, v) {
    motifOn(c, 0, t, (d) => d, 92);
    // the answer: upside down from the fifth, or a third higher
    motifOn(c, 1, t + BAR, v & 1 ? (d) => 4 - d : (d) => d + 2, 84);
    c.put(4, t, BAR - 20, 0, 76); c.put(4, t + BAR, BAR - 20, 0, 76);
  } },
  { name: 'the scale in thirds', fn(c, t, v) {
    const down = v & 1;
    for (let k = 0; k < 7; k++) { c.put(2, t + 2 * k * 240, 220, down ? 7 - k : k, 84); c.put(2, t + (2 * k + 1) * 240, 220, down ? 5 - k : k + 2, 76); }
    c.put(2, t + 3360, 460, down ? 0 : 7, 92);
    c.put(4, t, BAR - 20, 0, 76); c.put(4, t + BAR, BAR - 20, 7, 72);
    if (v & 2) for (let k = 0; k < 8; k++) c.hit(t + k * 480, 42, k % 2 ? 46 : 58);
  } },
  { name: "the mode's colour note", fn(c, t) {
    const x = c.colour < 3 ? c.colour + 7 : c.colour;
    // circle the note, lean on it, then step down to the nearest note of the tonic chord
    [x - 1, x, x + 1, x].forEach((d, k) => c.put(0, t + k * 240, 220, d, 80)); c.put(0, t + 960, 940, x, 104);
    let home = x - 1; while (![0, 2, 4].includes(mod7(home)) || (mod7(home) === 4 && c.fifth !== 4)) home--;
    const way = []; for (let d = x; d > home; d--) way.push(d);
    while (way.length < 4) way.unshift(way[0] === x ? x + 1 : x);
    way.slice(-4).forEach((d, k) => c.put(0, t + BAR + k * 240, 220, d, 84)); c.put(0, t + BAR + 960, 940, home, 92);
    c.put(1, t, SEG - 20, 0, 62); c.put(4, t, SEG - 20, 0, 70);
  } },
  { name: 'an arpeggio through the cadence', fn(c, t, v) {
    const k = c.cad > 3 ? c.cad - 7 : c.cad;
    [0, 2, 4, 7, 9, 11, 14, 11, 9, 7, 4, 2, 0, 2, 4, 7].forEach((d, i) => c.put(2, t + i * 120, 100, d, i % 4 ? 72 : 88));
    [k, k + 2, k + 4, k + 7, k + 4, k + 2, k, k + 2].forEach((d, i) => c.put(2, t + BAR + i * 120, 100, d, i % 4 ? 72 : 88));
    roll(c, 2, t + BAR + 960, 900, 90);
    c.put(4, t, BAR - 20, 0, 80); c.put(4, t + BAR, 940, k, 80); c.put(4, t + BAR + 960, 940, 0, 84);
    if (v & 1) for (const at of [480, 1440]) [0, 2, c.fifth === 4 ? 4 : 7].forEach((d) => c.put(3, t + at, 200, d, 66));
  } },
  { name: 'a canon a beat apart', fn(c, t, v) {
    // the motif and two steps home, in eighths; the second lead follows a beat later, an octave below
    const x = c.m[5], a = x === 0 ? 1 : x - sign(x), line = [...c.m, a, a === 0 ? 1 : a - sign(a)], up = v & 1 ? 2 : 0;
    line.forEach((d, k) => { c.put(0, t + k * 240, 220, d, 88); c.put(1, t + 480 + k * 240, 220, d, 78); c.put(0, t + BAR + k * 240, 220, d + up, 88); if (k < 6) c.put(1, t + BAR + 480 + k * 240, 220, d + up, 78); });
    c.put(4, t, BAR - 20, 0, 72); c.put(4, t + BAR, BAR - 20, 0, 72);
  } },
  { name: 'leaps with a swell', fn(c, t, v) {
    [0, 7, c.fifth === 4 ? 4 : 2, 9, 7, 14, 2, 0].forEach((d, k) => c.put(0, t + k * 480, 440, d, v & 1 ? 108 - 8 * k : 52 + 8 * k));
    for (let k = 0; k < 4; k++) { [0, 2, c.fifth === 4 ? 4 : 7].forEach((d) => c.put(3, t + BAR + 240 + k * 480, 120, d, 60)); c.hit(t + BAR + k * 480, 36, 84); }
  } },
  { name: 'a drum break', fn(c, t) {
    for (const [off, key, vel] of GROOVE[c.type]) { c.hit(t + off, key, vel); if (off < 960) c.hit(t + BAR + off, key, vel); }
    [45, 45, 43, 43, 41, 41, 38, 38].forEach((key, k) => c.hit(t + BAR + 960 + k * 120, key, 76 + 5 * k));
    // the bass keeps the motif's rhythm on the root and the fifth
    let at = t; c.mr.forEach((len, k) => { c.put(4, at, len - 20, k % 2 && c.fifth === 4 ? 4 : 0, 84); at += len; });
    c.put(4, t + BAR, 940, 0, 84);
  } },
  { name: 'trills and graces', fn(c, t, v) {
    const ds = v & 1 ? [7, 4, 2, 0] : [0, 2, 4, 7], fig = [[0, 1], [1, 0, -1], [0, 1, 0, 1, 0, 1], []];
    ds.forEach((d0, k) => {
      const d = mod7(d0) === 4 && c.fifth !== 4 ? d0 + 1 : d0, t0 = t + k * 960;
      if (k === 3) { c.put(0, t0, 70, d + 1, 78); c.put(0, t0 + 80, 860, d, 92); }
      else { fig[k].forEach((x, i) => c.put(0, t0 + i * 60, 55, d + x, i ? 78 : 88)); c.put(0, t0 + fig[k].length * 60, 940 - fig[k].length * 60, d, 88); }
      [0, c.fifth === 4 ? 4 : 7, 2, c.fifth === 4 ? 4 : 7].forEach((x, i) => c.put(3, t0 + i * 240, 220, x, 60));
    });
  } },
  { name: 'the motif handed round the band', fn(c, t, v) {
    const order = [0, 2, 1, 3], at = v & 1 ? [7, 4, 2, 0] : [0, 2, 4, 7];
    order.forEach((part, k) => c.m.slice(0, 4).forEach((d, i) => c.put(part, t + k * 960 + i * 240, i === 3 ? 460 : 220, d + at[k], 86)));
    c.put(4, t, SEG - 20, 0, 66);
  } },
];

export const CLOSES = [
  { name: 'a run into a stinger', fn(c, t) {
    const k = c.cad > 3 ? c.cad - 7 : c.cad;
    c.put(4, t, 940, k, 84); c.hit(t, 36, 96); c.hit(t + 480, 36, 88);
    [-1, 0, 1, 2, 3, 4, 5, 6].forEach((d, i) => { c.put(0, t + 960 + i * 120, 110, d, 70 + 5 * i); c.hit(t + 960 + i * 120, 38, 60 + 7 * i); });
    c.put(0, t + BAR, 1400, 7, 104); c.put(1, t + BAR, 1400, c.fifth === 4 ? 4 : 2, 96); roll(c, 2, t + BAR, 1400, 96); c.put(3, t + BAR, 1400, 2, 90); c.put(4, t + BAR, 1400, 0, 100);
    c.hit(t + BAR, 36, 110); c.hit(t + BAR, 49, 96);
  } },
  { name: 'a scale that settles', fn(c, t) {
    for (let k = 0; k < 8; k++) { c.put(0, t + k * 240, 220, 7 - k, 84 - 2 * k); if (k < 7) c.put(2, t + k * 240, 220, 5 - k, 70 - 2 * k); }
    c.put(4, t, BAR - 20, 0, 70);
    c.put(0, t + BAR, 1700, 0, 80); c.put(1, t + BAR, 1700, 0, 70); roll(c, 2, t + BAR, 1700, 76); c.put(4, t + BAR, 1700, 0, 76); c.hit(t + BAR, 36, 80);
  } },
  { name: 'the motif as a tag', fn(c, t) {
    c.m.slice(0, 3).forEach((d, k) => { for (const part of [0, 1, 2, 3, 4]) c.put(part, t + k * 480, 400, d, 96); c.hit(t + k * 480, 36, 96); });
    c.hit(t + 1440, 38, 80); c.hit(t + 1680, 38, 96);
    for (const part of [0, 1, 3, 4]) c.put(part, t + BAR, 1400, 0, 104); roll(c, 2, t + BAR, 1400, 100);
    c.hit(t + BAR, 36, 110); c.hit(t + BAR, 49, 96);
  } },
];

/** The Sound Check as notes. `take` 0 is the species' own; any other number is another routine. */
export function soundCheckScore(sp, mega, take = 0n) {
  const seed = BigInt(String(take).replace(/^seed:/, ''));
  const fold = Number((seed & 0xffffffffn) ^ ((seed >> 32n) & 0xffffffffn));
  const R = rng((fold ^ imul(sp.id, 0x85ebca77) ^ 0x43484b21) >>> 0);
  const scale = MODE_SCALES[sp.mode], tonic = sp.tonicPc, base = tonic < 6 ? 60 + tonic : 48 + tonic;
  const bpm = [104, 120, 92][sp.type] + R.int(21), opening = R.int(OPENINGS.length), close = R.int(CLOSES.length);
  // three drills without repeats: draw from those left
  const left = DRILLS.map((_, k) => k), drills = [];
  for (let k = 0; k < 3; k++) drills.push(left.splice(R.int(left.length), 1)[0]);
  const draws = [R.int(4), R.int(4), R.int(4)];
  const glDraw = R.int(20), glSeed = R();
  const parts = [[], [], [], [], [], [], []], perc = [];
  const band = {
    put(part, t, len, d, v) { parts[part].push({ t, len, d, v }); },
    hit(t, key, v) { perc.push({ t, key, v }); },
    m: sp.degrees.map((d) => d - sp.degrees[0]), mr: MOTIF_RHYTHM[sp.id % 3], cad: cadenceRoot(sp.mode), colour: COLOUR[sp.mode],
    fifth: quality(scale, 0) === 'd' ? 7 : 4, type: sp.type,
  };
  OPENINGS[opening].fn(band, 0);
  drills.forEach((k, i) => DRILLS[k].fn(band, (i + 1) * SEG, draws[i]));
  CLOSES[close].fn(band, 4 * SEG);
  const end = 5 * SEG;
  // harp glissandi: over the first two beats, into the first drill, into the close or into the last chord
  const glAt = [[960, 'at the start'], [SEG, 'into the first drill'], [4 * SEG, 'into the close'], [4 * SEG + BAR, 'into the last chord']];
  const glPlan = glissPlan(glDraw, glSeed, [0, 2, 3, 3, 1]);
  for (const x of glPlan) parts[6].push(...glissando(x, glAt[x.spot][0], 960, glSeed));
  if (mega) for (const n of parts[0]) parts[5].push({ ...n, v: Math.max(40, n.v - 14) });
  for (const p of parts) p.sort((a, b) => a.t - b.t);
  perc.sort((a, b) => a.t - b.t);
  const fam = FAMILIES[sp.type], lead = sp.id % 3;
  const programs = [fam.leads[lead], fam.leads[(lead + 1) % 3], fam.plucks[1], fam.plucks[2], fam.plucks[0]];
  programs[6] = fam.plucks[1];
  if (mega) { programs[0] = MEGA_LEADS[sp.id % 2]; programs[5] = MEGA_LEADS[(sp.id + 1) % 2]; }
  const us = Math.round(60e6 / bpm);
  const info = {
    key: NOTE[tonic] + ' ' + MODE_NAMES[sp.mode], bpm, opening: OPENINGS[opening].name, drills: drills.map((k) => DRILLS[k].name).join(' · '), close: CLOSES[close].name,
    colour: 'degree ' + (band.colour + 1) + ' (' + NOTE[(tonic + scale[band.colour]) % 12] + ')', cadence: numeral(scale, band.cad) + ' – ' + numeral(scale, 0),
    band: parts.map((p, k) => (p.length ? PART_NAMES[k] : null)).filter(Boolean).concat(perc.length ? ['kit'] : []).join(', '),
    glissandi: glPlan.length ? glPlan.map((x) => (x.up ? 'up' : 'down') + (x.high ? ', an octave higher, ' : ' ') + glAt[x.spot][1]).join(', ') : 'none',
    seconds: Math.round((end / TPQ) * (us / 1e6)),
  };
  return { glPlan, glAt: glAt.map((x) => x[0]), parts, perc, scale, base, tonic, mode: sp.mode, us, end, programs, opening, drills, close, mega, info };
}

/** A part's sounding notes [time, length, pitch, velocity]. */
export function checkNotes(score, part) {
  return score.parts[part].map((n) => [n.t, n.len, score.base + 12 * OCTAVE[part] + 12 * Math.floor(n.d / 7) + score.scale[mod7(n.d)], n.v]);
}
export function soundCheckMidi(sp, mega, take = 0n) {
  const sc = soundCheckScore(sp, mega, take), tracks = [], channels = [];
  const isLead = (p) => p < 12 || MEGA_LEADS.includes(p);
  sc.parts.forEach((p, ch) => { if (p.length) { tracks.push({ ch, program: sc.programs[ch], vol: ch === 5 ? 56 : ch === 6 ? 100 : isLead(sc.programs[ch]) ? 72 : 118, pan: PAN[ch], notes: checkNotes(sc, ch) }); channels.push(ch); } });
  if (sc.perc.length) { tracks.push({ ch: 9, notes: sc.perc.map((h) => [h.t, 120, h.key, h.v]) }); channels.push(9); }
  return { midi: smfFile(sc.us, [4, 2, 24, 8], sc.end, tracks), info: { ...sc.info, channels }, score: sc };
}
