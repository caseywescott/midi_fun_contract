// End to end on starknet-devnet: the patched Beasts V3 NFT (real art providers) → MidiSoundPage →
// BeastMidiProvider → NFT + Death Mountain state. Checks the sound-off bytes, the sound-on JSON and
// MIDI against the JS engine, a live-state change, and measures L2 gas, sizes and call latency.
//
//   starknet-devnet --seed 42 --port 5056 --accounts 1 --initial-balance 1000000000000000000000000000
//   STARKNET_JS=/path/to/node_modules/starknet node onchain/integration/e2e_devnet.mjs \
//     http://127.0.0.1:5056 <account> <private_key> <beasts-v3 target/dev with the patch built> <mock DM casm>
//
// The Death Mountain is beasts-v3's own test mock (`mock_death_mountain`: one global deaths/kills
// value, and it asserts the `dungeon` argument is its own address, the Beasts NFT convention). Its
// CASM comes from `universal-sierra-compiler compile-contract`. Prints a JSON report. With
// E2E_URI_DIR set, also saves each sound-on token_uri there (for `browser-check.mjs <files>`).
import { readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { encodeTokenId, engine, genesisBeast } from '../../src/index.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const repo = here + '../../../../';
const [rpc, accountAddress, privateKey, beastsDev, mockDmCasm] = process.argv.slice(2);
const { RpcProvider, Account, json, hash } = await import(pathToFileURL((process.env.STARKNET_JS || 'starknet') + '/dist/index.mjs').href);
const provider = new RpcProvider({ nodeUrl: rpc });
const account = new Account({ provider, address: accountAddress, signer: privateKey });

const hex = (x) => '0x' + BigInt(x).toString(16);
const u256 = (x) => [BigInt(x) & ((1n << 128n) - 1n), BigInt(x) >> 128n];
function ba(s) {
  const b = Buffer.from(s, 'utf8'), words = [];
  let i = 0;
  for (; i + 31 <= b.length; i += 31) words.push('0x' + b.subarray(i, i + 31).toString('hex'));
  const rest = b.subarray(i);
  return [words.length, ...words, rest.length ? '0x' + rest.toString('hex') : 0, rest.length];
}
function fromBa(felts) {
  const f = felts.map(BigInt), n = Number(f[0]);
  const bytes = (w, k) => Buffer.from(w.toString(16).padStart(k * 2, '0'), 'hex');
  return Buffer.concat([...f.slice(1, 1 + n).map((w) => bytes(w, 31)), bytes(f[1 + n], Number(f[2 + n]))]);
}
const post = async (method, params) => {
  const j = await (await fetch(rpc, { method: 'POST', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ jsonrpc: '2.0', id: 1, method, params }) })).json();
  if (j.error) throw new Error(JSON.stringify(j.error).slice(0, 400));
  return j.result;
};
const loadClass = (sierraPath, casmPath) => ({ contract: json.parse(readFileSync(sierraPath, 'utf8')), casm: json.parse(readFileSync(casmPath, 'utf8')) });
const classSize = (c) => ({ sierra_felts: c.contract.sierra_program.length, casm_felts: c.casm.bytecode.length });

async function declareDeploy(c, constructorCalldata) {
  const d = await account.declareIfNot(c);
  if (d.transaction_hash) await provider.waitForTransaction(d.transaction_hash);
  const r = await account.deployContract({ classHash: d.class_hash, constructorCalldata: constructorCalldata.map(hex) });
  await provider.waitForTransaction(r.transaction_hash);
  return r.contract_address;
}
async function invoke(contractAddress, entrypoint, calldata) {
  const r = await account.execute([{ contractAddress, entrypoint, calldata: calldata.map(hex) }]);
  const receipt = await provider.waitForTransaction(r.transaction_hash);
  if (receipt.execution_status && receipt.execution_status !== 'SUCCEEDED') throw new Error(`${entrypoint} reverted: ${receipt.revert_reason}`);
  return receipt;
}
async function call(contractAddress, entrypoint, calldata = []) {
  const t0 = performance.now();
  const r = await post('starknet_call', { request: { contract_address: contractAddress, entry_point_selector: hash.getSelectorFromName(entrypoint), calldata: calldata.map(hex) }, block_id: 'latest' });
  return { felts: r, ms: Math.round(performance.now() - t0) };
}
/** Exact L2 gas of calling `entrypoint` from the account (raw estimateFee, SKIP_VALIDATE). */
async function l2gas(contractAddress, entrypoint, calldata = []) {
  const nonce = await post('starknet_getNonce', { block_id: 'latest', contract_address: accountAddress });
  const zero = { max_amount: '0x0', max_price_per_unit: '0x0' };
  const cd = calldata.map(hex);
  const tx = { type: 'INVOKE', version: '0x3', sender_address: accountAddress, calldata: [hex(1), contractAddress, hash.getSelectorFromName(entrypoint), hex(cd.length), ...cd], signature: [], nonce, resource_bounds: { l2_gas: zero, l1_gas: zero, l1_data_gas: zero }, tip: '0x0', paymaster_data: [], account_deployment_data: [], nonce_data_availability_mode: 'L1', fee_data_availability_mode: 'L1' };
  try {
    const [est] = await post('starknet_estimateFee', { request: [tx], simulation_flags: ['SKIP_VALIDATE'], block_id: 'latest' });
    return Number(BigInt(est.l2_gas_consumed));
  } catch (e) { return `failed: ${e.message.slice(0, 200)}`; }
}

const SOURCES = ['Read', 'NotTracked', 'Unavailable', 'Retired'];
async function liveState(page, nft, tokenId) {
  const r = (await call(page.provider, 'get_live_state', [nft, ...u256(tokenId)])).felts.map((x) => Number(BigInt(x)));
  return { live: { adventurers_killed: r[0], scars: r[1], summit_held_seconds: r[2], rank: r[3], species_count: r[4] }, sources: { adventurers_killed: SOURCES[r[5]], scars: SOURCES[r[6]], summit_held_seconds: SOURCES[r[7]] }, complete: r[8] === 1 };
}
// Sound on: plain JSON from the page; sound off: the NFT's own base64 JSON.
const jsonOf = (uri) => (uri.startsWith('data:application/json;utf8,') ? JSON.parse(decodeURIComponent(uri.slice(27))) : JSON.parse(Buffer.from(uri.slice(uri.indexOf(',') + 1), 'base64').toString('utf8')));
const midiIn = (meta) => {
  const html = Buffer.from(meta.animation_url.slice(meta.animation_url.indexOf(',') + 1), 'base64').toString('utf8');
  return Uint8Array.from(Buffer.from(html.match(/id="midi">([^<]*)<\/script>/)[1].replace(/\s+/g, ''), 'base64'));
};

// ── classes ──────────────────────────────────────────────────────
const C = {
  nft: loadClass(beastsDev + 'beasts_nft_beasts_nft.contract_class.json', beastsDev + 'beasts_nft_beasts_nft.compiled_contract_class.json'),
  png: loadClass(beastsDev + 'beasts_nft_beast_png_regular_data.contract_class.json', beastsDev + 'beasts_nft_beast_png_regular_data.compiled_contract_class.json'),
  pngShiny: loadClass(beastsDev + 'beasts_nft_beast_png_shiny_data.contract_class.json', beastsDev + 'beasts_nft_beast_png_shiny_data.compiled_contract_class.json'),
  gif: loadClass(beastsDev + 'beasts_nft_beast_gif_regular_data.contract_class.json', beastsDev + 'beasts_nft_beast_gif_regular_data.compiled_contract_class.json'),
  gifShiny: loadClass(beastsDev + 'beasts_nft_beast_gif_shiny_data.contract_class.json', beastsDev + 'beasts_nft_beast_gif_shiny_data.compiled_contract_class.json'),
  dm: loadClass(beastsDev + 'beasts_nft_unittest_mock_death_mountain.test.contract_class.json', mockDmCasm),
  provider: loadClass(repo + 'contracts/beast_sound/target/dev/beast_sound_BeastMidiProvider.contract_class.json', repo + 'contracts/beast_sound/target/dev/beast_sound_BeastMidiProvider.compiled_contract_class.json'),
  page: loadClass(here + '../cairo/target/dev/beast_sound_page_MidiSoundPage.contract_class.json', here + '../cairo/target/dev/beast_sound_page_MidiSoundPage.compiled_contract_class.json'),
};
const report = { sizes: Object.fromEntries(Object.entries(C).filter(([k]) => ['nft', 'provider', 'page'].includes(k)).map(([k, c]) => [k, classSize(c)])), checks: {}, tokens: [] };

// ── deploy ───────────────────────────────────────────────────────
const art = [];
for (const k of ['png', 'pngShiny', 'gif', 'gifShiny']) art.push(await declareDeploy(C[k], []));
const deathMountain = await declareDeploy(C.dm, []);
const nft = await declareDeploy(C.nft, [...ba('Beasts'), ...ba('BEAST'), accountAddress, accountAddress, 500, ...art, deathMountain]);
await invoke(nft, 'set_dungeon_address', [accountAddress]);
const midiProvider = await declareDeploy(C.provider, [nft]);
const page = await declareDeploy(C.page, [midiProvider]);
const sys = { provider: midiProvider };

const BEASTS = [
  { label: 'Genesis Warlock (constructor mint)', tokenId: 0x7006400010000000000000000001n },
  { label: 'Sorrow Peak Warlock', mint: { id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0 } },
  { label: 'Tier 1 Brute, shiny + animated, level 255', mint: { id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1 } },
];
for (const b of BEASTS) {
  if (!b.mint) continue;
  const m = b.mint;
  await invoke(nft, 'mint', [accountAddress, m.id, m.prefix, m.suffix, m.level, m.health, m.shiny, m.animated]);
  b.tokenId = encodeTokenId(genesisBeast(m));
}

// ── sound off: today's bytes ─────────────────────────────────────
const offUris = {};
for (const b of BEASTS) {
  const r = await call(nft, 'token_uri', u256(b.tokenId));
  offUris[b.label] = fromBa(r.felts).toString('utf8');
  b.off = { uri_bytes: offUris[b.label].length, l2_gas: await l2gas(nft, 'token_uri', u256(b.tokenId)), call_ms: r.ms };
}

// ── sound on ─────────────────────────────────────────────────────
await invoke(nft, 'set_sound_page_address', [page]);
async function soundOn(b, tag) {
  const r = await call(nft, 'token_uri', u256(b.tokenId));
  const uri = fromBa(r.felts).toString('utf8');
  const meta = jsonOf(uri);
  const plain = jsonOf(offUris[b.label]);
  const state = await liveState(sys, nft, b.tokenId);
  const expected = Uint8Array.from(engine.toMidiFile(engine.render(engine.decodeTokenId(BigInt(b.tokenId)), state.live)));
  const embedded = midiIn(meta);
  const fromProvider = fromBa((await call(midiProvider, 'get_midi', u256(b.tokenId))).felts);
  const members = offUris[b.label] && JSON.stringify({ name: plain.name, description: plain.description, attributes: plain.attributes });
  return {
    tag, uri, meta, state, midi: embedded,
    row: {
      uri_bytes: uri.length, midi_bytes: embedded.length, call_ms: r.ms,
      json_same_as_off: meta.name === plain.name && meta.description === plain.description && meta.image === plain.image && JSON.stringify(meta.attributes) === JSON.stringify(plain.attributes),
      midi_matches_js_engine: Buffer.compare(Buffer.from(embedded), Buffer.from(expected)) === 0,
      midi_matches_provider: Buffer.compare(Buffer.from(embedded), fromProvider) === 0,
      live: state.live, sources: state.sources, complete: state.complete, members_bytes: members.length,
    },
  };
}
for (const b of BEASTS) {
  const on = await soundOn(b, 'on');
  b.on = on.row;
  b.on.l2_gas = await l2gas(nft, 'token_uri', u256(b.tokenId));
  b.on.provider_get_midi_l2_gas = await l2gas(midiProvider, 'get_midi', u256(b.tokenId));
  b.on.provider_get_live_state_l2_gas = await l2gas(midiProvider, 'get_live_state', [nft, ...u256(b.tokenId)]);
  // The page alone, with the members and SVG the NFT would hand it.
  const plain = offUris[b.label];
  const body = Buffer.from(plain.slice(plain.indexOf(',') + 1), 'base64').toString('utf8');
  const meta = JSON.parse(body);
  const image = `"image":${JSON.stringify(meta.image)},`;
  const membersStr = body.slice(1, -1).replace(image, '');
  const svgB64 = meta.image.slice('data:image/svg+xml;base64,'.length);
  b.on.page_token_uri_l2_gas = await l2gas(page, 'token_uri', [...ba(membersStr), ...ba(svgB64), nft, ...u256(b.tokenId)]);
  b.firstMidi = on.midi;
}

// ── live state changes reach the music ───────────────────────────
// 9 Death Mountain collects = 8 scars; then the heaviest history the composer distinguishes.
for (const [phase, deaths, kills] of [['after', 9, 40], ['max', 64, 200]]) {
  await invoke(deathMountain, 'set_values', [deaths, kills, 1727800000]);
  for (const b of BEASTS) {
    const s = await soundOn(b, phase);
    if (process.env.E2E_URI_DIR) writeFileSync(`${process.env.E2E_URI_DIR}/${b.label.replace(/\W+/g, '_')}.${phase}.txt`, s.uri);
    b[phase] = {
      live: s.row.live, sources: s.row.sources, uri_bytes: s.row.uri_bytes, midi_bytes: s.row.midi_bytes,
      midi_matches_js_engine: s.row.midi_matches_js_engine, midi_matches_provider: s.row.midi_matches_provider,
      midi_changed: Buffer.compare(Buffer.from(s.midi), Buffer.from(b.firstMidi)) !== 0,
      l2_gas: await l2gas(nft, 'token_uri', u256(b.tokenId)),
      provider_get_midi_l2_gas: await l2gas(midiProvider, 'get_midi', u256(b.tokenId)),
    };
  }
}

// ── sound off again: byte-identical to before ────────────────────
await invoke(nft, 'set_sound_page_address', [0]);
await invoke(deathMountain, 'set_values', [0, 0, 0]);
for (const b of BEASTS) b.off_again_identical = fromBa((await call(nft, 'token_uri', u256(b.tokenId))).felts).toString('utf8') === offUris[b.label];

report.addresses = { nft, deathMountain, midiProvider, page };
report.tokens = BEASTS.map(({ label, tokenId, off, on, after, max, off_again_identical }) => ({ label, tokenId: hex(tokenId), off, on, after, max, off_again_identical }));
console.log(JSON.stringify(report, null, 1));
