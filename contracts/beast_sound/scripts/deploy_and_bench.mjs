// Declare + deploy BeastSoundComposer, then measure each view for light → heaviest Beasts.
// node bench.mjs <rpc_url> <account_address> <private_key> [existing_contract_address]
import { RpcProvider, Account, json } from 'starknet';
import { readFileSync } from 'node:fs';
const [rpc, addr, pk, existing] = process.argv.slice(2);
const provider = new RpcProvider({ nodeUrl: rpc });
const account = new Account({ provider, address: addr, signer: pk });
const D = '/Volumes/Extreme SSD/Generative_Music_Series/midi_fun_contract/contracts/beast_sound/target/dev/';
let contractAddress = existing;
if (!contractAddress) {
  const sierra = json.parse(readFileSync(D + 'beast_sound_BeastSoundComposer.contract_class.json', 'utf8'));
  const casm = json.parse(readFileSync(D + 'beast_sound_BeastSoundComposer.compiled_contract_class.json', 'utf8'));
  const res = await account.declareAndDeploy({ contract: sierra, casm, constructorCalldata: ['0x' + Buffer.from('LS_V3_DEMO_SALT').toString('hex'), '500'] });
  contractAddress = res.deploy.contract_address;
  console.log('class_hash', res.declare.class_hash, '\ncontract', contractAddress);
}
const enc = (b) => BigInt(b.id) + (BigInt(b.prefix) << 64n) + (BigInt(b.suffix) << 71n) + (BigInt(b.level) << 76n) + (BigInt(b.health) << 92n) + (BigInt(b.shiny) << 108n) + (BigInt(b.animated) << 109n) + (BigInt(b.tier) << 110n) + (BigInt(b.beast_type) << 113n);
const cases = [
  ['Tier 5 common, fresh', { id: 47, prefix: 13, suffix: 6, level: 22, health: 60, shiny: 0, animated: 0, tier: 5, beast_type: 1 }, [0, 0, 0, 600, 1100]],
  ['Sorrow Peak Warlock (real, rank 1)', { id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 }, [2, 12, 0, 1, 954]],
  ['Tier 1, 3 sections', { id: 29, prefix: 20, suffix: 5, level: 150, health: 600, shiny: 1, animated: 0, tier: 1, beast_type: 1 }, [9, 25, 100 * 3600, 1, 1200]],
  ['HEAVIEST: Tier 1, 4 voices + countersubject, 5 sections, inverted', { id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 }, [200, 63, 500 * 3600, 1, 1243]],
];
for (const [label, b, live] of cases) {
  const tid = enc(b);
  const calldata = [tid & ((1n << 128n) - 1n), tid >> 128n, ...live].map((x) => '0x' + BigInt(x).toString(16));
  console.log(`\n== ${label}`);
  for (const fn of ['get_composition_params', 'get_music_state_hash', 'get_score_hash', 'get_score_notes', 'get_score_midi']) {
    const t0 = Date.now();
    let out = '';
    try { const r = await provider.callContract({ contractAddress, entrypoint: fn, calldata }); out = `call ok, ${r.length} felts` + (fn.startsWith('get_score_') && fn !== 'get_score_hash' ? ` (${BigInt(r[1])} bytes)` : ''); }
    catch (e) { out = 'CALL FAILED: ' + String(e.message).slice(0, 160); }
    const ms = Date.now() - t0;
    let gas = '';
    try { const est = await account.estimateInvokeFee({ contractAddress, entrypoint: fn, calldata }); gas = `max l2_gas ${Number(est.resourceBounds?.l2_gas?.max_amount ?? 0).toLocaleString()}`; }
    catch (e) { gas = 'estimate failed: ' + String(e.message).slice(0, 200); }
    console.log(`  ${fn.padEnd(24)} ${out.padEnd(36)} ${String(ms).padStart(5)} ms   ${gas}`);
  }
}
