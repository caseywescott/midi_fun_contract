#!/usr/bin/env node
// beast-sound: write any Beast's canonical theme as a MIDI file, offchain.
//
//   beast-sound mainnet 52918 -o warlock.mid
//   beast-sound v3 0x2e0064000a081000000000000004c            (Beasts V3, Sepolia by default)
//   beast-sound compose --species 1 --prefix 57 --suffix 15 --level 126 --health 229 --kills 40
//
// Common flags: -o <file.mid>  --bsn <file.bsn>  --json  --salt <felt> --bps <n>  --rpc <url>
//               --engine 2   (ornamented invertible canon; default 1)

import { writeFileSync } from 'node:fs';
import { composeBeast, decodeTokenId, genesisBeast, hasSound, soundDropRoll, MODE_NAMES, FAMILY_NAMES, TABLES } from '../src/index.js';
import { NETWORKS, readMainnetBeast, readV3Beast } from '../src/chain.js';

const argv = process.argv.slice(2);
const flag = (name, short) => { const i = argv.findIndex((a) => a === `--${name}` || (short && a === `-${short}`)); return i >= 0 ? argv[i + 1] : undefined; };
const has = (name) => argv.includes(`--${name}`);
const num = (name, d) => (flag(name) === undefined ? d : Number(flag(name)));
const usage = () => {
  console.log(`usage:
  beast-sound mainnet <token-number>           read a Beast from the current mainnet collection
  beast-sound v3 <token-id> [--network sepolia|mainnet] [--nft <addr>]
  beast-sound compose --species <1-75> [--prefix 1-69 --suffix 1-18] [--level N --health N]
                      [--shiny] [--animated] [--tier 1-5 --type 0-2 for species 76+]
                      [--kills N --scars N --summit-hours N --rank N --count N]
options: -o <file.mid> write MIDI · --bsn <file> write compact bytes (BSN1, or BSN2 for --engine 2)
         --engine 1|2 (2 = ornamented invertible canon) · --json print everything
         --salt <felt> --bps <n> evaluate the Sound drop (default 500 bps)`);
  process.exit(1);
};

async function load() {
  const [cmd, arg] = argv;
  if (cmd === 'mainnet' && arg) {
    const net = { ...NETWORKS.mainnet, ...(flag('rpc') ? { rpc: flag('rpc') } : {}) };
    return readMainnetBeast(arg, { network: net });
  }
  if (cmd === 'v3' && arg) {
    const base = flag('network') === 'mainnet' ? { ...NETWORKS.mainnet } : { ...NETWORKS.sepolia };
    if (flag('nft')) base.beastsV3 = flag('nft');
    if (flag('rpc')) base.rpc = flag('rpc');
    return readV3Beast(arg, { network: base, decodeTokenId });
  }
  if (cmd === 'compose') {
    const id = num('species');
    if (!id) usage();
    const traits = { id, prefix: num('prefix', 0), suffix: num('suffix', 0), level: num('level', 1), health: num('health', 100), shiny: has('shiny') ? 1 : 0, animated: has('animated') ? 1 : 0 };
    const beast = id <= 75 ? genesisBeast(traits) : { ...traits, tier: num('tier', 3), beast_type: num('type', 0) };
    const live = { adventurers_killed: num('kills', 0), scars: num('scars', 0), summit_held_seconds: num('summit-hours', 0) * 3600, species_count: num('count', 1243) };
    if (flag('rank') !== undefined) live.rank = num('rank');
    return { source: { network: 'none' }, beast, live };
  }
  usage();
}

const got = await load();
const song = composeBeast(got.beast, got.live, { speciesName: got.speciesName, engineVersion: num('engine', 1) });
const p = song.params, st = song.musicState;
const hex = (x) => '0x' + BigInt(x).toString(16);

if (has('json')) {
  console.log(JSON.stringify({ ...song, midi: undefined, bsn: undefined, bsnHex: Buffer.from(song.bsn).toString('hex') }, (k, v) => (typeof v === 'bigint' ? hex(v) : v), 2));
} else {
  const tonic = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'][p.tonic_keynum % 12] + (Math.floor(p.tonic_keynum / 12) - 1);
  console.log(`${song.name}  (${TABLES.types[song.beast.beast_type]} · Tier ${song.beast.tier})`);
  console.log(`  source        ${got.source.network}${got.source.tokenNumber ? ' #' + got.source.tokenNumber : ''}${got.source.tokenId ? ' ' + got.source.tokenId : ''}`);
  console.log(`  V3 token ID   ${hex(song.tokenId)}`);
  console.log(`  live          ${song.live.adventurers_killed} kills · ${song.live.scars} scars · ${Math.floor(song.live.summit_held_seconds / 3600)} h on Summit · rank ${song.live.rank}/${song.live.species_count}`);
  console.log(`  music         ${tonic} ${MODE_NAMES[p.mode_id] || p.mode_id} · ${FAMILY_NAMES[`${p.canon_config_id}/${p.profile_id}`] || 'config ' + p.canon_config_id}`);
  console.log(`                ${p.voice_count} voices${p.use_countersubject ? ' + countersubject' : ''} · ${p.section_count} sections · stretto ${p.stretto_lag} · ${p.use_inversion ? 'inverted (scarred) · ' : ''}${Math.round(60e6 / p.tempo_us)} bpm`);
  console.log(`  engine        v${song.engineVersion}${song.engineVersion === 2 ? ` · ${song.canonVoices}-voice invertible canon, entries every ${song.entryLag} · ${song.ornamentStyle} ornaments` : ''}`);
  if (song.ornamentKinds) console.log(`  ornaments     ${Object.entries(song.ornamentKinds).sort((a, b) => b[1] - a[1]).map(([k, n]) => `${k} ×${n}`).join(', ')}`);
  console.log(`  length        ${song.events.length} notes · ${song.durationSeconds.toFixed(1)} s · MIDI ${song.midi.length} B · BSN${song.engineVersion} ${song.bsn.length} B`);
  console.log(`  score_hash    ${hex(song.scoreHash)}`);
  console.log(`  state_hash    ${hex(song.stateHash)}  (crown ${st.is_crown}, kill bucket ${st.kill_bucket}, scar bucket ${st.defeat_bucket})`);
  if (flag('salt')) {
    const opts = { salt: flag('salt'), bps: num('bps', 500) };
    console.log(`  sound drop    ${hasSound(song.beast, opts) ? 'YES' : 'no'} (roll ${soundDropRoll(song.beast, opts)} vs ${opts.bps})`);
  }
}
if (flag('o', 'o')) { writeFileSync(flag('o', 'o'), song.midi); console.error(`wrote ${flag('o', 'o')}`); }
if (flag('bsn')) { writeFileSync(flag('bsn'), song.bsn); console.error(`wrote ${flag('bsn')}`); }
