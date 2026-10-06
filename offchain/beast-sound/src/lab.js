// Beast Sound lab: listening prototypes on top of composer v1.1 and the self-contained MIDI, JS only.
//
//   event tracks   every kill and defeat in Death Mountain's records makes a track; the holder picks
//                  one (Beasts V3 change_track(token_id, track_id)); $SKULL unlocks variations
//   progression    a Beast starts as its own scale; each unlock reveals a layer, in an order
//                  fixed by the Beast (onchain: the unlock transaction's block hash)
//   drift          a never-ending track: each epoch (a day of blocks, seeded by an old block hash)
//                  turns at most one small knob, so the music stays itself from day to day
//   specials       the Yeti (species 68): rock groove, yodel, avalanche, stomp
//
// Every function is a pure function of its inputs, like the composer, so each can move to Cairo.
import { poseidonHashMany } from './index.js';
import { MEGA_ALL, beastFullMidi, beastInstruments, drumEvents } from './full_midi.js';

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
export function drift(b, epoch) {
  const s = low32(H('BEAST_DRIFT', entityHash(b), epoch));
  const knob = s % 5; // 4 = no change
  return { knob: knob < 4 ? knob : null, label: knob < 4 ? DRIFT_KNOBS[knob] : 'as written' };
}

// ── layered drift (v2): every change audible, on three clocks, so a track evolves over years ──────
// The month (30 days) may re-pick the rhythm cells (2 months in 3; the first month plays as written);
// the week may rotate which channels play, keeping the count and the theme and low voice (3 weeks in 4;
// needs the full six channels); the day turns one more knob: the key plan the other way, the episode
// directions swapped, or the tempo nudged -4, -2, +2 or +4 BPM. Nothing accumulates: a day's version is
// a pure function of the track and the day number.
export const DRIFT2_DAY = ['key plan turns the other way', 'episode directions swap', 'tempo -4 BPM', 'tempo -2 BPM', 'tempo +2 BPM', 'tempo +4 BPM'];
export function drift2(b, day) {
  const k = entityHash(b), month = Math.floor((day - 1) / 30), week = Math.floor((day - 1) / 7);
  const m = low32(H('BEAST_DRIFT2_M', k, month)), w = low32(H('BEAST_DRIFT2_W', k, week)), dk = low32(H('BEAST_DRIFT2_D', k, day)) % 6;
  const rhythm = month > 0 && m % 3 !== 0 ? H('BEAST_DRIFT2_RHYTHM', k, month) : null;
  const rotate = w % 4 !== 0 ? H('BEAST_DRIFT2_ROT', k, week) : null;
  const delta = [0, 0, -4, -2, 2, 4][dk];
  const label = [rhythm !== null ? 'month ' + (month + 1) + ': new rhythm' : 'month ' + (month + 1) + ': rhythm as written',
    rotate !== null ? 'week ' + (week + 1) + ': channels rotate' : 'week ' + (week + 1) + ': channels as picked', 'day: ' + DRIFT2_DAY[dk]].join(' \u00b7 ');
  return { v: 2, rhythm, rotate, dayKnob: dk, delta, label };
}

export function driftMidi(b, live, epoch, E, v11) {
  const d = drift(b, epoch), override = {};
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
export const YETI_IDEAS = {
  rock: 'Rock groove: 175 BPM, kick on 1 and 3, snare backbeat, eighth hats, crash and tom fill at every section (the #301 groove)',
  yodel: 'Yodel: the lead leaps an octave on every other note of each beat pair, chest voice to head voice',
  avalanche: 'Avalanche: each section ends in a two-octave sixteenth-note arpeggio down through the closing chord on the Pulse 12.5% Pluck, landing on a crash',
  stomp: 'Stomp: three-quarter speed, a kick on every beat, the bass doubled an octave down',
};

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

export function yetiMidi(b, live, ideas, E, v11) {
  const opts = ideas.rock ? { ...V11, override: { tempo_us: 342857 } } : ideas.stomp ? { ...V11, override: { tempo_us: 666667 } } : V11;
  let r = v11.render(b, live, opts);
  let events = r.form.events.map((e) => ({ ...e }));
  const sec = r.form.section_ticks, sections = r.form.sections.length, maxV = Math.max(...events.map((e) => e.voice_id));
  const programs = {};
  let stompDouble = null;
  if (ideas.yodel) {
    // the theme voice: the second note of each beat pair jumps an octave up
    events = events.map((e) => (e.voice_id === 0 && Math.floor(e.time / 240) % 2 === 1 && e.pitch + 12 <= 108 ? { ...e, pitch: e.pitch + 12 } : e));
  }
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
    // the last half bar of each section: an arpeggio down two octaves in sixteenths through the chord
    // that is sounding there (the pitch classes of the other voices in that half bar), from the bass
    // note's pitch class two octaves above the home tonic's register down to it, so the run is in key and
    // on the chord, whatever the section closes on; a bare unison or fifth is filled out to the triad the
    // chord the key's scale gives it
    const ch = maxV + 2, top = r.params.tonic_keynum + 36, I = E.internals;
    const mode = I.canonicalToMelodic(r.params.mode_id), home = I.transposedTonic(r.params.tonic_keynum, 0);
    const scale = Array.from({ length: 7 }, (_, d) => I.realize(d, home, mode) % 12);
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
      const best = pref.slice().sort((a, c) => cover(c, pcs) - cover(a, pcs) || cover(c, heard) - cover(a, heard) || perfect(c) - perfect(a) || pref.indexOf(a) - pref.indexOf(c))[0];
      const root = scale[best], chord = triad(best); // the run uses the triad only, never a passing note
      let hi = top - (((top - root) % 12) + 12) % 12; // the highest pitch class of the root at or below top
      const run = [];
      for (let q = hi; q >= hi - 24; q--) if (chord.includes(q % 12)) run.push(q);
      const n = Math.min(run.length, 8), picked = run.length <= 8 ? run : run.filter((_, k) => k % Math.ceil(run.length / 8) === 0 || k === run.length - 1).slice(-8);
      if (picked[picked.length - 1] !== hi - 24) picked.push(hi - 24);
      const notes = picked.slice(-Math.min(picked.length, 8)), t0 = end - notes.length * 120;
      notes.forEach((q, i) => events.push({ time: t0 + i * 120, duration: 110, pitch: q, velocity: 112 - i * 4, voice_id: ch, role: 'avalanche' }));
    }
    programs[ch] = 13; // Pulse 12.5% Pluck: a bright, icy run
  }
  events.sort((a, c) => a.voice_id - c.voice_id || a.time - c.time);
  // keep each voice monophonic and in time order (the writer's contract)
  r = { ...r, form: { ...r.form, events } };
  if (stompDouble) programs[stompDouble.ch] = beastInstruments(r)[stompDouble.low] ?? 16;
  const drums = ideas.rock ? (length, s2) => rockDrums(length, s2) : ideas.stomp ? stompDrums : null;
  return beastFullMidi(r, E.formLength, b.shiny ? MEGA_ALL : {}, { instruments: 'beast', programs, drums });
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
// Name 0 is the species' Genesis Track, the base every Beast of the species starts with. Names 1-1242
// are the 69 x 18 prefix/suffix pairs (name variant id = 1 + (prefix - 1) * 18 + (suffix - 1)): a name
// sets the key, mode and register (prefix) and the ornament style (suffix), as it does for a named Beast
// in v1.1. The seed sets the treatment: development, episode direction, sections, spacing, which side the
// theme sits and the rhythm cells. With theme 'species' every track keeps the species' motif (the
// Genesis Track's theme); with 'name' the name also re-seeds the motif, as v1.1 does today.
// genesisKey 'rule' is v1.1's genesis key (every species Phrygian, tonic = id mod 12); 'spread' gives
// each species the key of a canonical name instead; 'proposed' adds genesisTempo (the Genesis Track
// table's starting point), for comparing while the 75 Genesis Tracks are tuned.
export const NAME_COUNT = 69 * 18;
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

export function sampleTrackMidi(b, live, { name = 0, seed = null, theme = 'species', genesisKey = 'rule', epoch = null, channels = 'tier', bpm = null, driftMode = 'v1', mix = null, flourishDay = null, ties = false } = {}, E, v11) {
  const neutral = { adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: live.species_count || 1 };
  const g = genesisBeast(b), nm = nameFromVariant(name);
  const t = seed === null || seed === undefined ? null : trackTreatment(seed);
  const cb = name && theme === 'name' ? { ...g, ...nm } : g; // the Beast the composer sees (theme, register)
  // channels 'tier': v1.1's voices for the tier; 'rarity' or a forced count 3-6: the full six, filtered
  const full = channels !== 'tier';
  const override = { voice_count: full ? 4 : TIER_VOICES[b.tier] ?? 2, sections: t ? t.sections : TIER_SECTIONS[b.tier] ?? 2, tr: {} };
  if (t) Object.assign(override, { rhythmSeed: t.rhythmSeed, flipSide: t.flipSide, tr: { development: t.development, direction: t.direction, spacing: t.spacing } });
  let orn = E.mapV3(cb, neutral)._ornament;
  if (name && theme === 'species') { // the name's key and ornament style on the species' theme
    const kp = E.mapV3({ ...g, ...nm }, neutral);
    override.params = { mode_id: kp.mode_id, tonic_keynum: kp.tonic_keynum, register_band: kp.register_band, ornament_density: kp.ornament_density, _ornament: kp._ornament };
    orn = kp._ornament;
  } else if (!name && (genesisKey === 'spread' || genesisKey === 'proposed')) {
    const kp = E.mapV3(spreadKeyBeast(g), neutral);
    override.params = { mode_id: kp.mode_id, tonic_keynum: kp.tonic_keynum, register_band: kp.register_band };
  }
  if (!name && genesisKey === 'proposed') override.tempo_us = Math.round(60e6 / genesisTempo(b));
  if (bpm) override.tempo_us = Math.round(60e6 / bpm); // the page's tempo control
  override.tr.trill = !!orn.allow_trill;
  if (full) override.params = { ...(override.params || {}), use_countersubject: true };
  const off = epoch === null || epoch === undefined;
  const d = off ? { knob: null, label: 'off' } : driftMode === 'v2' ? drift2(b, epoch) : drift(b, epoch);
  if (d.v === 2 && d.rhythm !== null) override.rhythmSeed = d.rhythm;
  const base = v11.render(cb, neutral, { ...V11, override });
  const tr = base.v11.trajectory;
  let again = d.knob === 0 || d.knob === 1 || d.knob === 2;
  if (d.knob === 0) override.flipSide = !override.flipSide;
  if (d.knob === 1) override.tr = { ...override.tr, direction: tr.direction === 0 ? 1 : -tr.direction };
  if (d.knob === 2) override.tr = { ...override.tr, trill: !tr.trill };
  if (d.v === 2) {
    again = true;
    if (d.dayKnob === 0) override.flipSide = !override.flipSide;
    else if (d.dayKnob === 1) override.tr = { ...override.tr, direction: tr.direction === 0 ? 1 : -tr.direction };
    else override.tempo_us = Math.round(60e6 / (60e6 / (override.tempo_us || base.params.tempo_us) + d.delta));
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
  // flourishes on the voices that play (after the channel filter)
  if (flourishDay) { fl = addFlourishes(out.form, flourishDay, H('BEAST_FLOURISH_KEY', entityHash(b), name, seed ?? 0n), orn); out = { ...out, form: fl.form }; }
  const info = { key: keyName(p), voices: p.voice_count, sections: p.section_count, tempo: Math.round(60e6 / (override.tempo_us || p.tempo_us)), ...r.v11.trajectory,
    tied,
    flourishes: fl ? { count: fl.added.length, share: fl.share, notes: fl.added.flatMap((x) => (x.notes ? x.notes.map(([time, pitch]) => ({ voice: x.voice, time, pitch })) : [{ voice: x.voice, time: x.time, pitch: x.pitch }])), voices: [...new Set(fl.added.map((x) => x.voice))].length, shapes: fl.added.reduce((m, x) => ((m[x.shape] = (m[x.shape] || 0) + 1), m), {}) } : null,
    channels: playing ? playing.map((c, i) => (i === 1 && c !== 4 && c !== 'drums' ? 'low voice' : CHANNEL_NAMES[c])) : null };
  return { midi: beastFullMidi(out, E.formLength, b.shiny ? MEGA_ALL : {}, { instruments: 'beast', drums, mix }), drift: d, result: out, info };
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
  if (mode === 'drift') return driftMidi(b, live, args.epoch, E, v11);
  if (mode === 'tracks') return ownedTrackMidi(b, live, args.seed, args.epoch, E, v11);
  if (mode === 'species') return speciesTrackMidi(b, live, args.seed, args.epoch, E, v11);
  if (mode === 'sample') return sampleTrackMidi(b, live, args, E, v11);
  if (mode === 'yeti') return { midi: yetiMidi(b, live, args.ideas, E, v11) };
  throw new Error('mode ' + mode);
}
