// Beast layer: a Beasts V3 token and its live stats → musical parameters and a seed.
// Nothing here makes sound; pair it with music.generate, or feed the params to your own generator.
import { engine } from './core.js';

/** Token ID (packed 116-bit) → { id, prefix, suffix, level, health, shiny, animated, tier, beast_type }. */
export const decode = (tokenId) => engine.decodeTokenId(BigInt(tokenId));

/** Fill missing live stats with neutral values (no history; last place in a full species). */
export function live(stats = {}, traits) {
  const count = Number(stats.species_count ?? 1243);
  return {
    adventurers_killed: Number(stats.adventurers_killed ?? 0),
    scars: Number(stats.scars ?? 0),
    summit_held_seconds: Number(stats.summit_held_seconds ?? 0),
    species_count: count,
    rank: Number(stats.rank ?? (traits && traits.prefix === 0 ? 0 : count)),
  };
}

/** Traits + live stats → composition params (mode, tonic, voices, sections, stretto, tempo, …). */
export const params = (traits, stats) => engine.mapV3(traits, live(stats, traits));

/** The Beast's sound seed: poseidon('BEAST_SOUND_V1', id, prefix, suffix). Fixed for life. */
export const seed = (traits) => engine.soundSeed(traits.id, traits.prefix, traits.suffix);
