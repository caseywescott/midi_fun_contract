// Read Beast data that already exists onchain. Plain JSON-RPC over fetch (Node 20+, browsers).
//
// Nothing here writes or needs a wallet. Every read is a public view on a Provable Games contract.

import { keccak, poseidonHashMany } from '@scure/starknet';
import { genesisTier, genesisType } from './engine.js';

export const NETWORKS = {
  mainnet: {
    name: 'mainnet',
    rpc: 'https://api.cartridge.gg/x/starknet/mainnet',
    // Current (pre-V3) Beasts collection: sequential token numbers, `get_beast` returns traits.
    beasts: '0x046da8955829adf2bda310099a0063451923f02e648cf25a1203aac6335cf0e4',
    deathMountain: '0x79938ca37e3510a6a8b073243c8f30f5c687eff81d63e66197c56f7b85b558b',
    dungeon: '0x539d24dfdaa2866d975fa93db501b971c08786f2c88e719800be39903e43bbc',
    summit: '0x01aa95ea66e7e01acf7dc3fda8be0d8661230c4c36b0169e2bab8ab4d6700dfc',
  },
  sepolia: {
    name: 'sepolia',
    rpc: 'https://api.cartridge.gg/x/starknet/sepolia',
    // Beasts V3 test deployment (31 Jul 2026): 116-bit token IDs, community species registry.
    beastsV3: '0x01dac77837c6751777d917051a6e405967c5c75f46df5ab7c635e52819634bfd',
    registry: '0x06d46c98087a1246182c6cd8ef144ee0a67da6e6cc9e44e39aef08cf92d30045',
  },
};

const enc = new TextEncoder();
export const selector = (name) => '0x' + keccak(enc.encode(name)).toString(16);
const hex = (x) => '0x' + BigInt(x).toString(16);
const u256 = (x) => [BigInt(x) & ((1n << 128n) - 1n), BigInt(x) >> 128n];

export async function call(rpc, contract, fn, calldata = []) {
  const res = await fetch(rpc, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'starknet_call', params: { request: { contract_address: contract, entry_point_selector: selector(fn), calldata: calldata.map(hex) }, block_id: 'latest' } }),
  });
  const j = await res.json();
  if (!j.result) throw new Error(`${fn}: ${j.error?.message || 'rpc error'}${j.error?.data ? ' ' + JSON.stringify(j.error.data).slice(0, 200) : ''}`);
  return j.result.map(BigInt);
}

const decodeShortString = (felt) => { let s = ''; let x = BigInt(felt); while (x > 0n) { s = String.fromCharCode(Number(x & 255n)) + s; x >>= 8n; } return s; };
const entityHash = (b) => poseidonHashMany([BigInt(b.id), BigInt(b.prefix), BigInt(b.suffix)]);

/**
 * Summit stats for a current-collection token number. Summit keys Beasts by these numbers today;
 * a Beast that never entered Summit reads as zeros.
 * scars = revival_count (Summit deaths), summit_held_seconds = time held on the summit.
 */
export async function readSummit(tokenNumber, { network = NETWORKS.mainnet } = {}) {
  // LiveBeastStats layout: [token_id, current_health, bonus_health, bonus_xp, attack_streak,
  //   last_death_timestamp, revival_count, extra_lives, summit_held_seconds, ...]
  const r = (await call(network.rpc, network.summit, 'get_live_stats', [1, tokenNumber])).slice(1).map(Number);
  if (r[0] !== Number(tokenNumber)) return { revival_count: 0, summit_held_seconds: 0 };
  return { revival_count: r[6], summit_held_seconds: r[8] };
}

/**
 * A Beast from the current mainnet collection (token numbers 1..~86k), with every live stat the
 * composer uses. Tier and type come from the genesis tables, exactly as V3 will encode them.
 */
export async function readMainnetBeast(tokenNumber, { network = NETWORKS.mainnet } = {}) {
  const n = BigInt(tokenNumber);
  const g = (await call(network.rpc, network.beasts, 'get_beast', u256(n))).map(Number);
  const beast = { id: g[0], prefix: g[1], suffix: g[2], level: g[3], health: g[4], shiny: g[5], animated: g[6], tier: genesisTier(g[0]), beast_type: genesisType(g[0]) };
  const [rank, count, kills, collects, summit] = await Promise.all([
    call(network.rpc, network.beasts, 'get_beast_rank', u256(n)),
    call(network.rpc, network.beasts, 'get_species_count', [beast.id]),
    call(network.rpc, network.beasts, 'get_adventurers_killed', u256(n)),
    call(network.rpc, network.deathMountain, 'get_collectable_count', [network.dungeon, entityHash(beast)]),
    readSummit(n, { network }).catch(() => ({ revival_count: 0, summit_held_seconds: 0 })),
  ]);
  return {
    source: { network: network.name || 'custom', contract: network.beasts, tokenNumber: Number(n) },
    beast,
    live: {
      adventurers_killed: Number(kills[0]),
      // The mint itself is one collect; anything beyond it is a later defeat.
      scars: summit.revival_count + Math.max(0, Number(collects[0]) - 1),
      summit_held_seconds: summit.summit_held_seconds,
      rank: Number(rank[0]),
      species_count: Number(count[0]),
    },
  };
}

/**
 * A Beasts V3 token. Static traits decode offline from the token ID; rank, species count and
 * kills come from the V3 NFT. Summit does not key V3 IDs yet, so pass `summit` stats if you have
 * them from elsewhere. Community species names come from the registry.
 */
export async function readV3Beast(tokenId, { network = NETWORKS.sepolia, decodeTokenId, summit } = {}) {
  if (!decodeTokenId) throw new Error('pass decodeTokenId (from @koji/beast-sound)');
  const t = BigInt(tokenId);
  const beast = decodeTokenId(t);
  const safe = (p) => p.then((r) => Number(r[0])).catch(() => null);
  const [rank, count, kills] = await Promise.all([
    safe(call(network.rpc, network.beastsV3, 'get_beast_rank', u256(t))),
    safe(call(network.rpc, network.beastsV3, 'get_species_count', [beast.id])),
    safe(call(network.rpc, network.beastsV3, 'get_adventurers_killed', u256(t))),
  ]);
  let speciesName;
  if (beast.id > 75 && network.registry) {
    try { speciesName = decodeShortString((await call(network.rpc, network.registry, 'get_definition', [beast.id]))[0]); } catch { /* unregistered */ }
  }
  return {
    source: { network: network.name || 'custom', contract: network.beastsV3, tokenId: '0x' + t.toString(16) },
    beast,
    speciesName,
    live: {
      adventurers_killed: kills ?? 0,
      scars: summit?.revival_count ?? 0,
      summit_held_seconds: summit?.summit_held_seconds ?? 0,
      rank: beast.prefix === 0 ? 0 : rank ?? 1,
      species_count: count || 1,
    },
  };
}
