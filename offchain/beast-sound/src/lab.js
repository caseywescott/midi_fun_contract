// Beast Sound lab: listening prototypes on top of composer v1.1 and the self-contained MIDI, JS only.
//
//   event tracks   every kill and defeat in Death Mountain's records makes a track; the holder picks
//                  one (Beasts V3 change_track(token_id, track_id)); $SKULL unlocks variations
//   progression    a Beast starts as its own scale; each unlock reveals a layer, in an order
//                  fixed by the Beast (onchain: the unlock transaction's block hash)
//   drift          a never-ending track: each epoch (a day of blocks; with blockHashes, seeded by the epoch's first block hash)
//                  turns at most one small knob, so the music stays itself from day to day
//   specials       the Yeti (species 68): rock groove, yodel, avalanche, stomp
//
// Every function is a pure function of its inputs, like the composer, so each can move to Cairo.
import { catalogueCheck, renderCatalogueCheck } from './sound_check_catalogue.js';
import { cyclopsSoundCheckMidi } from './cyclops_sound_check.js';
import { poseidonHashMany } from './index.js';
import { FAMILIES, MEGA_ALL, MEGA_LEADS, beastFullMidi, beastInstruments, drumEvents, graceOf } from './full_midi.js';

const V11 = { keys: 'mode', even: true, traj: true };
const P = 2n ** 251n + 17n * 2n ** 192n + 1n;
const felt = (x) => ((typeof x === 'string' ? BigInt('0x' + [...x].map((c) => c.charCodeAt(0).toString(16).padStart(2, '0')).join('')) : BigInt(x)) % P + P) % P;
export const H = (...xs) => poseidonHashMany(xs.map(felt));
const low32 = (h) => Number(h & 0xffffffffn);

/** The Beast's entity hash (Death Mountain's key): poseidon(id, prefix, suffix). */
export const entityHash = (b) => poseidonHashMany([BigInt(b.id), BigInt(b.prefix), BigInt(b.suffix)]);

// ── event tracks ──────────────────────────────────────────────────────────────────────────────
export const KIND = { origin: 0, kill: 1, defeat: 2 };

/** track_id (u64): 0 = the origin track; else kind << 40 | event index << 8 | variation (0 free, 1+ $SKULL). */
export const encodeTrack = ({ kind, index = 0, variation = 0 }) => (kind === 0 ? 0n : (BigInt(kind) << 40n) | (BigInt(index) << 8n) | BigInt(variation));
export const decodeTrack = (id) => {
  const t = BigInt(id);
  return t === 0n ? { kind: 0, index: 0, variation: 0 } : { kind: Number(t >> 40n), index: Number((t >> 8n) & 0xffffffffn), variation: Number(t & 0xffn) };
};

/**
 * An event's seed. Records with Death Mountain's detail fields (a defeat's seed, which commits to the
 * adventurer's explore block hash, ID and XP; a kill's adventurer ID) hash those; records written
 * before the fields were filled (zeros) fall back to the Beast, the kind, the index and the timestamp.
 */
export function eventSeed(b, ev) {
  const detail = BigInt(ev.seed || 0) || BigInt(ev.adventurer_id || 0);
  return detail ? H('BEAST_EVENT', entityHash(b), ev.kind, detail, BigInt(ev.adventurer_xp || 0)) : H('BEAST_EVENT_OLD', entityHash(b), ev.kind, ev.index, BigInt(ev.timestamp || 0));
}

/**
 * The composer options for a track. Kills and defeats never drive the music directly: the composer
 * sees no history (no kills, no defeats; only the current rank, for the lead's prominence), and the
 * event picks the treatment. Kill: the inverted development, episodes rising, firmer accents.
 * Defeat: tighter stretto, episodes falling, softer and longer notes. The seed makes the free choices
 * (2-4 sections, rhythm cells, trills or passing notes, voice spacing, which side the key plan turns
 * to); a higher adventurer level adds a section.
 */
export function trackOptions(b, live, track, ev) {
  const neutral = { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: live.rank, species_count: live.species_count };
  if (track.kind === 0) return { live: neutral, opts: { ...V11 }, shape: null };
  const seed = H(eventSeed(b, ev), track.variation), s = low32(seed);
  const level = Number(ev.adventurer_level || 0);
  const sections = Math.min(5, 2 + (s % 3) + (level >= 20 ? 1 : 0));
  const kill = track.kind === 1;
  return {
    live: neutral,
    opts: {
      ...V11,
      override: {
        sections,
        rhythmSeed: seed,
        flipSide: ((s >>> 12) & 1) === 1,
        tr: { development: kill ? 'inversion' : 'stretto', direction: kill ? 1 : -1, trill: ((s >>> 4) & 1) === 1, spacing: ['wide', 'normal', 'close'][(s >>> 8) % 3] },
      },
    },
    shape: kill ? 'firm' : 'soft',
  };
}

const reshape = (r, shape) => {
  if (!shape) return r;
  const events = r.form.events.map((e) => (shape === 'firm'
    ? { ...e, velocity: Math.min(127, e.velocity + (e.time % 1920 === 0 ? 10 : 4)) }
    : { ...e, velocity: Math.max(1, e.velocity - 10), duration: e.duration }));
  return { ...r, form: { ...r.form, events } };
};

// ── progression: from the Beast's scale to the full composition ───────────────────────────────
export const LAYERS = ['theme', 'canon', 'countersubject', 'drums', 'palette'];

/**
 * The three-level progression in loothero's favourite order, THEME > CANON > PALETTE >
 * COUNTERSUBJECT > DRUMS, the same for every Beast: level 1 the theme, level 2 the canon and the
 * palette (the ensemble arrives), level 3 the countersubject and the drums (the groove lands last).
 */
export const PREFERRED_ORDER = ['theme', 'canon', 'palette', 'countersubject', 'drums'];
export const THREE_LEVELS = [['theme'], ['canon', 'palette'], ['countersubject', 'drums']];

/** The layers unlocked at `level`: three levels in the preferred order, or one layer per level in a seeded order. */
export function unlockedLayers(level, { three = true, seed = 0n } = {}) {
  return three ? THREE_LEVELS.slice(0, level).flat() : unlockOrder(seed).slice(0, level);
}

/** The order a Beast unlocks its layers: the theme first, the rest shuffled by the seed. */
export function unlockOrder(seed) {
  const rest = LAYERS.slice(1), out = ['theme'];
  let h = BigInt(seed);
  while (rest.length) { out.push(rest.splice(Number(h % BigInt(rest.length)), 1)[0]); h /= 7n; }
  return out;
}

/** Level 0: the Beast's own scale, up and down its mode from the home tonic, in its type's feel. */
function scaleResult(full, E) {
  const p = full.params, I = E.internals, mode = I.canonicalToMelodic(p.mode_id), tonic = I.transposedTonic(p.tonic_keynum, 0);
  const degrees = [0, 1, 2, 3, 4, 5, 6, 7, 7, 6, 5, 4, 3, 2, 1, 0];
  // feel by type: Magic flowing eighths, Hunter driving dotted pairs, Brute heavy quarters
  const feel = [[240, 240], [360, 120], [480, 480]][full.beast.beast_type] ?? [480, 480];
  const events = []; let t = 0;
  degrees.forEach((d, i) => {
    const dur = i === degrees.length - 1 ? 960 : feel[i % 2];
    events.push({ time: t, duration: dur, pitch: I.realize(d + 7, tonic, mode), velocity: (t % 1920 === 0 ? 100 : 86), voice_id: 0, role: 'scale' });
    t += dur;
  });
  const bars = Math.max(2, Math.ceil(t / 1920)), ticks = (bars % 2 ? bars + 1 : bars) * 1920;
  return { ...full, form: { ...full.form, events, section_ticks: ticks, sections: [{ start: 0 }] } };
}

/** The MIDI for a Beast with `unlocked` layers (0 = just its scale). */
export function progressionMidi(full, E, unlocked, seed, three = false) {
  if (unlocked === 0) {
    const r = scaleResult(full, E);
    return beastFullMidi(r, E.formLength, {}, { instruments: 'beast', drums: false });
  }
  const have = new Set(unlockedLayers(unlocked, { three, seed }));
  const p = full.params, cs = p.use_countersubject ? p.voice_count : -1;
  const keep = (v) => v === 0 || (v === cs ? have.has('countersubject') : have.has('canon'));
  const r = { ...full, form: { ...full.form, events: full.form.events.filter((e) => keep(e.voice_id)) } };
  const lead = beastInstruments(full)[0];
  const programs = have.has('palette') ? null : Object.fromEntries([...new Set(r.form.events.map((e) => e.voice_id))].map((v) => [v, lead]));
  return beastFullMidi(r, E.formLength, full.beast.shiny ? MEGA_ALL : {}, { instruments: 'beast', programs, drums: have.has('drums') ? null : false });
}

// ── drift: the never-ending track ─────────────────────────────────────────────────────────────
export const DRIFT_KNOBS = ['key plan turns the other way', 'episode directions swap', 'trills and passing notes swap', 'a neighbouring fill'];

/**
 * The drift for epoch `epoch` (onchain: one epoch per day of blocks, seeded by the epoch's first block
 * hash, readable once it is 10 blocks old). Each epoch turns at most one knob; one epoch in four turns
 * none, so the track is mostly itself.
 */
export function drift(b, epoch, anchor = null) {
  const s = low32(anchor === null ? H('BEAST_DRIFT', entityHash(b), epoch) : H('BEAST_DRIFT', entityHash(b), epoch, anchor(epoch)));
  const knob = s % 5; // 4 = no change
  return { knob: knob < 4 ? knob : null, label: knob < 4 ? DRIFT_KNOBS[knob] : 'as written' };
}

// ── block-hash epochs: nobody can hear a future day before its block exists ──────────────────────
// An epoch is a run of DRIFT_EPOCH_BLOCKS blocks; epoch e's seed mixes in the hash of its first block
// (e * DRIFT_EPOCH_BLOCKS), which does not exist until that block is made. Starknet's get_block_hash
// only reads blocks at least 10 behind the current one, so the epoch at block B is (B - 10) / N: an
// epoch starts 10 blocks after its first block, once that hash is readable. Days count from 1
// (day d = epoch d - 1). The three sound modes pick the block: live = the current block, original =
// the block the track was produced in, a specific block = any block up to the current one.
export const DRIFT_EPOCH_BLOCKS = 43200; // about a day at 2-second blocks; set from the chain's real block time
export const epochAtBlock = (block) => Math.max(0, Math.floor((block - 10) / DRIFT_EPOCH_BLOCKS));
export const epochFirstBlock = (epoch) => epoch * DRIFT_EPOCH_BLOCKS;
/** The lab's stand-in for get_block_hash (a fixed hash per block number); onchain this is the real block hash. */
export const labBlockHash = (block) => H('LAB_BLOCK_HASH', block);
/** Day d's anchor: the hash of its epoch's first block. */
export const dayAnchor = (blockHash = labBlockHash) => (day) => blockHash(epochFirstBlock(day - 1));

// ── layered drift (v2): every change audible, on three clocks, so a track evolves over years ──────
// The month (30 days) may re-pick the rhythm cells (2 months in 3; the first month plays as written);
// the week may rotate which channels play, keeping the count and the theme and low voice (3 weeks in 4;
// needs the full six channels); the day turns one more knob: the key plan the other way, the episode
// directions swapped, or the tempo nudged -4, -2, +2 or +4 BPM. Nothing accumulates: a day's version is
// a pure function of the track and the day number.
export const DRIFT2_DAY = ['key plan turns the other way', 'episode directions swap', 'tempo -4 BPM', 'tempo -2 BPM', 'tempo +2 BPM', 'tempo +4 BPM'];
// a Species Song's week from day 2 (genesis.cairo): the entries' spacing, the trill turned, the inner
// voices' fills (their share under the day's ceiling) and from day 360 graces on every voice
function songWeekExtras(rotate, day) {
  if (day < 2) return '';
  const h = Number(BigInt(rotate) & 0xffffffffn), fill = [0, 15, 30, 50][Math.floor(h / 524288) % ((day < 180 ? 0 : day < 360 ? 1 : day < 540 ? 2 : 3) + 1)];
  return ', entries ' + (1 + Math.floor(h / 65536) % 4) + ' beats apart' + (Math.floor(h / 262144) % 2 === 1 ? ', trill turned' : '') + (fill ? ', fills ' + fill + '%' : '') + (day >= 360 ? ', graces on every voice' : '');
}
export function drift2(b, day, anchor = null) {
  const k = entityHash(b), month = Math.floor((day - 1) / 30), week = Math.floor((day - 1) / 7);
  // with block hashes, each clock also mixes in the hash of its own first block (day d's epoch is d - 1)
  const hm = anchor ? [anchor(month * 30 + 1)] : [], hw = anchor ? [anchor(week * 7 + 1)] : [], hd = anchor ? [anchor(day)] : [];
  const m = low32(H('BEAST_DRIFT2_M', k, month, ...hm)), w = low32(H('BEAST_DRIFT2_W', k, week, ...hw)), dk = low32(H('BEAST_DRIFT2_D', k, day, ...hd)) % 6;
  const rhythm = month > 0 && m % 3 !== 0 ? H('BEAST_DRIFT2_RHYTHM', k, month, ...hm) : null;
  const rotate = w % 4 !== 0 ? H('BEAST_DRIFT2_ROT', k, week, ...hw) : null;
  const delta = [0, 0, -4, -2, 2, 4][dk];
  const inv = rhythm !== null && day >= 2 && Math.floor(Number(BigInt(rhythm) & 0xffffffffn) / 4096) % 2 === 1;
  const label = [rhythm !== null ? 'month ' + (month + 1) + ': new rhythm' + (inv ? ', inversion turned' : '') : 'month ' + (month + 1) + ': rhythm as written',
    rotate !== null ? 'week ' + (week + 1) + ': channels rotate, ornaments ' + Math.floor(Number(BigInt(rotate) & 0xffffffffn) / 128) % ((day < 180 ? 3 : day < 360 ? 5 : 7) + 1) + ' of 7' + songWeekExtras(rotate, day) : 'week ' + (week + 1) + ': channels as picked',
    'day: ' + DRIFT2_DAY[dk] + (dk >= 2 ? (dk >= 4 ? ', staccato' : ', tenuto') : '')].join(' \u00b7 ');
  return { v: 2, rhythm, rotate, dayKnob: dk, delta, label, day };
}

export function driftMidi(b, live, epoch, E, v11, anchor = null) {
  const d = drift(b, epoch, anchor), override = {};
  const base = v11.render(b, live, V11), tr = base.v11.trajectory;
  if (d.knob === 0) override.flipSide = true;
  if (d.knob === 1) override.tr = { direction: tr.direction === 0 ? 1 : -tr.direction };
  if (d.knob === 2) override.tr = { trill: !tr.trill };
  const r = d.knob === null || d.knob === 3 ? base : v11.render(b, live, { ...V11, override });
  const drums = d.knob === 3 ? (length, sec, tier, mega) => drumEvents(length, sec, tier >= 5 ? 4 : tier + 1, mega) : null;
  return { midi: beastFullMidi(r, E.formLength, b.shiny ? MEGA_ALL : {}, { instruments: 'beast', drums }), drift: d };
}

// ── specials: the Yeti (species 68) ───────────────────────────────────────────────────────────
export const YETI = 68;
/** The Yeti's tracks: the rock groove's tempo (175 BPM) and the avalanche's voice (past the six channels). */
export const YETI_ROCK_TEMPO_US = 342857;
export const YETI_AVALANCHE_VOICE = 6;
export const YETI_IDEAS = {
  rock: 'Rock groove: 175 BPM, kick on 1 and 3, snare backbeat, eighth hats, crash and tom fill at every section (the #301 groove)',
  yodel: 'Yodel: the lead leaps an octave on every other note of each beat pair, chest voice to head voice',
  avalanche: 'Avalanche: each section ends in a two-octave sixteenth-note arpeggio down through the closing chord on the Pulse 12.5% Pluck, landing on a crash',
  stomp: 'Stomp: three-quarter speed, a kick on every beat, the bass doubled an octave down',
  develop: 'Develop: the first bar is the motif; bar 2 repeats it a third higher, bar 3 turns it upside down and climbs to the high point, bar 4 steps down to the tonic (same rhythm)',
  thirtyseconds: '32nds: the ornaments in 32nd notes: snappier mordents and turns, faster trills (two flicks on a quarter, a longer trill on long notes), runs into the next note in 32nds',
  dark: 'Dark: the whole Yeti (every voice, ornaments, avalanche) in a darker mode on the same tonic and rhythm (Aeolian, harmonic minor, Locrian, or Phrygian kept), and the avalanche only ever runs down a minor chord, never one of the mode\'s major chords',
  varied: 'Varied: each Beast (species and name) gets its own ornament profile: where the figures go (evenly spaced, in bursts, on the long notes, on the strong beats, at bar ends, or thickening through the section) and a palette of three favourite figures out of mordent, upper mordent, turn, run, slide and trill, weighted 3:2:1',
  ornaments: 'Ornaments: sixteenth-note figures inside the melody notes (mordents, trill starts, turns, runs into the next note, trilled long notes); every note still starts on its beat, about one melody note in four, one in two for a Yeti with a busier ornament style',
};

// ── Yeti melody: more melodic variety in the first section, same note times and lengths ──────────
// Both work in scale degrees of the Beast's key, so every note stays in key; the rhythm (each note's
// time and length) is untouched, so the groove and the drums line up exactly as before.
const BAR = 1920;
function yetiScale(r, E) {
  const I = E.internals, mode = I.canonicalToMelodic(r.params.mode_id), home = I.transposedTonic(r.params.tonic_keynum, 0), sc = r.yetiScale;
  const pitch = sc ? (d) => home + 12 * Math.floor(d / 7) + sc[((d % 7) + 7) % 7] : (d) => I.realize(d, home, mode);
  const degree = (p) => { let best = 0; for (let d = -28; d <= 42; d++) if (Math.abs(pitch(d) - p) < Math.abs(pitch(best) - p)) best = d; return best; };
  return { pitch, degree };
}
/** A small deterministic hash of the Beast's name (so each Yeti gets its own choices). */
const nameHash = (b, salt) => { let h = (b.prefix * 131 + b.suffix * 31 + salt * 977 + 7) >>> 0; h ^= h << 13; h >>>= 0; h ^= h >>> 17; h ^= h << 5; return h >>> 0; };

/** Develop: motif, sequence a third up, inversion to the high point, cadence down to the tonic. */
function yetiDevelop(notes, sc) {
  const deg = notes.map((e) => sc.degree(e.pitch));
  const bars = [0, 1, 2, 3].map((k) => notes.map((e, i) => i).filter((i) => Math.floor(notes[i].time / BAR) === k));
  const motif = bars[0].map((i) => deg[i]);
  const steps = motif.slice(1).map((d, k) => d - motif[k]); // the motif's intervals in degrees
  const step = (k) => (steps.length ? steps[k % steps.length] : 1) || 1; // never a repeat
  const out = deg.slice();
  let last = motif[motif.length - 1];
  // bar 2: the motif a third (two degrees) above where bar 1 started
  bars[1].forEach((i, k) => { out[i] = k === 0 ? motif[0] + 2 : out[bars[1][k - 1]] + step(k - 1); });
  if (bars[1].length) last = out[bars[1][bars[1].length - 1]];
  // bar 3: the intervals upside down, widened, so it climbs to the section's high point
  bars[2].forEach((i, k) => {
    const prev = k === 0 ? last : out[bars[2][k - 1]];
    const inv = -step(k);
    out[i] = prev + (inv > 0 ? inv + (k % 2 === 0 ? 1 : 0) : k === 0 ? 2 : inv);
  });
  // bar 4: step down to the tonic (degree 0 in the register of the last high note), leading tone
  // before the last note when there are only two notes left
  const b4 = bars[3];
  if (b4.length) {
    const hi = Math.max(...bars[2].map((i) => out[i]), last);
    const tonic = Math.floor(hi / 7) * 7 - (hi % 7 < 3 ? 7 : 0);
    b4.forEach((i, k) => { const left = b4.length - 1 - k; out[i] = left === 0 ? tonic : left === 1 && b4.length <= 3 ? tonic - 1 : tonic + left; });
  }
  // no two equal notes in a row
  for (let i = 1; i < out.length; i++) if (out[i] === out[i - 1]) out[i] += i % 2 ? 1 : -1;
  return out.map((d) => sc.pitch(d));
}

/** A hash of the species and the name (nameHash alone is the same for every species' name 0). */
const beastHash = (b, salt) => nameHash({ prefix: b.prefix + b.id * 70, suffix: b.suffix + b.id * 19 }, salt);
export const ORNAMENT_PLACEMENTS = { even: 'evenly spaced' };
export const ORNAMENT_FIGURES = { mordent: 'mordent', upper: 'upper mordent', turn: 'turn', slide: 'slide', trill: 'trill' };
/** The figures as scale-degree offsets from the note (0 = the note itself), sixteenths each. */
const YETI_FIGURES = [[0, -1, 0], [0, 1, 0], [1, 0, -1, 0], [-2, -1, 0], [0, 1, 0, 1]];
/** A Beast's ornament profile: every `gap`-th long note from `phase`, and three neighbouring figures
 *  from `first` (weights 3, 2, 1). yeti.cairo `profile`. */
export function yetiOrnamentProfile(b) {
  const h = beastHash(b, 5), g = beastHash(b, 6), gap = 2 + ((h >>> 4) % 4), first = g % 5;
  const names = Object.keys(ORNAMENT_FIGURES);
  return { placement: 'even', gap, phase: (h >>> 8) % gap, first, figures: [0, 1, 2].map((k) => names[(first + k) % 5]) };
}

/** Ornaments: sixteenth-note figures inside the first section's melody notes. Each figure splits one
 *  note into sixteenths (120 ticks) that start on the note's own beat and add up to its length, so the
 *  beat and the groove are untouched. Neighbours are the scale's next degrees, so it stays in key. */
export function yetiOrnaments(events, r, b, E, fast = false, varied = false) {
  if (varied) return yetiOrnamentsVaried(events, r, b, E, fast);
  const sec = r.form.section_ticks, sc = yetiScale(r, E), S = fast ? 60 : 120; // a sixteenth or a 32nd
  const notes = events.filter((e) => e.voice_id === 0 && e.time < sec).sort((a, c) => a.time - c.time);
  if (notes.length < 2) return events;
  const h = nameHash(b, 2);
  const dens = r.params.ornament_density ?? 3; // the Yeti's own ornament style (from its name)
  const gaps = dens >= 4 ? [2, 3] : [4, 5]; // notes between ornaments, alternating: about one in four or five (two or three for busier styles)
  let made = 0;
  const repl = new Map();
  let since = 99;
  notes.forEach((e, i) => {
    since++;
    const next = notes[i + 1], last = i === notes.length - 1;
    if (e.duration < 480 || since < gaps[made % 2] || last) return;
    const d = sc.degree(e.pitch), up = sc.pitch(d + 1), down = sc.pitch(d - 1);
    const vel = Math.max(1, e.velocity - 12), seg = (pitch, len, v = vel) => ({ pitch, len, v });
    const k = (h >>> (i % 24)) % 5;
    let fig;
    const alt = (n) => Array.from({ length: n }, (_, j) => seg(j % 2 ? up : e.pitch, S, j ? vel : e.velocity)); // main, upper, main, ...
    // the rest of the note: the figure's last note held on when it is the note itself, else the note again
    const hold = (fig2) => {
      const used = fig2.reduce((x, f) => x + f.len, 0), rest = e.duration - used, lastF = fig2[fig2.length - 1];
      if (rest <= 0) return fig2;
      return lastF.pitch === e.pitch ? [...fig2.slice(0, -1), seg(e.pitch, lastF.len + rest, lastF.v)] : [...fig2, seg(e.pitch, rest)];
    };
    if (e.duration >= 960) {
      // a long note: trilled for its first beat (4 sixteenths or 8 32nds), then held
      fig = hold(alt(fast ? 8 : 4));
    } else if (next && Math.abs(sc.degree(next.pitch) - d) >= 2 && k < 3 && next.time === e.time + e.duration) {
      // a run into the next note: the note, then short notes stepping toward it
      const nd = sc.degree(next.pitch), dir = Math.sign(nd - d), gap = Math.abs(nd - d);
      const steps = Math.min(fast ? 4 : 3, gap - 1, Math.floor(e.duration / S) - 1);
      fig = [seg(e.pitch, e.duration - steps * S, e.velocity)];
      for (let s2 = 1; s2 <= steps; s2++) fig.push(seg(sc.pitch(d + dir * (gap - steps - 1 + s2)), S));
    } else if (k === 0 || k === 3) {
      fig = hold([seg(e.pitch, S, e.velocity), seg(down, S), seg(e.pitch, S)]); // mordent
    } else if (k === 1) {
      fig = hold(fast ? alt(5) : [seg(e.pitch, S, e.velocity), seg(up, S), seg(e.pitch, S)]); // trill start (two flicks in 32nds)
    } else {
      fig = hold([seg(e.pitch, S, e.velocity), seg(up, S), seg(down, S), seg(e.pitch, S)]); // turn, back on the note
    }
    let t = e.time;
    repl.set(e, fig.map((f) => { const n = { ...e, time: t, duration: f.len, pitch: Math.max(24, Math.min(108, f.pitch)), velocity: f.v }; t += f.len; return n; }));
    since = 0;
    made++;
  });
  return events.flatMap((e) => repl.get(e) ?? [e]);
}

/** Ornaments placed and chosen by the Beast's own profile (yetiOrnamentProfile): every `gap`-th
 *  note of a quarter or longer (not the last) from `phase`, one less apart when busy; the figure a
 *  3:2:1 pick of the profile's three, a trill on a note shorter than a half becoming an upper
 *  mordent. Every figure starts on the note's beat and adds up to its length, in the key's scale. */
function yetiOrnamentsVaried(events, r, b, E, fast) {
  const sec = r.form.section_ticks, sc = yetiScale(r, E), S = fast ? 60 : 120;
  const notes = events.filter((e) => e.voice_id === 0 && e.time < sec).sort((a, c) => a.time - c.time);
  if (notes.length < 2) return events;
  const P = yetiOrnamentProfile(b), busy = (r.params.ornament_density ?? 3) >= 4, h = beastHash(b, 7);
  const roll = (i, salt) => ((h ^ Math.imul(i + 1, 2654435761) ^ Math.imul(salt, 40503)) >>> 0) % 1000; // 0..999 (integers, so Cairo can match it)
  const elig = notes.map((_, i) => i).filter((i) => notes[i].duration >= 480 && i < notes.length - 1);
  const gap = busy && P.gap > 1 ? P.gap - 1 : P.gap, phase = P.phase % gap, pick = new Set();
  elig.forEach((i, k) => { if (k % gap === phase) pick.add(i); });
  if (!pick.size && elig.length) pick.add(elig[0]);
  const weighted = [0, 0, 0, 1, 1, 2].map((k) => (P.first + k) % 5); // 3:2:1
  const repl = new Map();
  notes.forEach((e, i) => {
    if (!pick.has(i)) return;
    let f = weighted[Math.floor((roll(i, 2) * 6) / 1000)];
    if (f === 4 && e.duration < 960) f = 1;
    const d = sc.degree(e.pitch), vel = Math.max(1, e.velocity - 12);
    const fig = YETI_FIGURES[f].map((o, j) => ({ pitch: o === 0 ? e.pitch : sc.pitch(d + o), len: S, v: j ? vel : e.velocity }));
    // the rest of the note: the figure's last note held on when it is the note itself, else the note again
    const used = fig.length * S, rest = e.duration - used, lastF = fig[fig.length - 1];
    if (rest > 0) { if (lastF.pitch === e.pitch) lastF.len += rest; else fig.push({ pitch: e.pitch, len: rest, v: vel }); }
    let t = e.time;
    repl.set(e, fig.map((x) => { const n = { ...e, time: t, duration: x.len, pitch: Math.max(24, Math.min(108, x.pitch)), velocity: x.v }; t += x.len; return n; }));
  });
  return events.flatMap((e) => repl.get(e) ?? [e]);
}

/** The first section's theme voice developed from its first bar (same times and lengths). */
export function yetiMelody(events, r, b, E, kind) {
  const sec = r.form.section_ticks, sc = yetiScale(r, E);
  const notes = events.filter((e) => e.voice_id === 0 && e.time < sec).sort((a, c) => a.time - c.time);
  if (notes.length < 3) return events;
  const pitches = yetiDevelop(notes, sc);
  const at = new Map(notes.map((e, i) => [e, Math.max(24, Math.min(108, pitches[i]))]));
  return events.map((e) => (at.has(e) ? { ...e, pitch: at.get(e) } : e));
}

/** A rock beat: kick 1 and 3 (and the and of 3), snare 2 and 4, eighth hats, crash per section, tom fill into the next. */
export function rockDrums(length, sec) {
  const out = [];
  for (let u = 0; u < length; u += 120) {
    const rel = u % sec, q = rel % 1920, fill = rel >= sec - 480;
    if (rel === 0) out.push([u, 49, 110]);
    if (fill) { if (u % 120 === 0) out.push([u, [50, 48, 47, 45][Math.floor((rel - (sec - 480)) / 120)] ?? 45, 96 + ((rel - (sec - 480)) / 120) * 6]); continue; }
    if (u % 240 !== 0) continue;
    if (q === 0 || q === 960 || q === 1200) out.push([u, 36, q === 1200 ? 96 : 120]);
    if (q === 480 || q === 1440) out.push([u, 38, 112]);
    out.push([u, 42, q % 480 === 0 ? 84 : 60]);
  }
  return out;
}

const stompDrums = (length, sec, tier, mega) => {
  const base = drumEvents(length, sec, tier, mega).filter(([, k]) => k !== 36);
  for (let u = 0; u < length; u += 480) base.push([u, 36, u % 1920 === 0 ? 124 : 104]);
  return base.sort((a, b) => a[0] - b[0]);
};

/** The Yeti's avalanche: the run down each section's closing chord on voice `ch` (see yetiMidi). */
export function yetiAvalanche(events, r, E, ch, darkId = null) {
  // the last half bar of each section: an arpeggio down two octaves in sixteenths through the chord
  // that is sounding there (the pitch classes of the other voices in that half bar), from the bass
  // note's pitch class two octaves above the home tonic's register down to it, so the run is in key and
  // on the chord, whatever the section closes on; a bare unison or fifth is filled out to the triad the
  // chord the key's scale gives it
  const top = r.params.tonic_keynum + 24; // two octaves down to the tonic's octave above the home register, around the melody
  const sec = r.form.section_ticks, sections = r.form.sections.length;
  events = events.slice();
  const ys = yetiScale(r, E);
  const scale = Array.from({ length: 7 }, (_, d) => ys.pitch(d) % 12);
  for (let s = 0; s < sections; s++) {
    const end = s * sec + sec, start = end - 960;
    const window = events.filter((e) => e.voice_id < ch && e.time < end && e.time + e.duration > start);
    if (!window.length) continue;
    // what sounds at the close (the last beat), falling back on the whole half bar
    const closing = window.filter((e) => e.time + e.duration > end - 480);
    const pcs = [...new Set((closing.length ? closing : window).map((e) => e.pitch % 12))], heard = [...new Set(window.map((e) => e.pitch % 12))];
    // the chord: the key's triad that holds the most of what is sounding, preferring a perfect fifth (no
    // diminished triad) and then the tonic, V, IV, VI, III, II, VII; a lone fifth in the bass reads as the
    // chord above it (Eb alone in Ab Phrygian is the tonic chord, Ab-Cb-Eb)
    const triad = (d) => [0, 2, 4].map((k) => scale[(d + k) % 7]);
    const perfect = (d) => ((triad(d)[2] - triad(d)[0] + 12) % 12) === 7;
    const pref = [0, 4, 3, 5, 2, 1, 6];
    const cover = (d, set) => set.filter((q) => triad(d).includes(q)).length;
    const minor = (d) => perfect(d) && ((triad(d)[1] - triad(d)[0] + 12) % 12) === 3;
    // the composer's rule (yeti.cairo): V at the end of the track, else I or IV, whichever holds more of
    // what sounds at the close (ties to I); the lab's dark variant scores every triad
    const inT = (d) => closing.map((e) => e.pitch % 12).filter((q) => triad(d).includes(q)).length;
    const best = darkId === null ? (s === sections - 1 ? 4 : inT(3) > inT(0) ? 3 : 0)
      : pref.filter((d) => d === 0 || minor(d)).slice().sort((a, c) => cover(c, pcs) - cover(a, pcs) || cover(c, heard) - cover(a, heard) || perfect(c) - perfect(a) || pref.indexOf(a) - pref.indexOf(c))[0];
    const root = scale[best], chord = triad(best); // the run uses the triad only, never a passing note
    let hi = top - (((top - root) % 12) + 12) % 12; // the highest pitch class of the root at or below top
    const run = [];
    for (let q = hi; q >= hi - 24; q--) if (chord.includes(q % 12)) run.push(q);
    const n = Math.min(run.length, 8), picked = run.length <= 8 ? run : run.filter((_, k) => k % Math.ceil(run.length / 8) === 0 || k === run.length - 1).slice(-8);
    if (picked[picked.length - 1] !== hi - 24) picked.push(hi - 24);
    const notes = picked.slice(-Math.min(picked.length, 8)), t0 = end - notes.length * 120;
    notes.forEach((q, i) => events.push({ time: t0 + i * 120, duration: 110, pitch: q, velocity: 112 - i * 4, voice_id: ch, role: 'avalanche' }));
  }
  return events;
}

/** Dark modes for the Yeti (canonical mode id -> its scale): Aeolian, harmonic minor, Locrian, Phrygian. */
export const YETI_DARK = { aeolian: 7, harmonic: 8, locrian: 6, phrygian: 5 };

export function yetiMidi(b, live, ideas, E, v11) {
  const override = ideas.rock ? { tempo_us: 342857 } : ideas.stomp ? { tempo_us: 666667 } : {};
  const darkId = ideas.dark ? YETI_DARK[ideas.dark] ?? YETI_DARK.aeolian : null;
  if (darkId !== null) { override.params = { mode_id: darkId }; override.scale = MODE_SCALES[darkId]; } // same tonic, every voice in the dark scale
  let r = v11.render(b, live, Object.keys(override).length ? { ...V11, override } : V11);
  if (darkId !== null) r = { ...r, yetiScale: MODE_SCALES[darkId] };
  let events = r.form.events.map((e) => ({ ...e }));
  const sec = r.form.section_ticks, sections = r.form.sections.length, maxV = Math.max(...events.map((e) => e.voice_id));
  const programs = {};
  let stompDouble = null;
  if (ideas.develop) events = yetiMelody(events, r, b, E, 'develop');
  const ornament = ideas.ornaments || ideas.thirtyseconds || ideas.varied;
  if (ideas.yodel) {
    // the theme voice: the second note of each beat pair jumps an octave up
    events = events.map((e) => (e.voice_id === 0 && Math.floor(e.time / 240) % 2 === 1 && e.pitch + 12 <= 108 ? { ...e, pitch: e.pitch + 12 } : e));
  }
  if (ornament) events = yetiOrnaments(events, r, b, E, !!ideas.thirtyseconds, !!ideas.varied);
  if (ideas.stomp) {
    // the lowest voice doubled an octave down on its own channel
    const means = {};
    for (const e of events) (means[e.voice_id] ||= []).push(e.pitch);
    const low = Object.keys(means).map(Number).sort((a, c) => means[a].reduce((x, y) => x + y, 0) / means[a].length - means[c].reduce((x, y) => x + y, 0) / means[c].length)[0];
    const ch = maxV + 1;
    events.filter((e) => e.voice_id === low && e.pitch - 12 >= 24).forEach((e) => events.push({ ...e, pitch: e.pitch - 12, velocity: Math.max(1, e.velocity - 6), voice_id: ch }));
    stompDouble = { ch, low }; // plays the low voice's own preset, an octave down
  }
  if (ideas.avalanche) {
    events = yetiAvalanche(events, r, E, maxV + 2, darkId);
    programs[maxV + 2] = 13; // Pulse 12.5% Pluck: a bright, icy run
  }
  events.sort((a, c) => a.voice_id - c.voice_id || a.time - c.time);
  // keep each voice monophonic and in time order (the writer's contract)
  r = { ...r, form: { ...r.form, events } };
  if (stompDouble) programs[stompDouble.ch] = beastInstruments(r)[stompDouble.low] ?? 16;
  const drums = ideas.rock ? (length, s2) => rockDrums(length, s2) : ideas.stomp ? stompDrums : null;
  return beastFullMidi(r, E.formLength, b.shiny ? MEGA_ALL : {}, { instruments: 'beast', programs, drums, notLead: ideas.avalanche ? [maxV + 2] : [] });
}

// ── owned tracks: the origin plus tracks bought with $CORPSE into slots opened with $SKULL ─────────
// loothero's model: every Beast plays its origin track out of the box; $SKULL raises how many tracks
// it can carry, $CORPSE buys a track into a free slot, seeded with fresh entropy (onchain: a block
// hash at least 10 blocks old, the token and the purchase index). Kills and defeats never touch the
// music: they earn the tokens. The provider only reads the selected track's seed.
export const TIER_SECTIONS = { 1: 4, 2: 4, 3: 3, 4: 2, 5: 2 };
export const TIER_VOICES = { 1: 4, 2: 4, 3: 3, 4: 2, 5: 2 };
const DEVELOPMENTS = ['inversion', 'stretto', 'sequence'];

/** What a track does: null for the origin, else the treatment its seed picks. */
export function trackTreatment(seed) {
  if (seed === null || seed === undefined) return null;
  const s = low32(H('BEAST_TRACK', seed)), t = low32(H('BEAST_TRACK_2', seed));
  return {
    development: DEVELOPMENTS[s % 3],
    direction: [1, -1, 0][(s >>> 2) % 3],
    sections: 2 + ((s >>> 4) % 3),
    trill: ((s >>> 6) & 1) === 1,
    spacing: ['wide', 'normal', 'close'][(s >>> 7) % 3],
    flipSide: ((s >>> 9) & 1) === 1,
    rhythmSeed: BigInt(t) * 0x10000000n + BigInt(s),
  };
}

/** The MIDI of the selected track (seed null = the origin), with the drift of `epoch` (null = none). */
export function ownedTrackMidi(b, live, seed, epoch, E, v11) {
  return trackMidi(b, live, seed, epoch, E, v11, false);
}

// ── species tracks with a per-Beast auction (loothero, 6 Oct) ──────────────────────────────────────
// Every Beast of a species starts with the same base track: the composition sees only the species
// (a canonical name, level and health per species; no kills, defeats, rank, shiny or animated), so all
// Warlocks play the same notes at the same tempo. Shiny keeps the mega layer as a sound on top.
// Each Beast then has one track on offer at a time, sold by a gradual Dutch auction; a purchase needs a
// free slot ($SKULL raises capacity), and the next offer is seeded from the purchase block's hash
// (readable 10 blocks later), the token and the purchase index. A bought track keeps the species theme
// and instruments; its seed picks a key and mode (the prefix table) and an ornament style (the suffix
// table), which used to come from the Beast's name, plus the development, episode direction, sections,
// spacing, side and rhythm.
export const BASE_LEVEL = 50, BASE_HEALTH = 200;
export function speciesBeast(b) {
  return { ...b, prefix: ((b.id - 1) % 69) + 1, suffix: ((b.id - 1) % 18) + 1, level: BASE_LEVEL, health: BASE_HEALTH, shiny: 0, animated: 0 };
}
/** A bought track's choices: the treatment plus the key and ornament style taken from the name tables. */
export function speciesTrackTreatment(seed) {
  const t = trackTreatment(seed);
  if (!t) return null;
  const k = low32(H('BEAST_TRACK_KEY', seed));
  return { ...t, prefix: 1 + (k % 69), suffix: 1 + ((k >>> 8) % 18) };
}
/** The chosen Genesis themes (the user's picks, 7 Oct; later picks 8 Oct): species id -> theme candidate; absent = 0, its own. */
export const GENESIS_THEMES = { 2: 3, 3: 5, 4: 1, 7: 5, 8: 419, 9: 1, 11: 6, 13: 1176, 14: 1, 15: 7, 17: 4, 19: 837, 20: 452, 21: 511, 22: 1174, 23: 353, 25: 908, 26: 2, 27: 195, 28: 61, 29: 967, 30: 597, 31: 598, 32: 914, 33: 976, 34: 204, 35: 797, 36: 74, 38: 911, 39: 210, 41: 808, 42: 575, 43: 7, 44: 582, 45: 847, 46: 1018, 48: 1087, 49: 986, 51: 6, 52: 1115, 53: 496, 54: 196, 55: 1075, 56: 1146, 57: 1180, 58: 559, 59: 1119, 60: 208, 61: 677, 62: 165, 63: 696, 64: 16, 65: 931, 66: 799, 67: 136, 68: 941, 69: 650, 70: 5, 71: 2, 72: 135, 73: 1156, 74: 965, 75: 1040 };
/** Default music swaps: species id -> the species whose Genesis Track it plays (two-way pairs). Harpy (39) <-> Pegasus (40). */
export const GENESIS_SWAPS = { 39: 40, 40: 39 };
/** Genesis mode overrides on the spread key (same tonic): species id -> mode id. Nue (33) is Phrygian. */
export const GENESIS_MODES = { 33: 5 };
/** Each mode's scale as semitone offsets from the tonic, as named. */
export const MODE_SCALES = { 4: [0, 2, 3, 5, 7, 9, 10], 5: [0, 1, 3, 5, 7, 8, 10], 6: [0, 1, 3, 5, 6, 8, 10], 7: [0, 2, 3, 5, 7, 8, 10], 8: [0, 2, 3, 5, 7, 8, 11], 26: [0, 2, 3, 6, 7, 9, 10] };
const MODE_NAMES = { 4: 'Dorian', 5: 'Phrygian', 6: 'Locrian', 7: 'Aeolian', 8: 'harmonic minor', 26: 'Dorian #4' };
const PC = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
export const keyName = (p) => PC[p.tonic_keynum % 12] + ' ' + (MODE_NAMES[p.mode_id] || 'mode ' + p.mode_id);

export function speciesTrackMidi(b, live, seed, epoch, E, v11) {
  return trackMidi(b, live, seed, epoch, E, v11, true);
}

function trackMidi(b, live, seed, epoch, E, v11, species) {
  const neutral = { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: live.species_count };
  const t = species ? speciesTrackTreatment(seed) : trackTreatment(seed);
  const cb = species ? speciesBeast(b) : b;
  const override = { voice_count: TIER_VOICES[b.tier] ?? 2, sections: t ? t.sections : TIER_SECTIONS[b.tier] ?? 2 };
  if (t) Object.assign(override, { rhythmSeed: t.rhythmSeed, flipSide: t.flipSide, tr: { development: t.development, direction: t.direction, trill: t.trill, spacing: t.spacing } });
  if (t && species) {
    // the key and ornament style a Beast with that name would have, on the species' theme
    const kp = E.mapV3({ ...cb, prefix: t.prefix, suffix: t.suffix }, neutral);
    override.params = { mode_id: kp.mode_id, tonic_keynum: kp.tonic_keynum, register_band: kp.register_band, ornament_density: kp.ornament_density, _ornament: kp._ornament };
    override.tr.trill = !!kp._ornament.allow_trill;
  }
  const shown = t && species ? { ...t, trill: override.tr.trill } : t;
  const d = epoch === null || epoch === undefined ? { knob: null, label: 'off' } : drift(b, epoch);
  const base = v11.render(cb, neutral, { ...V11, override });
  const tr = base.v11.trajectory;
  if (d.knob === 0) override.flipSide = !override.flipSide;
  if (d.knob === 1) override.tr = { ...(override.tr || {}), direction: tr.direction === 0 ? 1 : -tr.direction };
  if (d.knob === 2) override.tr = { ...(override.tr || {}), trill: !tr.trill };
  const r = d.knob === null || d.knob === 3 ? base : v11.render(cb, neutral, { ...V11, override });
  const drums = d.knob === 3 ? (length, sec, tier, mega) => drumEvents(length, sec, tier >= 5 ? 4 : tier + 1, mega) : null;
  const key = override.params ? keyName({ ...r.params, ...override.params }) : keyName(r.params);
  return { midi: beastFullMidi(r, E.formLength, b.shiny ? MEGA_ALL : {}, { instruments: 'beast', drums }), drift: d, result: r, key, treatment: shown };
}

// ── the sampler (loothero, 6 Oct): a Beast (species), a special name 0-1242 and a seed (a block hash) ──
// Name 0 with seed 0 is the species' Genesis Track, the base every Beast of the species starts with. Names 1-1242
// are the 69 x 18 prefix/suffix pairs (name variant id = 1 + (prefix - 1) * 18 + (suffix - 1)): a name
// sets the key, mode and register (prefix) and the ornament style (suffix), as it does for a named Beast
// in v1.1. The seed sets the treatment: development, episode direction, sections, spacing, which side the
// theme sits and the rhythm cells. With theme 'species' every track keeps the species' motif (the
// Genesis Track's theme); with 'name' the name also re-seeds the motif, as v1.1 does today.
// genesisKey 'rule' is v1.1's genesis key (every species Phrygian, tonic = id mod 12); 'spread' gives
// each species the key of a canonical name instead; 'proposed' adds genesisTempo (the Genesis Track
// table's starting point), for comparing while the 75 Genesis Tracks are tuned.
export const NAME_COUNT = 69 * 18;
/** A special name's variant id (0 = none): 1 + (prefix - 1) * 18 + (suffix - 1). */
export const nameVariant = (prefix, suffix) => (prefix === 0 ? 0 : 1 + (prefix - 1) * 18 + (suffix - 1));
export const nameFromVariant = (n) => (n === 0 ? { prefix: 0, suffix: 0 } : { prefix: Math.floor((n - 1) / 18) + 1, suffix: ((n - 1) % 18) + 1 });
export const genesisBeast = (b) => ({ ...b, prefix: 0, suffix: 0, level: BASE_LEVEL, health: BASE_HEALTH, shiny: 0, animated: 0 });

/** A starting tempo for a species' Genesis Track (v1.1 plays every one at 120 BPM): Hunters quick,
 *  Magic moderate, Brutes heavy; big tiers slower, small tiers quicker; a step by species to separate
 *  neighbours. A suggestion to tune by ear in the Genesis Track table. */
export function genesisTempo(b) {
  return [104, 124, 92][b.beast_type] + [-8, -4, 0, 4, 8][b.tier - 1] + [-4, 0, 4][b.id % 3];
}
/** The spread key: a canonical name's key per species (prefix (id - 1) mod 69 + 1). */
export const spreadKeyBeast = (g) => ({ ...g, prefix: ((g.id - 1) % 69) + 1, suffix: ((g.id - 1) % 18) + 1 });

// ── channel rarity (loothero, 6 Oct): the same presets, a filter on which channels play ──────────
// Every track is composed with the full six channels (four canon voices, the countersubject, drums);
// the seed decides how many play: most tracks 3-5, a rare one all 6. The theme voice and the lowest
// canon voice (the foundation) always play; the seed picks the rest. A Genesis Track (no seed) plays a
// fixed count by tier, so 6 only ever comes from a bought track. Muting never adds a clash (the voices
// that remain are the ones composed together); the mega double, when shiny, rides on the lead.
export const CHANNEL_ODDS = [[3, 30], [4, 40], [5, 26], [6, 4]]; // percent: 6 channels is 1 track in 25
export const GENESIS_CHANNELS = { 1: 5, 2: 5, 3: 4, 4: 3, 5: 3 };
export const CHANNEL_NAMES = { 0: 'theme', 1: 'voice 2', 2: 'voice 3', 3: 'voice 4', 4: 'countersubject', drums: 'drums' };
export function channelCount(seed, tier) {
  if (seed === null || seed === undefined) return GENESIS_CHANNELS[tier] ?? 3;
  let roll = Number(H('BEAST_CHANNELS', seed) % 100n);
  for (const [count, pct] of CHANNEL_ODDS) { if (roll < pct) return count; roll -= pct; }
  return 3;
}
/** Which channels play: the theme (voice 0), the lowest canon voice, then a seeded order of the rest. */
export function channelPick(events, count, seed) {
  const st = {};
  for (const e of events) if (e.voice_id <= 3) { const s = (st[e.voice_id] ||= { sum: 0, n: 0 }); s.sum += e.pitch; s.n++; }
  const canon = Object.keys(st).map(Number), low = canon.reduce((a, b) => (st[b].sum / st[b].n < st[a].sum / st[a].n ? b : a));
  const rest = [...canon.filter((v) => v !== 0 && v !== low), 4, 'drums'];
  if (seed === null || seed === undefined) rest.sort((a, b) => ['drums', 4, 1, 2, 3].indexOf(a) - ['drums', 4, 1, 2, 3].indexOf(b)); // Genesis: drums, then the countersubject
  else for (let i = rest.length - 1, h = H('BEAST_CHANNEL_ORDER', seed); i > 0; i--, h /= 7n) { const j = Number(h % BigInt(i + 1)); [rest[i], rest[j]] = [rest[j], rest[i]]; }
  return [...new Set([0, low])].concat(rest).slice(0, count);
}

// ── ties: repeated notes in the inner voices held instead of struck again ──────────────────────────
// Only when 3 or more pitched voices play, and only on inner voices: never the bass (lowest mean pitch),
// the topline (highest) or the theme (its rhythm is the motif). One pass per voice: a note that repeats the pitch of the one
// before it, starting where it ends and in the same section, extends it instead, up to a bar per tied
// note. Mode 'weak' ties only a repeat that would strike off the strong beats (1 and 3), so the pulse is
// still re-struck; 'all' ties every repeat. Cheap (linear in the notes) and the same rule ports to Cairo as
// a merge while writing the voice.
export const TIE_MAX = 1920;
export function tieRepeats(form, mode = 'weak') {
  const keep = [], last = {}, st = {};
  let tied = 0;
  for (const e of form.events) { const x = (st[e.voice_id] ||= { sum: 0, n: 0 }); x.sum += e.pitch; x.n++; }
  const vs = Object.keys(st).map(Number), avg = (v) => st[v].sum / st[v].n;
  if (vs.length < 3) return { form, tied: 0, voices: [] };
  const bass = vs.reduce((a, b) => (avg(b) < avg(a) ? b : a)), top = vs.reduce((a, b) => (avg(b) > avg(a) ? b : a));
  const inner = new Set(vs.filter((v) => v !== 0 && v !== bass && v !== top));
  for (const e of [...form.events].sort((a, b) => a.voice_id - b.voice_id || a.time - b.time)) {
    const prev = last[e.voice_id];
    if (inner.has(e.voice_id) && prev && prev.pitch === e.pitch && prev.time + prev.duration === e.time && prev.section === e.section
      && Math.floor(prev.time / form.section_ticks) === Math.floor(e.time / form.section_ticks) && prev.duration + e.duration <= TIE_MAX && (mode === 'all' || e.time % 960 !== 0)) {
      prev.duration += e.duration; tied++; continue;
    }
    const c = { ...e }; keep.push(c); last[e.voice_id] = c;
  }
  keep.sort((a, b) => a.time - b.time || a.voice_id - b.voice_id);
  return { form: { ...form, events: keep }, tied, voices: [...inner] };
}

// ── flourishes that grow with age: the one layer that accumulates ─────────────────────────────────
// Every playing voice gains ornaments in 16ths as the Beast ages: the share of a voice's eligible notes
// that carry one rises from 0 toward FLOURISH_CAP on the theme and FLOURISH_CAP_OTHERS on the other voices
// (about two-thirds of it by the first year), with one flourish per beat across the whole texture so they
// trade off between voices; the lowest voice takes no trills or turns (they muddy a bass line). Each note has a
// fixed hash threshold and shape, so a note keeps its flourish once it has one (while the composition is
// the same). Eligible: theme notes a quarter or longer running straight into the next one; one per beat;
// none in a section's last (cadence) bar; no added note a minor second or major seventh against another
// voice. The shapes sit in different places in the note, so they do not all sound like pickups:
//   trill        at the start: main, upper, main, upper in 16ths, then the note (any note)
//   mordent      at the start: main, lower, main, then the note (any note)
//   turn         the note's last beat as upper, main, lower, main into the next note (a step or a third ahead)
//   suspension   the note held an eighth into the next beat, then resolving down by step (a step down ahead)
//   passing      the last 16th fills a third ahead with the step between
//   anticipation the last 16th arrives early on the next pitch (a step ahead; now the rarest)
// The track's ornament style (the name's suffix, as in v1.1) doubles the weight of trills or suspensions.
export const FLOURISH_CAP = 0.08, FLOURISH_CAP_OTHERS = 0.04, FLOURISH_YEAR = 365;
export const flourishShare = (day, cap = FLOURISH_CAP) => (day > 0 ? cap * (1 - Math.exp(-day / FLOURISH_YEAR)) : 0);
export const FLOURISH_SHAPES = ['trill', 'mordent', 'turn', 'suspension', 'passing', 'anticipation'];
export function addFlourishes(form, day, key, style = {}) {
  const share = flourishShare(day), S = 120, BEAT = 480, BAR = 1920;
  const ev = form.events.map((e) => ({ ...e }));
  const byVoice = {};
  for (const e of ev) (byVoice[e.voice_id] ||= []).push(e);
  for (const v of Object.keys(byVoice)) byVoice[v].sort((a, b) => a.time - b.time);
  const mean = (v) => byVoice[v].reduce((a, e) => a + e.pitch, 0) / byVoice[v].length;
  const lowest = Object.keys(byVoice).map(Number).reduce((a, b) => (mean(b) < mean(a) ? b : a));
  const cnt = Array(12).fill(0);
  for (const e of ev) cnt[e.pitch % 12]++;
  const pcs = new Set(cnt.map((c, i) => [c, i]).filter(([c]) => c > 0).sort((a, b) => b[0] - a[0]).slice(0, 7).map(([, i]) => i));
  const inScale = (q) => pcs.has(((q % 12) + 12) % 12);
  const step = (q, dir) => { for (let x = q + dir; Math.abs(x - q) <= 2; x += dir) if (inScale(x)) return x; return null; };
  // a brief rub is what ornaments do; only a minor second or a major seventh against another voice is out
  const harsh = (a, b) => [1, 11].includes(((a - b) % 12 + 12) % 12);
  const against = (self, t, dur, q, bad) => !ev.some((o) => o.voice_id !== self && o.time < t + dur && o.time + o.duration > t && bad(o.pitch, q));
  // the neighbour notes of a trill, mordent or turn rub for longer, so they also avoid the tritone
  const soft = (a, b) => [1, 6, 11].includes(((a - b) % 12 + 12) % 12);
  const beats = new Set(), added = [], touched = new Set();
  // notes in the order they unlock (lowest threshold first) across all voices, so a flourish that appeared
  // earlier keeps its place and later ones only take what is still free: the set only grows with age
  const order = [];
  for (const [v, list] of Object.entries(byVoice)) {
    const cap = +v === 0 ? FLOURISH_CAP : FLOURISH_CAP_OTHERS, vs = flourishShare(day, cap);
    // th / cap: when this note unlocks on the shared age curve, comparable across voices with different caps
    list.slice(0, -1).forEach((e, i) => { const h = H('BEAST_FLOURISH', key, +v, i), th = Number(h % 10000n) / 10000; if (th < vs) order.push({ v: +v, i, h, th: th / cap, orig: { time: e.time, duration: e.duration } }); });
  }
  order.sort((a, b) => a.th - b.th || a.v - b.v || a.i - b.i);
  for (const { v, i, h, orig } of order) {
    const list = byVoice[v], e = list[i], nx = list[i + 1], low = v === lowest && Object.keys(byVoice).length > 1;
    const W = { trill: low ? 0 : style.allow_trill ? 4 : 2, mordent: 2, turn: low ? 0 : 4, suspension: style.allow_suspension ? 6 : 3, passing: 2, anticipation: 1 };
    if (e.role === 'flourish' || touched.has(e) || touched.has(nx) || e.time !== orig.time || e.duration !== orig.duration || orig.duration < BEAT || nx.time !== orig.time + orig.duration) continue;
    if (e.time % form.section_ticks >= form.section_ticks - BAR || nx.time % form.section_ticks >= form.section_ticks - BAR) continue;
    const clear = (t, dur, q) => against(v, t, dur, q, harsh), calm = (t, dur, q) => against(v, t, dur, q, soft);
    const iv = nx.pitch - e.pitch, up = step(e.pitch, 1), down = step(e.pitch, -1);
    const ok = {
      trill: up !== null, mordent: down !== null,
      turn: up !== null && down !== null && Math.abs(iv) >= 1 && Math.abs(iv) <= 4,
      suspension: (iv === -1 || iv === -2) && nx.duration >= BEAT,
      passing: Math.abs(iv) === 3 || Math.abs(iv) === 4,
      anticipation: Math.abs(iv) === 1 || Math.abs(iv) === 2,
    };
    const cands = FLOURISH_SHAPES.filter((x) => ok[x] && W[x] > 0);
    if (!cands.length) continue;
    let roll = Number((h / 10000n) % 1000n) % cands.reduce((a, x) => a + W[x], 0), shape = cands[0];
    for (const x of cands) { if (roll < W[x]) { shape = x; break; } roll -= W[x]; }
    // the 16ths to add: [time, pitch] pairs replacing the start or end of e (or delaying nx)
    let notes = [], cutStart = 0, cutEnd = 0;
    if (shape === 'trill') { notes = [[e.time, e.pitch], [e.time + S, up], [e.time + 2 * S, e.pitch], [e.time + 3 * S, up]]; cutStart = 4 * S; }
    else if (shape === 'mordent') { notes = [[e.time, e.pitch], [e.time + S, down], [e.time + 2 * S, e.pitch]]; cutStart = 3 * S; }
    else if (shape === 'turn') { const t0 = e.time + e.duration - BEAT; notes = [[t0, up], [t0 + S, e.pitch], [t0 + 2 * S, down], [t0 + 3 * S, e.pitch]]; cutEnd = BEAT; }
    else if (shape === 'passing') { const q = step(e.pitch, Math.sign(iv)); if (q === null || (q - e.pitch) * (nx.pitch - q) <= 0) continue; notes = [[e.time + e.duration - S, q]]; cutEnd = S; }
    else if (shape === 'anticipation') { notes = [[e.time + e.duration - S, nx.pitch]]; cutEnd = S; }
    const span = shape === 'suspension' ? [nx.time, nx.time + 2 * S] : [Math.min(...notes.map((n) => n[0])), Math.max(...notes.map((n) => n[0])) + S];
    const bs = []; for (let t = span[0]; t < span[1]; t += BEAT / 2) bs.push(Math.floor(t / BEAT));
    if (bs.some((x) => beats.has(x))) continue;
    if (shape === 'suspension') {
      if (!clear(nx.time, 2 * S, e.pitch)) continue;
      e.duration += 2 * S; nx.time += 2 * S; nx.duration -= 2 * S; touched.add(nx);
      added.push({ voice: v, time: e.time, pitch: e.pitch, shape, at: nx.time - 2 * S });
    } else {
      if (!notes.every(([t, q]) => (q === e.pitch ? true : ['trill', 'mordent', 'turn'].includes(shape) ? calm(t, S, q) : clear(t, S, q)))) continue;
      if (cutStart) { e.time += cutStart; e.duration -= cutStart; }
      if (cutEnd) e.duration -= cutEnd;
      notes.forEach(([t, q], k) => ev.push({ ...e, time: t, duration: S, pitch: q, velocity: Math.max(1, (cutStart ? e.velocity : e.velocity - 10) - (k ? 8 : 0)), role: 'flourish' }));
      added.push({ voice: v, time: notes[0][0], pitch: notes[0][1], shape, notes });
    }
    bs.forEach((x) => beats.add(x)); touched.add(e);
  }
  ev.sort((a, b) => a.time - b.time || a.voice_id - b.voice_id);
  return { form: { ...form, events: ev.filter((x) => x.duration > 0) }, added, share };
}

export function sampleTrackMidi(b, live, { name = 0, seed = null, theme = 'species', genesisKey = 'rule', epoch = null, channels = 'tier', bpm = null, driftMode = 'v1', mix = null, flourishDay = null, ties = false, topLead = false, motif = 0, trueV = false, blockHashes = false, yeti = true, echo = false } = {}, E, v11) {
  // seed 0 is the Genesis seed (0 is never a block hash): the Genesis rules, no seeded treatment, the
  // tier's fixed channel count, so the OG track of a species (name 0, seed 0) is known exactly
  if (seed === 0n || seed === 0) seed = null;
  const neutral = { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: live.species_count || 1 };
  const g = genesisBeast(b), nm = nameFromVariant(name);
  const t = seed === null || seed === undefined ? null : trackTreatment(seed);
  // motif: theme candidate N, the motif (pitches and rhythm) that special name N would compose, on the
  // track's own key, ornament style and instruments; 0 = the species' own theme. The species' picked
  // theme plays on its Genesis Track and on every track of the species (name tracks and bought tracks
  // keep the species' theme), so all of a species' tracks share it
  if (motif === 'default') motif = GENESIS_THEMES[b.id] || 0;
  const cand = (!name || theme === 'species') && motif > 0 ? nameFromVariant(Math.min(NAME_COUNT, motif)) : null;
  const cb = cand ? { ...g, ...cand } : name && theme === 'name' ? { ...g, ...nm } : g; // the Beast the composer sees (theme, register)
  // channels 'tier': v1.1's voices for the tier; 'rarity' or a forced count 3-6: the full six, filtered
  const full = channels !== 'tier';
  const override = { voice_count: full ? 4 : TIER_VOICES[b.tier] ?? 2, sections: t ? t.sections : TIER_SECTIONS[b.tier] ?? 2, tr: {} };
  if (t) Object.assign(override, { rhythmSeed: t.rhythmSeed, flipSide: t.flipSide, tr: { development: t.development, direction: t.direction, spacing: t.spacing } });
  let orn = E.mapV3(cb, neutral)._ornament;
  if (cand) { // everything but the theme stays the Genesis Track's (key, ornament style, instruments, countersubject seed)
    const kg = E.mapV3(g, neutral);
    override.params = { mode_id: kg.mode_id, tonic_keynum: kg.tonic_keynum, register_band: kg.register_band, ornament_density: kg.ornament_density, _ornament: kg._ornament, name_variant_id: 0 };
    orn = kg._ornament;
  }
  if (name && theme === 'species') { // the name's key and ornament style on the species' theme
    const kp = E.mapV3({ ...g, ...nm }, neutral);
    override.params = { mode_id: kp.mode_id, tonic_keynum: kp.tonic_keynum, register_band: kp.register_band, ornament_density: kp.ornament_density, _ornament: kp._ornament, name_variant_id: 0 };
    if (MODE_SCALES[kp.mode_id]) override.scale = MODE_SCALES[kp.mode_id]; // the mode as named, as on the Genesis spread keys
    orn = kp._ornament;
  } else if (!name && (genesisKey === 'spread' || genesisKey === 'proposed')) {
    const kp = E.mapV3(spreadKeyBeast(g), neutral);
    if (GENESIS_MODES[b.id] !== undefined) kp.mode_id = GENESIS_MODES[b.id]; // a chosen mode, same tonic
    override.params = { ...(override.params || {}), mode_id: kp.mode_id, tonic_keynum: kp.tonic_keynum, register_band: kp.register_band };
    // the mode as named: the engine realizes only Aeolian, Dorian and Phrygian (Locrian plays as Phrygian,
    // harmonic minor as Aeolian, Dorian #4 as Dorian), so the Genesis spread passes the real scale
    if (MODE_SCALES[kp.mode_id]) override.scale = MODE_SCALES[kp.mode_id];
  }
  if (!name && genesisKey === 'proposed') override.tempo_us = Math.round(60e6 / genesisTempo(b));
  if (bpm) override.tempo_us = Math.round(60e6 / bpm); // the page's tempo control
  if (trueV) override.trueDominant = true; // section ends close on a real (major) V
  const yetiOn = yeti && b.id === YETI; // the Yeti special on every Yeti track (see below)
  if (yetiOn && !bpm) override.tempo_us = YETI_ROCK_TEMPO_US;
  override.tr.trill = !!orn.allow_trill;
  if (full) override.params = { ...(override.params || {}), use_countersubject: true };
  const off = epoch === null || epoch === undefined;
  const anchor = blockHashes ? dayAnchor() : null;
  const ent = name ? { ...b, ...nm } : b; // drift belongs to the Beast: its species and special name
  const d = off ? { knob: null, label: 'off' } : driftMode === 'v2' ? drift2(ent, epoch, anchor) : drift(ent, epoch, anchor);
  if (d.v === 2 && d.rhythm !== null) override.rhythmSeed = d.rhythm;
  const base = v11.render(cb, neutral, { ...V11, override });
  const tr = base.v11.trajectory;
  let again = d.knob === 0 || d.knob === 1 || d.knob === 2;
  if (d.knob === 0) override.flipSide = !override.flipSide;
  if (d.knob === 1) override.tr = { ...override.tr, direction: tr.direction === 0 ? 1 : -tr.direction };
  if (d.knob === 2) override.tr = { ...override.tr, trill: !tr.trill };
  if (d.v === 2) {
    again = true;
    // from the second day: a month may turn the inversion, a week sets the entries' spacing and may
    // turn the trill (genesis.cairo drifted_song_inputs)
    if (d.day >= 2 && d.rhythm !== null && Math.floor(Number(BigInt(d.rhythm) & 0xffffffffn) / 4096) % 2 === 1) {
      const inv = (override.params && override.params.use_inversion) ?? base.params.use_inversion;
      override.params = { ...(override.params || {}), use_inversion: !inv };
    }
    if (d.day >= 2 && d.rotate !== null) {
      const h = Number(BigInt(d.rotate) & 0xffffffffn);
      override.params = { ...(override.params || {}), stretto_lag: 1 + Math.floor(h / 65536) % 4 };
      if (Math.floor(h / 262144) % 2 === 1) override.tr = { ...override.tr, trill: !override.tr.trill };
    }
    // a new-rhythm month: two months in three the key moves to the dominant or subdominant (an octave
    // down above 96; genesis.cairo drift_key)
    if (d.rhythm !== null) {
      const km = Math.floor(Number(BigInt(d.rhythm) & 0xffffffffn) / 256) % 3;
      if (km < 2) {
        const T0 = (override.params && override.params.tonic_keynum) ?? base.params.tonic_keynum, k = T0 + [7, 5][km];
        override.params = { ...(override.params || {}), tonic_keynum: k > 96 ? k - 12 : k };
      }
    }
    if (d.dayKnob === 0) override.flipSide = !override.flipSide;
    else if (d.dayKnob === 1) override.tr = { ...override.tr, direction: tr.direction === 0 ? 1 : -tr.direction };
    else { // the tempo nudged by delta BPM: 60e6 / (60e6 / T + delta), rounded half up, in integers (as Cairo)
      const T = override.tempo_us || base.params.tempo_us, D = 60e6 + d.delta * T;
      override.tempo_us = Math.floor((2 * 60e6 * T + D) / (2 * D));
      // and the phrasing: staccato when faster, tenuto when slower
      override.params = { ...(override.params || {}), articulation_profile: d.delta > 0 ? 1 : 2 };
    }
    // a drift week draws the ornament density under a ceiling rising with the day: 0-3 to day 180,
    // 0-5 to day 360, then 0-7 (genesis.cairo drift_ornaments)
    if (d.rotate !== null) {
      const h = Number(BigInt(d.rotate) & 0xffffffffn), ceiling = d.day < 180 ? 3 : d.day < 360 ? 5 : 7;
      override.params = { ...(override.params || {}), ornament_density: Math.floor(h / 128) % (ceiling + 1) };
    }
  }
  const r = again ? v11.render(cb, neutral, { ...V11, override }) : base;
  let drums = d.knob === 3 ? (length, sec, tier, mega) => drumEvents(length, sec, tier >= 5 ? 4 : tier + 1, mega) : null;
  const p = { ...r.params, ...(override.params || {}) };
  let out = r, playing = null, fl = null;
  if (full) {
    const count = channels === 'rarity' ? channelCount(seed, b.tier) : Math.min(6, Math.max(3, +channels));
    playing = channelPick(out.form.events, count, d.v === 2 && d.rotate !== null ? d.rotate : seed);
    out = { ...out, form: { ...out.form, events: out.form.events.filter((e) => playing.includes(e.voice_id)) } };
    if (!playing.includes('drums')) drums = false;
  }
  let tied = null;
  if (ties) { const t2 = tieRepeats(out.form, ties === 'all' ? 'all' : 'weak'); tied = t2.tied; out = { ...out, form: t2.form }; }
  // the Yeti special: 16th-note ornaments placed by the track's own profile (its special name), the
  // avalanche down each section's closing chord, and the rock groove at 175 BPM, on the track's key
  let yetiMix = null;
  if (yetiOn) {
    const ys = { ...out, yetiScale: override.scale || null };
    let ev = yetiOrnaments(out.form.events.map((e) => ({ ...e })), ys, name ? { ...b, ...nm } : b, E, false, true);
    ev = yetiAvalanche(ev, ys, E, YETI_AVALANCHE_VOICE);
    ev.sort((a, c) => a.voice_id - c.voice_id || a.time - c.time);
    out = { ...out, form: { ...out.form, events: ev } };
    if (drums !== false) drums = (length, s2) => rockDrums(length, s2);
    yetiMix = { programs: { [YETI_AVALANCHE_VOICE]: 13 }, notLead: [YETI_AVALANCHE_VOICE] };
  }
  // flourishes on the voices that play (after the channel filter)
  if (flourishDay) { fl = addFlourishes(out.form, flourishDay, H('BEAST_FLOURISH_KEY', entityHash(b), name, seed ?? 0n), orn); out = { ...out, form: fl.form }; }
  const info = { key: keyName(p), voices: p.voice_count, sections: p.section_count, tempo: Math.round(60e6 / (override.tempo_us || p.tempo_us)), ...r.v11.trajectory,
    tied,
    flourishes: fl ? { count: fl.added.length, share: fl.share, notes: fl.added.flatMap((x) => (x.notes ? x.notes.map(([time, pitch]) => ({ voice: x.voice, time, pitch })) : [{ voice: x.voice, time: x.time, pitch: x.pitch }])), voices: [...new Set(fl.added.map((x) => x.voice))].length, shapes: fl.added.reduce((m, x) => ((m[x.shape] = (m[x.shape] || 0) + 1), m), {}) } : null,
    channels: playing ? playing.map((c, i) => (i === 1 && c !== 4 && c !== 'drums' ? 'low voice' : CHANNEL_NAMES[c])) : null };
  // echo: the chip echo of sound_effects 2 and 3 (full_midi.js)
  const fx = { ...(b.shiny ? MEGA_ALL : {}), ...(echo ? { echo: true } : {}) };
  // the lead's grace notes from the song's ornament density (full_midi.js graceOf): on a day of drift
  // after the first only, never on a written track
  // the kind: from the week's hash on a drift week (the channel order's seed), else the bought track's
  // seed, else from the species and density (genesis.cairo song_tracks)
  const kseed = d.v === 2 && d.rotate !== null ? d.rotate : seed;
  const gkind = kseed !== null && kseed !== undefined ? Math.floor(Number(BigInt(kseed) & 0xffffffffn) / 2048) % 4 : ((Number(p.species_id) % 4) + p.ornament_density) % 4;
  // the ornaments that grow with time (genesis.cairo song_ornaments): none as written or on day 1;
  // graces (every canon voice from day 360, +15% from day 540) and the inner voices' fills, drawn
  // from the seed under a ceiling rising with the day
  const day = off ? 0 : epoch, kh = kseed !== null && kseed !== undefined ? Number(BigInt(kseed) & 0xffffffffn) : 0;
  const grace = day >= 2 ? graceOf(p.ornament_density + (day >= 540 ? 3 : 0), gkind) : 0;
  const fill = day >= 2 ? [0, 15, 30, 50][Math.floor(kh / 524288) % ((day < 180 ? 0 : day < 360 ? 1 : day < 540 ? 2 : 3) + 1)] : 0;
  const songScale = MODE_SCALES[p.mode_id] ?? (p.mode_id === 6 ? [0, 2, 3, 5, 7, 9, 11] : p.mode_id === 7 ? [0, 2, 4, 6, 8, 10] : [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 9, 10], [0, 1, 3, 5, 7, 8, 10], [0, 2, 4, 6, 7, 9, 11], [0, 2, 4, 5, 7, 9, 10], [0, 2, 3, 5, 7, 8, 10]][p.mode_id % 6]);
  return { midi: beastFullMidi(out, E.formLength, fx, { instruments: 'beast', drums, mix, topLead, grace, graceAll: day >= 360, fill, tonic: p.tonic_keynum, scale: songScale, ...(yetiMix || {}) }), drift: d, result: out, info };
}

// ── the Genesis Track, as the lab plays it by default (and as the Cairo port must match) ─────────
/** Tier and type of a species: tiers in fives within each 25 (Magic 1-25, Hunter 26-50, Brute 51-75). */
export const speciesTier = (id) => Math.floor(((id - 1) % 25) / 5) + 1;
export const speciesType = (id) => Math.floor((id - 1) / 25);
/** The default settings of a Genesis Track (name 0, seed 0): spread keys, the chosen themes, the species
 *  motif, the tier's Genesis channels, the balanced mix, weak-beat ties on inner voices, no pluck on top. */
export const GENESIS_DEFAULTS = { name: 0, seed: 0n, theme: 'species', genesisKey: 'spread', channels: 'rarity', mix: 'balanced', ties: 'weak', topLead: true, motif: 'default', trueV: false };
/** The Genesis Track a Beast of `speciesId` plays: the default swaps applied (it plays its swap partner's
 *  Genesis music), the mega sound when shiny. The reference for BeastMidiProvider.get_midi's Cairo. */
export function genesisMidi(speciesId, shiny, E, v11, opts = {}) {
  const src = GENESIS_SWAPS[speciesId] || speciesId;
  const b = { id: src, prefix: 0, suffix: 0, level: 1, health: 100, shiny: shiny ? 1 : 0, animated: 0, tier: speciesTier(src), beast_type: speciesType(src) };
  return sampleTrackMidi(b, { species_count: 1 }, { ...GENESIS_DEFAULTS, ...opts }, E, v11);
}

// ── curated species Sound Checks (audition candidates) ───────────────────────────────────────
export function soundCheckMidi(b, E) {
  if (b.id === 64) return cyclopsSoundCheckMidi();
  const neutral = { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1 };
  const named = b.prefix !== 0;
  // Unnamed checks warm up the actual shared song, including the Harpy/Pegasus swap.
  const source = !named ? (GENESIS_SWAPS[b.id] || b.id) : b.id;
  const g = genesisBeast({ ...b, id: source });
  const kp = E.mapV3(named ? { ...g, prefix: b.prefix, suffix: b.suffix } : spreadKeyBeast(g), neutral);
  const satori = b.id === 44 && (!named || nameVariant(b.prefix, b.suffix) === 1);
  const mode = satori ? 7 : !named && GENESIS_MODES[source] !== undefined ? GENESIS_MODES[source] : kp.mode_id;
  const row = catalogueCheck(b.id, b.beast_type);
  const tonic = row.register + ((satori ? 57 : kp.tonic_keynum) % 12);
  const result = renderCatalogueCheck(row, { tonic, scale: MODE_SCALES[mode], mega: !!b.shiny });
  return { midi: result.midi, result: { beast: b, params: { tempo_us: row.tempo_us }, form: { events: result.events, section_ticks: 15360, sections: [0] } }, info: { key: keyName({ mode_id: mode, tonic_keynum: tonic }), presets: [result.program], tempo_us: row.tempo_us, tempo: Math.round(60e6 / row.tempo_us), bpm: 60e6 / row.tempo_us, curated: true, mode_id: mode, tonic_keynum: tonic, phrase: row.phrase, species: b.id } };
}

/** A simulated per-Beast auction: the offer's seed chain and a gradual Dutch auction price. */
export const GDA = { start: 100, floor: 5, halfLifeHours: 12 };
export const gdaPrice = (hours) => Math.max(GDA.floor, Math.round(GDA.start * Math.pow(0.5, hours / GDA.halfLifeHours)));
/** Offer n's seed: n = 0 from the launch block, then from the block of purchase n - 1. */
export const offerSeed = (tokenKey, n, blockHash) => H('BEAST_TRACK_OFFER', blockHash, tokenKey, n);

// ── one entry point for the page ──────────────────────────────────────────────────────────────
export function labMidi(mode, b, live, args, E, v11) {
  if (mode === 'track') {
    const { live: l, opts, shape } = trackOptions(b, live, args.track, args.event);
    const r = reshape(v11.render(b, l, opts), shape);
    return { midi: beastFullMidi(r, E.formLength, b.shiny ? MEGA_ALL : {}, { instruments: 'beast' }), result: r };
  }
  if (mode === 'progression') {
    const full = v11.render(b, live, V11);
    return { midi: progressionMidi(full, E, args.unlocked, args.seed, !!args.three), order: args.three ? PREFERRED_ORDER : unlockOrder(args.seed) };
  }
  if (mode === 'drift') return driftMidi(b, live, args.epoch, E, v11, args.blockHashes ? dayAnchor() : null);
  if (mode === 'tracks') return ownedTrackMidi(b, live, args.seed, args.epoch, E, v11);
  if (mode === 'species') return speciesTrackMidi(b, live, args.seed, args.epoch, E, v11);
  if (mode === 'sample') return sampleTrackMidi(b, live, args, E, v11);
  if (mode === 'yeti') return { midi: yetiMidi(b, live, args.ideas, E, v11) };
  if (mode === 'soundcheck') return soundCheckMidi({ ...b, ...nameFromVariant(args.name) }, E);
  throw new Error('mode ' + mode);
}
