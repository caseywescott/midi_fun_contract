// @koji/beast-sound: compose any Beast's canonical theme offchain.
//
// The only inputs are Beast data that already exists: the token's static traits (from the Beasts
// V3 token ID, or `get_beast` on the current collection) and its live stats (kills, Summit deaths,
// hours held on the Summit, species rank). No Sound contract is required.

import { poseidonHashMany } from '@scure/starknet';
import { createEngine, TABLES, genesisTier, genesisType, shortString } from './engine.js';
import { createEngineV2, DEFAULT_V2_OPTIONS, ORNAMENT_NAMES } from './engine_v2.js';

export {
  TABLES, genesisTier, genesisType, MODE_NAMES, FAMILY_NAMES, ORNAMENT_FAMILIES, ARTICULATION_NAMES,
} from './engine.js';

/** Bump only with a deliberate, announced change to the music; old versions stay installable. */
export const ENGINE_VERSION = 1;
export { encodeBsi, decodeBsi, isBsi, BSI_VERSION } from './bsi.js';
export { poseidonHashMany };
export const engine = createEngine({ poseidonHashMany });
/** Engine v2 (invertible canon + V2 ornaments). Opt in with composeBeast(..., { engineVersion: 2 }). */
export const engineV2 = createEngineV2(engine);
export { DEFAULT_V2_OPTIONS, ORNAMENT_NAMES };
export const { decodeBsn2, bsn2ToMidi } = engineV2;
export const { decodeTokenId, encodeTokenId, genesisTokenId, decodeBsn, bsnToMidi, eventsToMidi } = engine;

/** Build a full Beast from a genesis species id (1–75) and its per-token traits. */
export function genesisBeast({ id, prefix = 0, suffix = 0, level = 1, health = 100, shiny = 0, animated = 0 }) {
  if (id < 1 || id > 75) throw new Error('genesis species ids are 1–75; pass tier and beast_type for community species');
  return { id, prefix, suffix, level, health, shiny: shiny ? 1 : 0, animated: animated ? 1 : 0, tier: genesisTier(id), beast_type: genesisType(id) };
}

/** Display name, e.g. "Sorrow Peak Warlock". Community species need their registry name. */
export function beastName(beast, speciesName) {
  const sp = speciesName || (beast.id <= 75 ? TABLES.species[beast.id - 1] : `Community Beast #${beast.id}`);
  return beast.prefix === 0 ? sp : `${TABLES.prefixes[beast.prefix - 1]} ${TABLES.suffixes[beast.suffix - 1]} ${sp}`;
}

/** Fill unknown live stats with neutral values (no history, last place in a full species). */
export function normalizeLive(beast, live = {}) {
  const species_count = live.species_count ?? 1243;
  return {
    adventurers_killed: Number(live.adventurers_killed ?? 0),
    scars: Number(live.scars ?? 0),
    summit_held_seconds: Number(live.summit_held_seconds ?? 0),
    species_count,
    rank: live.rank ?? (beast.prefix === 0 ? 0 : species_count),
  };
}

/**
 * Compose a Beast's canonical theme.
 * @returns everything a player, game client or indexer needs; see index.d.ts.
 */
export function composeBeast(beast, live, { speciesName, engineVersion = 1, v2Options } = {}) {
  const l = normalizeLive(beast, live);
  if (engineVersion !== 1 && engineVersion !== 2) throw new Error(`unknown engine version ${engineVersion}`);
  const v2 = engineVersion === 2;
  const r = v2 ? engineV2.renderV2(beast, l, v2Options) : engine.render(beast, l);
  const { _ornament, _state, ...params } = r.params;
  const bsn = v2 ? engineV2.encodeBsn2(r) : engine.encodeBsn(r);
  const ticks = Math.max(...r.form.events.map((e) => e.time + e.duration));
  return {
    engineVersion: v2 ? 2 : ENGINE_VERSION,
    name: beastName(beast, speciesName),
    beast,
    live: l,
    tokenId: engine.encodeTokenId(beast),
    creatorTokenId: engine.genesisTokenId(beast.id, beast.tier, beast.beast_type),
    params,
    musicState: _state,
    events: r.form.events.map(({ time, duration, pitch, velocity, voice_id, section, role, ornament }) => ({ time, duration, pitch, velocity, voice: voice_id, section, role, ornament: ornament || 0 })),
    sections: r.form.sections,
    durationSeconds: (ticks / 480) * (params.tempo_us / 1e6),
    soundSeed: r.seed,
    motifHash: r.form.theme.theme_hash,
    paramsHash: r.params_hash,
    stateHash: r.state_hash,
    scoreHash: r.form.score_hash,
    midi: engine.eventsToMidi(r.form.events, params.tempo_us),
    ...(v2 ? { ornamentStyle: r.form.style, ornamentKinds: Object.fromEntries([...r.form.ornamentKinds].map(([k, n]) => [ORNAMENT_NAMES[k], n])), canonVoices: r.form.voiceCount, entryLag: r.form.entryLag } : {}),
    bsn,
    bsnFelts: engine.bytesToFelts(bsn),
  };
}

// ── Sound rarity drop, verifiable with no contract ─────────────────────────────
//
// 1. Announce a future Starknet block number N before launch.
// 2. salt = dropSaltFromBlockHash(hash of block N). Nobody knows it in advance; anyone can check it.
// 3. hasSound(beast, { salt }) is then a pure function every client computes identically.

export const DEFAULT_DROP_BPS = 500;

export function dropSaltFromBlockHash(blockHash) {
  return poseidonHashMany([shortString('BEAST_SOUND_SALT'), BigInt(blockHash)]);
}

export function soundDropRoll(beast, { salt }) {
  return engine.soundDropRoll(BigInt(salt), beast.id, beast.prefix, beast.suffix);
}

export function hasSound(beast, { salt, bps = DEFAULT_DROP_BPS }) {
  return engine.hasSound(BigInt(salt), bps, beast);
}
