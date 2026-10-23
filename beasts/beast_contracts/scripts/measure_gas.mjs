// Exact L2 gas per view via raw starknet_estimateFee (SKIP_VALIDATE), plus a starknet_call round-trip.
// node gas.mjs <rpc_url> <account_address> <contract>
import { hash } from 'starknet';
const [rpc, sender, contract] = process.argv.slice(2);
const post = async (method, params) => { const j = await (await fetch(rpc, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) })).json(); if (j.error) throw new Error(JSON.stringify(j.error).slice(0, 300)); return j.result; };
const hex = (x) => '0x' + BigInt(x).toString(16);
// A PackableBeastV3 as calldata, in its Serde order (the views take the Beast, not a token ID).
const beastCalldata = (b) => [b.id, b.prefix, b.suffix, b.level, b.health, b.shiny, b.animated, b.tier, b.beast_type];
export const CASES = [
  ['Tier 5 common, fresh', { id: 47, prefix: 13, suffix: 6, level: 22, health: 60, shiny: 0, animated: 0, tier: 5, beast_type: 1 }, [0, 0, 0, 600, 1100]],
  ['Sorrow Peak Warlock (real)', { id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 }, [2, 12, 0, 1, 954]],
  ['Tier 1, 3 sections', { id: 29, prefix: 20, suffix: 5, level: 150, health: 600, shiny: 1, animated: 0, tier: 1, beast_type: 1 }, [9, 25, 360000, 1, 1200]],
  ['HEAVIEST (T1, 4v+CS, 5 sect)', { id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 }, [200, 63, 1800000, 1, 1243]],
];
const nonce = await post('starknet_getNonce', { block_id: 'latest', contract_address: sender });
const zero = { max_amount: '0x0', max_price_per_unit: '0x0' };
for (const [label, b, live] of CASES) {
  const cd = [...beastCalldata(b), ...live].map(hex);
  console.log(`\n== ${label}`);
  for (const fn of ['get_composition_params', 'get_music_state_hash', 'get_score_hash', 'get_score_notes', 'get_score_midi']) {
    const sel = hash.getSelectorFromName(fn);
    let call = '';
    const t0 = Date.now();
    try { const r = await post('starknet_call', { request: { contract_address: contract, entry_point_selector: sel, calldata: cd }, block_id: 'latest' }); call = `ok ${r.length} felts` + (fn === 'get_score_midi' ? `, ${BigInt(r[1])} B MIDI` : fn === 'get_score_notes' ? `, ${BigInt(r[1])} B BSN1` : ''); }
    catch (e) { call = 'FAILED ' + e.message.slice(0, 120); }
    const ms = Date.now() - t0;
    let gas = '';
    try {
      const tx = { type: 'INVOKE', version: '0x3', sender_address: sender, calldata: [hex(1), contract, sel, hex(cd.length), ...cd], signature: [], nonce, resource_bounds: { l2_gas: zero, l1_gas: zero, l1_data_gas: zero }, tip: '0x0', paymaster_data: [], account_deployment_data: [], nonce_data_availability_mode: 'L1', fee_data_availability_mode: 'L1' };
      const [est] = await post('starknet_estimateFee', { request: [tx], simulation_flags: ['SKIP_VALIDATE'], block_id: 'latest' });
      gas = Number(BigInt(est.l2_gas_consumed)).toLocaleString();
    } catch (e) { gas = 'n/a ' + e.message.slice(0, 120); }
    console.log(`  ${fn.padEnd(24)} ${call.padEnd(26)} ${String(ms).padStart(5)} ms   l2_gas ${gas}`);
  }
}
