// Read the gallery Beasts' (and the Warlock's) kill and defeat records from Death Mountain on mainnet (the events the
// event-track prototype composes from) into onchain/.events-cache.json, git-ignored like the gallery
// cache. Up to 8 of each kind per Beast, newest first.
//   node onchain/events-cache.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { keccak } from '@scure/starknet';
import { poseidonHashMany } from '../src/index.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const RPC = process.env.RPC || 'https://api.cartridge.gg/x/starknet/mainnet';
const DM = '0x79938ca37e3510a6a8b073243c8f30f5c687eff81d63e66197c56f7b85b558b';
const DUNGEON = '0x539d24dfdaa2866d975fa93db501b971c08786f2c88e719800be39903e43bbc';
const PER_KIND = 8;
const sel = (n) => '0x' + keccak(new TextEncoder().encode(n)).toString(16);
async function call(fn, calldata) {
  for (let attempt = 0; attempt < 6; attempt++) {
    try {
      const r = await (await fetch(RPC, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method: 'starknet_call', params: { request: { contract_address: DM, entry_point_selector: sel(fn), calldata: calldata.map((x) => '0x' + BigInt(x).toString(16)) }, block_id: 'latest' } }) })).json();
      if (r.result) return r.result.map(BigInt);
      throw new Error(JSON.stringify(r.error).slice(0, 120));
    } catch (e) { if (attempt === 5) throw e; await new Promise((s) => setTimeout(s, 1500 * (attempt + 1))); }
  }
}

const cache = JSON.parse(readFileSync(here + '.gallery-cache.json', 'utf8'));
const gallery = JSON.parse(readFileSync(here + '../public/onchain/gallery.json', 'utf8'));
const beasts = { warlock: { id: 1, prefix: 57, suffix: 15 } };
for (const { token } of gallery) { const { beast } = cache[token]; beasts[token] = { id: Number(beast.id), prefix: Number(beast.prefix), suffix: Number(beast.suffix) }; }
const out = {};
const entries = Object.entries(beasts);
let done = 0, withDetail = 0, records = 0;
for (let i = 0; i < entries.length; i += 2) {
  await Promise.all(entries.slice(i, i + 2).map(async ([token, b]) => {
    const eh = poseidonHashMany([BigInt(b.id), BigInt(b.prefix), BigInt(b.suffix)]);
    const kills = Number((await call('get_entity_stats', [DUNGEON, eh]))[2]);
    const defeats = Number((await call('get_collectable_count', [DUNGEON, eh]))[0]);
    const ev = [];
    for (let k = Math.max(0, kills - PER_KIND); k < kills; k++) {
      const a = await call('get_adventurer_killed', [DUNGEON, eh, k]);
      ev.push({ kind: 1, index: k, adventurer_id: a[3].toString(), timestamp: Number(a[4]) });
    }
    for (let k = Math.max(0, defeats - PER_KIND); k < defeats; k++) {
      const c = await call('get_collectable', [DUNGEON, eh, k]);
      ev.push({ kind: 2, index: k, seed: c[3].toString(), adventurer_id: c[9].toString(), timestamp: Number(c[10]) });
    }
    for (const e of ev) { records++; if (e.seed && e.seed !== '0' || e.adventurer_id !== '0') withDetail++; }
    out[token] = { kills, defeats, events: ev.sort((x, y) => y.timestamp - x.timestamp || y.index - x.index) };
    done++;
  }));
  process.stdout.write(`\r${done}/${entries.length}`);
}
writeFileSync(here + '.events-cache.json', JSON.stringify(out));
console.log(`\n${entries.length} Beasts, ${records} event records (${withDetail} with adventurer or seed detail) -> onchain/.events-cache.json`);
