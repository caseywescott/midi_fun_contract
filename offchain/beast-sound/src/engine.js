// Beast Sound engine: the Koji Beast composer in plain JavaScript.
//
// A line-for-line port of the Cairo reference implementation:
//   src/composition/beast_v3_sound.cairo   (V3 token -> BeastCompositionParams, MIDI, BSN1)
//   src/composition/beast_trait_map.cairo  (key cells, ornament policy, buckets)
//   src/composition/beast_score.cairo      (build_beast_form: hashed theme, canon, countersubject,
//                                           articulation, score hash)
// Same inputs => same score hash, note events, MIDI bytes and BSN1 bytes. Checked against Cairo
// output by test/golden.test.mjs (fixtures regenerated with scripts/beast_v3_parity.mjs --write).
//
// Poseidon is injected so this file has no dependencies:
//   createEngine({ poseidonHashMany })       // full engine, incl. BSN1 (bsn.js)
//   createCoreEngine({ poseidonHashMany })   // composition + MIDI only

import { createBsn } from './bsn.js';
import { notesToMidi } from './midi_file.js';

export const TABLES = {
  species: ['Warlock', 'Typhon', 'Jiangshi', 'Anansi', 'Basilisk', 'Gorgon', 'Kitsune', 'Lich', 'Chimera', 'Wendigo', 'Rakshasa', 'Werewolf', 'Banshee', 'Draugr', 'Vampire', 'Goblin', 'Ghoul', 'Wraith', 'Sprite', 'Kappa', 'Fairy', 'Leprechaun', 'Kelpie', 'Pixie', 'Gnome', 'Griffin', 'Manticore', 'Phoenix', 'Dragon', 'Minotaur', 'Qilin', 'Ammit', 'Nue', 'Skinwalker', 'Chupacabra', 'Weretiger', 'Wyvern', 'Roc', 'Harpy', 'Pegasus', 'Hippogriff', 'Fenrir', 'Jaguar', 'Satori', 'Direwolf', 'Bear', 'Wolf', 'Mantis', 'Spider', 'Rat', 'Kraken', 'Colossus', 'Balrog', 'Leviathan', 'Tarrasque', 'Titan', 'Nephilim', 'Behemoth', 'Hydra', 'Juggernaut', 'Oni', 'Jotunn', 'Ettin', 'Cyclops', 'Giant', 'Nemean Lion', 'Berserker', 'Yeti', 'Golem', 'Ent', 'Troll', 'Bigfoot', 'Ogre', 'Orc', 'Skeleton'],
  prefixes: ['Agony', 'Apocalypse', 'Armageddon', 'Beast', 'Behemoth', 'Blight', 'Blood', 'Bramble', 'Brimstone', 'Brood', 'Carrion', 'Cataclysm', 'Chimeric', 'Corpse', 'Corruption', 'Damnation', 'Death', 'Demon', 'Dire', 'Dragon', 'Dread', 'Doom', 'Dusk', 'Eagle', 'Empyrean', 'Fate', 'Foe', 'Gale', 'Ghoul', 'Gloom', 'Glyph', 'Golem', 'Grim', 'Hate', 'Havoc', 'Honour', 'Horror', 'Hypnotic', 'Kraken', 'Loath', 'Maelstrom', 'Mind', 'Miracle', 'Morbid', 'Oblivion', 'Onslaught', 'Pain', 'Pandemonium', 'Phoenix', 'Plague', 'Rage', 'Rapture', 'Rune', 'Skull', 'Sol', 'Soul', 'Sorrow', 'Spirit', 'Storm', 'Tempest', 'Torment', 'Vengeance', 'Victory', 'Viper', 'Vortex', 'Woe', 'Wrath', 'Lights', 'Shimmering'],
  suffixes: ['Bane', 'Root', 'Bite', 'Song', 'Roar', 'Grasp', 'Instrument', 'Glow', 'Bender', 'Shadow', 'Whisper', 'Shout', 'Growl', 'Tear', 'Peak', 'Form', 'Sun', 'Moon'],
  types: ['Magic', 'Hunter', 'Brute'],
};

// Genesis species tier/type tables (beasts/src/beast_definitions.cairo).
export function genesisTier(id) {
  const r = (id - 1) % 25;
  return Math.floor(r / 5) + 1;
}
export function genesisType(id) {
  return id <= 25 ? 0 : id <= 50 ? 1 : 2;
}

export const MODE_NAMES = { 4: 'Dorian', 5: 'Phrygian', 6: 'Locrian', 7: 'Aeolian', 8: 'Harmonic minor', 26: 'Dorian ♯4' };
export const FAMILY_NAMES = {
  '18/8': 'Altered-dominant ♭9 canon', '25/15': 'Soft chromatic cluster', '34/19': 'Phrygian 3-voice canon',
  '40/0': 'Smooth pentatonic canon', '3/0': 'Unison canon', '24/14': 'Bartók axis canon', '29/19': 'Phrygian 4-voice canon',
  '30/0': 'Open pentatonic canon', '1/0': 'Canon at the fifth below', '20/10': 'Octatonic axis canon',
  '11/2': 'Quartal 4-stack canon', '12/4': 'Hindemith 4-voice canon', '10/2': 'Quartal stack canon', '4/0': 'Three-voice 5th-below/8va canon',
};
export const ORNAMENT_FAMILIES = ['structural', 'pedal', 'suspension', 'neighbor', 'trill', 'turn'];

const ART_NORMAL = 0, ART_STACCATO = 1, ART_TENUTO = 2, ART_ACCENT = 3, ART_PORTATO = 5;
export const ARTICULATION_NAMES = { 0: 'normal', 1: 'staccato', 2: 'tenuto', 3: 'accent', 5: 'portato' };
const TIME_UNIT = 480;
const DEFAULT_VELOCITY = 90;
const SCORE_VERSION = 1;
const FIELD_P = 2n ** 251n + 17n * 2n ** 192n + 1n;

export function shortString(s) {
  let v = 0n;
  for (const c of s) v = (v << 8n) | BigInt(c.charCodeAt(0));
  return v;
}

/**
 * Composition + MIDI only: what the onchain page library bundles. The compact BSN1 note stream
 * (used for Cairo parity and onchain note storage) lives in bsn.js; createEngine adds it.
 */
export function createCoreEngine({ poseidonHashMany }) {
  const H = (...xs) => poseidonHashMany(xs.map((x) => (typeof x === 'string' ? shortString(x) : BigInt(x))));
  const enc = (d) => (d < 0 ? 1000 + d : d); // Cairo's (1000 + negative) felt encoding

  // ── V3 token ID (beasts pack.cairo) ──────────────────────────────
  function decodeTokenId(tokenId) {
    let p = BigInt(tokenId);
    const take = (bits) => { const m = 1n << BigInt(bits); const v = p % m; p /= m; return Number(v); };
    const id = take(64), prefix = take(7), suffix = take(5), level = take(16), health = take(16);
    const shiny = take(1), animated = take(1), tier = take(3), beast_type = take(3);
    if (p !== 0n) throw new Error('invalid token id');
    const b = { id, prefix, suffix, level, health, shiny, animated, tier, beast_type };
    assertValid(b);
    return b;
  }
  function encodeTokenId(b) {
    return BigInt(b.id) + (BigInt(b.prefix) << 64n) + (BigInt(b.suffix) << 71n) + (BigInt(b.level) << 76n)
      + (BigInt(b.health) << 92n) + (BigInt(b.shiny) << 108n) + (BigInt(b.animated) << 109n)
      + (BigInt(b.tier) << 110n) + (BigInt(b.beast_type) << 113n);
  }
  function assertValid(b) {
    if (b.id === 0) throw new Error('invalid beast id');
    if (b.tier < 1 || b.tier > 5) throw new Error('invalid tier');
    if (b.beast_type > 2) throw new Error('invalid type');
    if (b.prefix > 69 || b.suffix > 18) throw new Error('invalid affix');
    if ((b.prefix === 0) !== (b.suffix === 0)) throw new Error('invalid affix combo');
  }

  // Genesis Beast (id, 0, 0) with provenance attributes; its holder is the species' artist.
  const genesisTokenId = (id, tier, beast_type) => encodeTokenId({ id, prefix: 0, suffix: 0, level: 1, health: 100, shiny: 1, animated: 1, tier, beast_type });

  // ── identity ─────────────────────────────────────────────────────
  const soundSeed = (id, prefix, suffix) => H('BEAST_SOUND_V1', id, prefix, suffix);
  const soundDropRoll = (salt, id, prefix, suffix) => Number(H('BEAST_SOUND_DROP', salt, id, prefix, suffix) % 10000n);
  const hasSound = (salt, bps, b) => b.prefix === 0 || soundDropRoll(salt, b.id, b.prefix, b.suffix) < bps;
  const nameVariantId = (prefix, suffix) => (prefix === 0 ? 0 : 1 + (prefix - 1) * 18 + (suffix - 1));

  // ── beast_trait_map.cairo ────────────────────────────────────────
  function prefix1Key(prefix1, tier) {
    const fam = [7, 5, 4, 8][prefix1 % 4]; // Aeolian, Phrygian, Dorian, HarmonicMinor
    let mode = fam;
    if (tier <= 2) {
      const gate = prefix1 % 12;
      if (gate === 10) mode = 6; // Locrian
      if (gate === 11) mode = 26; // Dorian #4
    }
    return { mode_id: mode, tonic_pc: prefix1 % 12, register_band: Math.floor(prefix1 / 12) % 3 };
  }
  function genesisKey(id, tier) {
    return { mode_id: 5, tonic_pc: id % 12, register_band: tier <= 2 ? 0 : tier <= 4 ? 1 : 2 };
  }
  function prefix2Policy(p2) {
    const family = p2 % 6;
    return {
      profile_id: family, density_cap: 1 + (p2 % 5), allow_chromatic_approach: p2 >= 6,
      allow_suspension: family === 2 || family === 3 || p2 >= 12, allow_trill: family === 4 || family === 5,
    };
  }
  function bucketLog2(n) {
    let x = n + 1, b = 0;
    while (!(x <= 1 || b >= 7)) { x = Math.floor(x / 2); b += 1; }
    return b;
  }
  const sectionsForKill = (k) => (k === 0 ? 1 : k === 1 ? 2 : k <= 3 ? 3 : k <= 5 ? 4 : 5);
  const tonicKeynum = (key) => [48, 60, 72][key.register_band] + key.tonic_pc;
  const strettoLag = (bucket) => { const base = 4, min = 1, range = base - min; const red = Math.floor(range * bucket / 7); return red >= range ? min : base - red; };

  // ── beast_v3_sound.cairo ─────────────────────────────────────────
  function typeTierFamily(type, tier) {
    const base_voice_count = tier <= 2 ? 3 : tier === 3 ? 2 : 1;
    const t = [
      [[18, 8], [25, 15], [34, 19], [40, 0], [3, 0]],
      [[24, 14], [29, 19], [30, 0], [1, 0], [1, 0]],
      [[20, 10], [11, 2], [12, 4], [10, 2], [4, 0]],
    ][type][tier - 1];
    return { canon_config_id: t[0], profile_id: t[1], base_voice_count };
  }
  const typeToRelation = (type) => (type === 0 ? 2 : type === 1 ? 0 : 1); // weakness codes
  function visualLayer(shiny, animated) {
    if (shiny && animated) return [45000, 127, ART_ACCENT];
    if (animated) return [30000, 120, ART_PORTATO];
    if (shiny) return [25000, 124, ART_TENUTO];
    return [0, 112, ART_NORMAL];
  }
  function rankTier(rank, count) {
    if (rank === 0) return 1;
    if (rank === 1) return 0;
    const c = count === 0 ? 1 : count;
    const pm = Math.floor(rank * 1000 / c);
    return pm <= 10 ? 1 : pm <= 50 ? 2 : pm <= 200 ? 3 : 4;
  }
  const clampU32 = (v) => Math.min(Number(v), 0xffffffff);
  const satAdd = (a, b) => Math.min(a + b, 0xffffffff);
  function musicState(live) {
    const kills = clampU32(live.adventurers_killed), scars = clampU32(live.scars);
    const hours = clampU32(Math.floor(Number(live.summit_held_seconds || 0) / 3600));
    return {
      kill_bucket: bucketLog2(kills), defeat_bucket: bucketLog2(scars), summit_bucket: bucketLog2(hours),
      encounter_bucket: bucketLog2(satAdd(satAdd(kills, scars), hours)),
      rank_tier: rankTier(live.rank, live.species_count), is_crown: live.rank === 1,
    };
  }

  function mapV3(b, live) {
    assertValid(b);
    const tier = b.tier;
    const family = typeTierFamily(b.beast_type, tier);
    const genesis = b.prefix === 0;
    const key = genesis ? genesisKey(b.id, tier) : prefix1Key(b.prefix - 1, tier);
    if (b.health >= 250 && key.register_band > 0) key.register_band -= 1;
    const orn = genesis
      ? { profile_id: family.profile_id, density_cap: 1, allow_chromatic_approach: false, allow_suspension: tier <= 3, allow_trill: false }
      : prefix2Policy(b.suffix - 1);
    const [tempoBump, velCeil, visArt] = visualLayer(b.shiny, b.animated);
    const st = musicState(live);
    const crownBump = st.is_crown && st.kill_bucket < 7 ? 1 : 0;
    const stretto_bucket = st.kill_bucket + crownBump;
    const extra = st.kill_bucket >= 4 && tier <= 3 ? 1 : 0;
    const rankV = st.rank_tier <= 1 && tier <= 2 ? 1 : 0;
    const levelV = b.level >= 64 && tier <= 4 ? 1 : 0;
    const maxV = tier <= 2 ? 4 : tier === 3 ? 3 : 2;
    const voice_count = Math.min(family.base_voice_count + extra + rankV + levelV, maxV);
    const density = orn.density_cap + st.kill_bucket + (st.is_crown ? 1 : 0) + (st.summit_bucket >= 4 ? 1 : 0);
    return {
      species_id: b.id, name_variant_id: nameVariantId(b.prefix, b.suffix), mode_id: key.mode_id,
      tonic_keynum: tonicKeynum(key), register_band: key.register_band, tier, weakness: typeToRelation(b.beast_type),
      canon_config_id: family.canon_config_id, profile_id: family.profile_id, voice_count,
      section_count: sectionsForKill(st.kill_bucket), stretto_bucket, stretto_lag: strettoLag(stretto_bucket),
      use_inversion: st.defeat_bucket >= 3 || (tier <= 2 && st.encounter_bucket >= 4),
      use_countersubject: tier <= 2 || (tier === 3 && st.rank_tier <= 1),
      use_compound_melody: tier >= 4, ornament_density: Math.min(density, 7),
      articulation_profile: st.is_crown ? ART_ACCENT : visArt, velocity_ceiling: velCeil,
      tempo_us: 500000 - tempoBump, score_version: SCORE_VERSION,
      _ornament: orn, _state: st,
    };
  }

  function musicStateHash(b, live) {
    const st = musicState(live);
    return H('BEAST_MUSIC_STATE_V3', soundSeed(b.id, b.prefix, b.suffix), SCORE_VERSION, b.level, b.health,
      b.shiny, b.animated, b.tier, b.beast_type, st.kill_bucket, st.defeat_bucket, st.summit_bucket, st.encounter_bucket,
      st.rank_tier, st.is_crown ? 1 : 0);
  }

  // ── beast_score.cairo ────────────────────────────────────────────
  const paramsHash = (p) => H(p.species_id, p.name_variant_id, p.mode_id, p.tonic_keynum, p.tier, p.weakness,
    p.canon_config_id, p.profile_id, p.voice_count, p.section_count, p.stretto_bucket, p.stretto_lag,
    p.ornament_density, p.articulation_profile, p.register_band, p.use_inversion ? 1 : 0,
    p.use_countersubject ? 1 : 0, p.velocity_ceiling, p.tempo_us);

  const deriveSeeds = (seed) => ({
    motif_seed: H(seed, 'MOTIF'), canon_seed: H(seed, 'CANON'),
    orchestration_seed: H(seed, 'ORCHESTRATION'), ornament_seed: H(seed, 'ORNAMENT'),
  });

  function walkLeaderHashed(seed, len, band) {
    const degrees = [0], steps = [];
    let prior = H(seed, 'BEAST_PRIOR');
    const cands = [-2, -1, 1, 2];
    for (let p = 1; p < len; p++) {
      const cur = degrees[degrees.length - 1];
      const raw = Number(H(seed, 'LEADER_WALK_V2', p, enc(cur), prior) % 0x100000000n);
      let picked = 0, found = false;
      for (let tries = 0; tries < 4 && !found; tries++) {
        const cand = cands[(raw + tries) % 4];
        const next = cur + cand;
        if (next >= -band && next <= band) { picked = cand; found = true; }
      }
      if (!found) picked = cur > 0 ? -1 : cur < 0 ? 1 : 0;
      degrees.push(cur + picked);
      steps.push(picked);
      prior = H(prior, enc(picked));
    }
    return { degrees, steps };
  }
  function buildTheme(p, motifSeed) {
    const len = 12 + (p.tier <= 2 ? 4 : 0);
    const band = p.register_band === 0 ? 5 : 7;
    const { degrees, steps } = walkLeaderHashed(motifSeed, len, band);
    return { degrees, steps, theme_hash: H('BEAST_THEME_V1', ...degrees.map(enc)) };
  }

  const canonicalToMelodic = (m) => (m === 4 ? 1 : m === 5 ? 2 : m === 7 ? 5 : m === 8 ? 5 : m === 6 ? 2 : m === 26 ? 1 : 5);
  const SCALES = [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 9, 10], [0, 1, 3, 5, 7, 8, 10], [0, 2, 4, 6, 7, 9, 11], [0, 2, 4, 5, 7, 9, 10], [0, 2, 3, 5, 7, 8, 10]];
  // degree_to_keynum_sized: the i32 -> u32 and u32 -> u8 conversions panic in Cairo; throw here.
  function realize(deg, tonic, mode) {
    const du = deg + 70;
    if (du < 0) throw new Error('realize: degree below lattice');
    const total = tonic + 12 * Math.floor(du / 7) + SCALES[mode % 6][du % 7] - 120;
    if (total < 0 || total > 255) throw new Error('realize: keynum out of u8 range');
    return total;
  }
  const icPairSafe = (a, b) => Math.abs(a - b) % 12 !== 7;
  const transposedTonic = (t, s) => Math.max(24, Math.min(96, t + s));
  const voiceOffset = (v) => [0, -4, 3][v] ?? -8;
  function sectionTonicShift(p, s) {
    if (s === 1) return p.weakness === 0 ? 7 : p.weakness === 1 ? -5 : 6;
    if (s === 2) return p.use_inversion ? -3 : 3;
    if (s >= 4) return 2;
    return 0;
  }

  // countersubject.cairo with default config {start_offset 2, max_step 3, invertible}
  const genericClass = (a, b) => Math.abs(a - b) % 7;
  const consonant = (c) => [0, 2, 4, 5].includes(c % 7);
  const diatonicIcSafe = (a, b) => Math.abs(a - b) % 7 !== 4;
  function csCands(cur, subj, maxStep, ic, lo, hi) {
    const out = [];
    for (let m = -maxStep; m <= maxStep; m++) {
      const n = cur + m;
      if (n < lo || n > hi) continue;
      if (!consonant(genericClass(n, subj))) continue;
      if (ic && !diatonicIcSafe(n, subj)) continue;
      out.push(m);
    }
    return out;
  }
  function csValid(d, s, lo, hi) { return d >= lo && d <= hi && consonant(genericClass(d, s)) && diatonicIcSafe(d, s); }
  function generateCountersubject(subject, seed) {
    const hw = 7;
    let state = Number(BigInt(seed) % 256n);
    let start = 2;
    if (!csValid(start, subject[0], -hw, hw)) {
      let found = null;
      for (let r = 1; r <= 14 && found === null; r++) {
        if (csValid(2 + r, subject[0], -hw, hw)) found = 2 + r;
        else if (csValid(2 - r, subject[0], -hw, hw)) found = 2 - r;
      }
      if (found === null) throw new Error('no safe cs start');
      start = found;
    }
    const degrees = [start];
    for (let p = 1; p < subject.length; p++) {
      const cur = degrees[degrees.length - 1];
      let pool = csCands(cur, subject[p], 3, true, -hw, hw);
      if (pool.length === 0) pool = csCands(cur, subject[p], 14, true, -hw, hw);
      if (pool.length === 0) throw new Error('no ic cs candidate');
      const raw = (5 * state + 3) % 256;
      state = raw;
      degrees.push(cur + pool[raw % pool.length]);
    }
    return degrees;
  }

  function articulate(events, profile, ceiling) {
    const pattern = profile === ART_STACCATO ? [ART_STACCATO] : profile === ART_TENUTO ? [ART_TENUTO]
      : profile === ART_ACCENT ? [ART_ACCENT, ART_NORMAL, ART_NORMAL, ART_NORMAL]
        : profile === ART_PORTATO ? [ART_PORTATO] : [ART_NORMAL];
    const ceil = ceiling === 0 ? 127 : ceiling;
    return events.map((e, i) => {
      const art = pattern[i % pattern.length];
      let dur = art === ART_STACCATO ? (e.duration < 2 ? e.duration : Math.floor(e.duration / 2))
        : art === ART_PORTATO ? (Math.floor(e.duration * 3 / 4) || e.duration) : e.duration;
      if (dur < 60) dur = 60;
      let vel = art === ART_ACCENT ? Math.min(e.velocity + 20, ceil) : e.velocity;
      if (vel === 0) vel = 1; else if (vel > ceil) vel = ceil;
      return { ...e, duration: dur, velocity: vel, art };
    });
  }

  function buildSection(p, theme, s, offset, csSeed) {
    const out = [];
    const tonic = transposedTonic(p.tonic_keynum, sectionTonicShift(p, s));
    const mode = canonicalToMelodic(p.mode_id);
    const len = theme.degrees.length;
    for (let v = 0; v < p.voice_count; v++) {
      const entry = v === 0 ? 0 : v * p.stretto_lag;
      const off = voiceOffset(v);
      for (let i = 0; i < len; i++) {
        const base = theme.degrees[i];
        let deg = p.use_inversion && v === 1 ? 4 - base : base + off;
        if (v === 1 && i + entry < len) {
          const lp = realize(theme.degrees[i + entry], tonic, mode);
          if (!icPairSafe(lp, realize(deg, tonic, mode))) {
            deg += 1;
            if (!icPairSafe(lp, realize(deg, tonic, mode))) deg -= 2;
          }
        }
        out.push({ time: offset + (entry + i) * TIME_UNIT, duration: TIME_UNIT, pitch: realize(deg, tonic, mode), velocity: DEFAULT_VELOCITY, voice_id: v, section: s, role: 'canon' });
      }
    }
    if (p.use_countersubject) {
      const cs = generateCountersubject(theme.degrees, csSeed);
      cs.forEach((d, i) => out.push({ time: offset + i * TIME_UNIT, duration: TIME_UNIT, pitch: realize(d, tonic, mode), velocity: DEFAULT_VELOCITY, voice_id: p.voice_count, section: s, role: 'countersubject' }));
    }
    return articulate(out, p.articulation_profile, p.velocity_ceiling);
  }

  function buildForm(p, seed) {
    const seeds = deriveSeeds(seed);
    const theme = buildTheme(p, seeds.motif_seed);
    // theme + voice entries + a closing rest of two lags, rounded up to whole 4/4 bars (beast_score.cairo)
    const dur = Math.ceil((theme.degrees.length + p.stretto_lag * (p.voice_count + 1)) / 4) * 4 * TIME_UNIT;
    const csSeed = H(p.name_variant_id, p.species_id);
    const events = [];
    const sections = [];
    for (let s = 0; s < p.section_count; s++) {
      sections.push({ id: s, start: s * dur, tonic: transposedTonic(p.tonic_keynum, sectionTonicShift(p, s)), shift: sectionTonicShift(p, s) });
      events.push(...buildSection(p, theme, s, s * dur, csSeed));
    }
    const score_hash = H(paramsHash(p), theme.theme_hash, p.section_count, p.stretto_bucket, SCORE_VERSION);
    return { events, score_hash, theme, sections, section_ticks: dur, seeds };
  }

  function render(b, live) {
    const params = mapV3(b, live);
    const seed = soundSeed(b.id, b.prefix, b.suffix);
    const form = buildForm(params, seed);
    return { beast: b, live, params, seed, form, params_hash: paramsHash(params), state_hash: musicStateHash(b, live) };
  }

  function eventChecksum(events) {
    let c = 0n;
    events.forEach((e, j) => {
      const term = (BigInt(e.time) * 31n + BigInt(e.duration) * 7n + BigInt(e.pitch) * 131n + BigInt(e.velocity) * 17n + BigInt(e.voice_id) + 1n) * BigInt(j + 1);
      c = (c + term) % 1000000007n;
    });
    return c;
  }

  // Standard MIDI file (type 1, 480 ppq); one track per voice + tempo track.
  // Byte-identical to beast_form_to_smf_bytes in beast_v3_sound.cairo. The file lasts the whole form:
  // every section, each with its closing rest (BeastForm.length_ticks in Cairo).
  const formLength = (form) => form.section_ticks * form.sections.length;
  const toMidiFile = (result) => eventsToMidi(result.form.events, result.params.tempo_us, formLength(result.form));
  const eventsToMidi = (events, tempo, endTick = 0) => notesToMidi(events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]), tempo, endTick);


  // Building blocks reused by engine v2 (engine_v2.js). Not part of the public API.
  const internals = {
    H, enc, realize, articulate, generateCountersubject, paramsHash, deriveSeeds, sectionTonicShift,
    transposedTonic, canonicalToMelodic, mapV3, soundSeed, prefix2Policy, typeTierFamily,
    themeHash: (degrees) => H('BEAST_THEME_V1', ...degrees.map(enc)),
  };

  return {
    internals,
    eventsToMidi,
    decodeTokenId, encodeTokenId, genesisTokenId, soundSeed, soundDropRoll, hasSound, nameVariantId, mapV3, musicState,
    musicStateHash, paramsHash, buildForm, render, eventChecksum, toMidiFile, formLength, typeTierFamily, rankTier,
    FIELD_P,
  };
}

/** The full engine: core plus the BSN1 compact note stream (npm package, parity scripts). */
export function createEngine(opts) {
  const core = createCoreEngine(opts);
  return { ...core, ...createBsn(core, { grid: TIME_UNIT, baseVelocity: DEFAULT_VELOCITY, accent: ART_ACCENT }) };
}
