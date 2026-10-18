// The bench's case matrix and its expected-output table.
//
// Writes, from the matrix below:
//   bench/expected/cases.json   every case (group, contract, selector, inputs) and its checks
//   bench/src/expected.cairo    the expected (len, hash) of every check, as constants
//   bench/src/tests.cairo       one #[test] per case (one measured call each)
//   bench/src/fixtures.cairo    the page fixtures (MIDI files, members, SVG base64)
// and with --check writes nothing and fails if any of them differs from what it would write.
//
// Where each expected value comes from:
//   js               the independent JS engine (offchain/beast-sound): `genesisMidi` digested as
//                    scripts/genesis_parity.mjs does (bytesToFelts, poseidonHashMany), the page's
//                    `tokenUri` (onchain/page.js + onchain/dist/stored.b64), Buffer base64, and
//                    plain byte packing for the library probes
//   baseline-frozen  the Cairo output at the baseline commit, recorded once by
//                    `gas_bench.py freeze` into bench/expected/frozen.json
// frozen.json also records the baseline's value of every js check; this script fails if the two
// disagree. Neither source is ever taken from a candidate: rerunning this script reproduces the
// same table (the JS engine does not read Cairo), and `gas_bench.py freeze` refuses to overwrite
// frozen.json. See bench/README.md.
//
//   node bench/scripts/gen_expected.mjs           # write
//   node bench/scripts/gen_expected.mjs --check   # verify (gas_bench.py run does this)
// Needs `npm install` in offchain/beast-sound, and scarb (to format the Cairo it writes).
import { execFileSync } from 'node:child_process';
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

const BENCH = join(dirname(fileURLToPath(import.meta.url)), '..');
const SOUND = join(BENCH, '..', 'offchain', 'beast-sound');
if (!existsSync(join(SOUND, 'node_modules'))) {
  console.error('gen_expected: run `npm install` in offchain/beast-sound first');
  process.exit(2);
}
const { engine: E, poseidonHashMany, TABLES } = await import(join(SOUND, 'src', 'index.js'));
const { createEngineV11 } = await import(join(SOUND, 'src', 'engine_v11.js'));
const { genesisMidi, sampleTrackMidi, GENESIS_DEFAULTS, GENESIS_SWAPS } = await import(join(SOUND, 'src', 'lab.js'));
const { tokenUri, midiHtml } = await import(join(SOUND, 'onchain', 'page.js'));
const v11 = createEngineV11(E);
const STORED = readFileSync(join(SOUND, 'onchain', 'dist', 'stored.b64'), 'utf8');
const WARLOCK = JSON.parse(readFileSync(join(SOUND, 'onchain', 'fixtures', 'warlock_v3.json'), 'utf8'));
const CHECK = process.argv.includes('--check');

// ── digests (the Cairo side is bench/src/digest.cairo) ──────────────────────────────────────────
const hex = (x) => '0x' + BigInt(x).toString(16);
/** (byte_len, poseidon(bytesToFelts(bytes))): `bytes_digest` / `u8s_digest`. */
const bytesDigest = (bytes) => [bytes.length, hex(poseidonHashMany(E.bytesToFelts(Uint8Array.from(bytes))))];
/** (felt_count, poseidon(felts)) of a Serde serialization: `serde_digest`. */
const serdeDigest = (felts) => [felts.length, hex(poseidonHashMany(felts.map(BigInt)))];
const utf8 = (s) => Uint8Array.from(Buffer.from(s, 'utf8'));
const synthetic = (n) => Uint8Array.from({ length: n }, (_, i) => (i * 37 + 11) % 256);

// ── Beasts ──────────────────────────────────────────────────────────────────────────────────────
const speciesTier = (id) => Math.floor(((id - 1) % 25) / 5) + 1;
const speciesType = (id) => Math.floor((id - 1) / 25);
const SPECIES = TABLES.species;
const TYPES = ['Magic', 'Hunter', 'Brute'];
const pad3 = (n) => String(n).padStart(3, '0');
const sx = (shiny) => (shiny ? 's' : 'n');

const genesisCache = new Map();
/** The Genesis Track's bytes for species `id` (1..75) as the lab plays it. */
function genesisBytes(id, shiny) {
  const k = `${id}/${shiny}`;
  if (!genesisCache.has(k)) genesisCache.set(k, Uint8Array.from(genesisMidi(id, !!shiny, E, v11).midi));
  return genesisCache.get(k);
}
/** A community species' Genesis Track: the lab's `sampleTrackMidi` with the Genesis defaults on
 *  the token's own tier and type (what `genesisMidi` does for 1..75). Checked against the baseline. */
function communityBytes(b) {
  const g = { id: b.id, prefix: 0, suffix: 0, level: 1, health: 100, shiny: b.shiny, animated: 0, tier: b.tier, beast_type: b.beast_type };
  return Uint8Array.from(sampleTrackMidi(g, { species_count: 1 }, GENESIS_DEFAULTS, E, v11).midi);
}

const cairoBeast = (b) => `cases::beast(${b.id}, ${b.prefix}, ${b.suffix}, ${b.level}, ${b.health}, ${b.shiny}, ${b.animated}, ${b.tier}, ${b.beast_type})`;
const gb = (id, shiny) => ({ id, prefix: 0, suffix: 0, level: 1, health: 100, shiny, animated: 0, tier: speciesTier(id), beast_type: speciesType(id) });
const cairoLive = (l) => (l.summit ? `cases::live_summit(${l.kills}, ${l.scars}, ${l.summit}, ${l.rank}, ${l.count})` : `cases::live(${l.kills}, ${l.scars}, ${l.rank}, ${l.count})`);
const L = (kills, scars, rank, count, summit = 0) => ({ kills, scars, rank, count, summit });

const GAS_LIVE = L(0, 0, 1, 954); // the live state of the existing gas probes (beast_contracts tests)
const SORROW_PEAK_WARLOCK = { id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 };
const GENESIS_WARLOCK = { id: 1, prefix: 0, suffix: 0, level: 1, health: 100, shiny: 1, animated: 1, tier: 1, beast_type: 0 };
const HEAVIEST = { id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 };
// Agony Bane Gloomfang (community_species_plays_its_genesis_track) and two more community species.
const COMMUNITY = [
  { tag: 'c076', b: { id: 76, prefix: 1, suffix: 2, level: 10, health: 100, shiny: 0, animated: 1, tier: 3, beast_type: 1 }, live: L(7, 0, 1, 1), note: 'Agony Bane Gloomfang (community_species_plays_its_genesis_track): Hunter, tier 3' },
  { tag: 'c077', b: { id: 77, prefix: 0, suffix: 0, level: 1, health: 100, shiny: 1, animated: 0, tier: 1, beast_type: 2 }, live: L(0, 0, 1, 1), note: 'community species 77: Brute, tier 1, shiny (most sections and channels)' },
  { tag: 'c200', b: { id: 200, prefix: 0, suffix: 0, level: 1, health: 100, shiny: 0, animated: 0, tier: 5, beast_type: 0 }, live: L(0, 0, 1, 1), note: 'community species 200: Magic, tier 5' },
];

function speciesLabels(id, shiny) {
  const labels = [SPECIES[id - 1], TYPES[speciesType(id)], `tier ${speciesTier(id)}`, shiny ? 'shiny (mega)' : 'normal'];
  if (id === 68) labels.push('Yeti (ornaments, avalanche, rock tempo)');
  if (GENESIS_SWAPS[id]) labels.push(`swap: plays species ${GENESIS_SWAPS[id]}'s Genesis Track`);
  if (id === 33) labels.push('Nue: Phrygian');
  if (id === 21 && !shiny) labels.push('lightest Genesis file (1,406 bytes)');
  if (id === 32 && shiny) labels.push('largest Genesis file (7,197 bytes)');
  return labels;
}

// ── the matrix ──────────────────────────────────────────────────────────────────────────────────
// A case: { name, group, contract, selector, labels, call, checks: [{ key, kind, source, js }] }.
// `call` is the Cairo statement of its test; checks are passed to it in order as ("KEY", expected).
const cases = [];
const js = (fn) => ({ source: 'js', js: fn });
const jsOpt = (fn) => ({ source: 'js', optional: true, js: fn });
const frozen = () => ({ source: 'baseline-frozen' });
function add(c) {
  const checks = c.checks.map((k, i) => ({ key: (c.name + (k.suffix ? '_' + k.suffix : '')).toUpperCase(), ...k }));
  const args = checks.map((k) => `"${k.key}", expected::${k.key}`).join(', ');
  cases.push({ ...c, checks, test: `${c.call.replace('$CHECKS', args)};` });
}

// A: BeastMidiProvider.get_midi, every species x shiny (genesis_parity_range)
for (let id = 1; id <= 75; id++) for (const shiny of [0, 1]) {
  add({
    name: `a_get_midi_s${pad3(id)}_${sx(shiny)}`, group: 'A', contract: 'BeastMidiProvider', selector: 'get_midi',
    labels: speciesLabels(id, shiny),
    call: `cases::get_midi(cases::gbeast(${id}, ${shiny}), ${cairoLive(GAS_LIVE)}, $CHECKS)`,
    checks: [{ kind: 'bytes', ...js(() => bytesDigest(genesisBytes(id, shiny))) }],
  });
}
for (const c of COMMUNITY) {
  add({
    name: `a_get_midi_${c.tag}`, group: 'A', contract: 'BeastMidiProvider', selector: 'get_midi', labels: [c.note],
    call: `cases::get_midi(${cairoBeast(c.b)}, ${cairoLive(c.live)}, $CHECKS)`,
    checks: [{ kind: 'bytes', ...jsOpt(() => bytesDigest(communityBytes(c.b))) }],
  });
}
add({
  name: 'a_get_midi_named_warlock', group: 'A', contract: 'BeastMidiProvider', selector: 'get_midi',
  labels: ['Sorrow Peak Warlock (prefix 57, suffix 15, level 126, health 229), live(2, 12, 1, 954): plays the Warlock Genesis Track'],
  call: `cases::get_midi(${cairoBeast(SORROW_PEAK_WARLOCK)}, ${cairoLive(L(2, 12, 1, 954))}, $CHECKS)`,
  checks: [{ kind: 'bytes', ...js(() => bytesDigest(genesisBytes(1, 0))) }],
});
// A: get_midi_for
for (const [id, shiny] of [[21, 0], [1, 0], [32, 1]]) {
  add({
    name: `a_get_midi_for_s${pad3(id)}_${sx(shiny)}`, group: 'A', contract: 'BeastMidiProvider', selector: 'get_midi_for',
    labels: speciesLabels(id, shiny),
    call: `cases::get_midi_for(cases::gbeast(${id}, ${shiny}), ${cairoLive(GAS_LIVE)}, $CHECKS)`,
    checks: [{ kind: 'bytes', ...js(() => bytesDigest(genesisBytes(id, shiny))) }],
  });
}
// A: get_sound (MIDI from JS, settings frozen)
const SOUND_CASES = [
  ['s001_n', gb(1, 0), () => genesisBytes(1, 0), speciesLabels(1, 0)],
  ['s001_s', gb(1, 1), () => genesisBytes(1, 1), speciesLabels(1, 1)],
  ['s068_n', gb(68, 0), () => genesisBytes(68, 0), speciesLabels(68, 0)],
  ['s039_n', gb(39, 0), () => genesisBytes(39, 0), speciesLabels(39, 0)],
  ['s021_n', gb(21, 0), () => genesisBytes(21, 0), speciesLabels(21, 0)],
];
for (const [tag, b, bytes, labels] of SOUND_CASES) {
  add({
    name: `a_get_sound_${tag}`, group: 'A', contract: 'BeastMidiProvider', selector: 'get_sound', labels,
    call: `cases::get_sound(${cairoBeast(b)}, ${cairoLive(GAS_LIVE)}, $CHECKS)`,
    checks: [{ suffix: 'midi', kind: 'bytes', ...js(() => bytesDigest(bytes())) }, { suffix: 'settings', kind: 'serde', ...frozen() }],
  });
}
add({
  name: 'a_get_sound_c076', group: 'A', contract: 'BeastMidiProvider', selector: 'get_sound', labels: [COMMUNITY[0].note],
  call: `cases::get_sound(${cairoBeast(COMMUNITY[0].b)}, ${cairoLive(COMMUNITY[0].live)}, $CHECKS)`,
  checks: [{ suffix: 'midi', kind: 'bytes', ...jsOpt(() => bytesDigest(communityBytes(COMMUNITY[0].b))) }, { suffix: 'settings', kind: 'serde', ...frozen() }],
});
// A: get_settings: each type x shiny, the Yeti x shiny, the 39/40 swap
for (const [id, shiny] of [[1, 0], [1, 1], [26, 0], [26, 1], [51, 0], [51, 1], [68, 0], [68, 1], [39, 0], [40, 0]]) {
  add({
    name: `a_get_settings_s${pad3(id)}_${sx(shiny)}`, group: 'A', contract: 'BeastMidiProvider', selector: 'get_settings',
    labels: speciesLabels(id, shiny),
    call: `cases::get_settings(cases::gbeast(${id}, ${shiny}), $CHECKS)`,
    checks: [{ kind: 'serde', ...frozen() }],
  });
}
// A: get_live_state
for (const [tag, b, l, dm, label] of [
  ['genesis_warlock_dm', GENESIS_WARLOCK, L(0, 0, 0, 0), true, 'genesis Warlock (Sepolia 0x7006400010000000000000000001), Death Mountain set, all zero'],
  ['named_warlock_scars', SORROW_PEAK_WARLOCK, L(3, 4, 7, 954), true, 'Sorrow Peak Warlock with 3 kills, 4 scars, rank 7 (report_shows_sources)'],
  ['named_warlock_no_dm', SORROW_PEAK_WARLOCK, L(25, 6, 9, 954), false, 'Sorrow Peak Warlock, no Death Mountain address: Unavailable'],
  ['c076', COMMUNITY[0].b, COMMUNITY[0].live, true, 'community species 76: cached kills, scars NotTracked'],
]) {
  add({
    name: `a_get_live_state_${tag}`, group: 'A', contract: 'BeastMidiProvider', selector: 'get_live_state', labels: [label],
    call: `cases::get_live_state(${cairoBeast(b)}, ${cairoLive(l)}, ${dm}, $CHECKS)`,
    checks: [{ kind: 'serde', ...frozen() }],
  });
}
add({ name: 'a_get_collection', group: 'A', contract: 'BeastMidiProvider', selector: 'get_collection', labels: [], call: 'cases::get_collection($CHECKS)', checks: [{ kind: 'serde', ...frozen() }] });
add({ name: 'a_get_engine_version', group: 'A', contract: 'BeastMidiProvider', selector: 'get_engine_version', labels: [], call: 'cases::get_engine_version($CHECKS)', checks: [{ kind: 'serde', ...js(() => serdeDigest([1])) }] });
add({ name: 'a_owner', group: 'A', contract: 'BeastMidiProvider', selector: 'owner', labels: ['OpenZeppelin Ownable'], call: 'cases::owner($CHECKS)', checks: [{ kind: 'serde', ...js(() => serdeDigest([0x0a11ce])) }] });

// B: BeastSoundComposer, 7 views x 4 Beasts (beasts/beast_contracts/scripts/deploy_and_bench.mjs)
const COMPOSER_BEASTS = [
  ['tier5_fresh', { id: 47, prefix: 13, suffix: 6, level: 22, health: 60, shiny: 0, animated: 0, tier: 5, beast_type: 1 }, L(0, 0, 600, 1100), 'tier 5, fresh: live(0, 0, 600, 1100)'],
  ['sorrow_peak_warlock', SORROW_PEAK_WARLOCK, L(2, 12, 1, 954), 'Sorrow Peak Warlock (mainnet rank-1 Warlock): live(2, 12, 1, 954)'],
  ['tier1_3_sections', { id: 29, prefix: 20, suffix: 5, level: 150, health: 600, shiny: 1, animated: 0, tier: 1, beast_type: 1 }, L(9, 25, 1, 1200, 360000), 'tier 1, 3 sections: kills 9, scars 25, Summit 100 h, rank 1 of 1200'],
  ['heaviest', HEAVIEST, L(200, 63, 1, 1243), 'heaviest(): tier 1, 4 voices + countersubject, 5 sections; live(200, 63, 1, 1243)'],
];
const VIEWS = [['has_sound', 'HAS_SOUND'], ['get_composition_params', 'PARAMS'], ['get_music_state_hash', 'STATE_HASH'], ['get_score_hash', 'SCORE_HASH'], ['get_score_notes', 'SCORE_NOTES'], ['get_score_instructions', 'SCORE_INSTRUCTIONS'], ['get_score_midi', 'SCORE_MIDI']];
for (const [selector, view] of VIEWS) for (const [tag, b, l, label] of COMPOSER_BEASTS) {
  add({
    name: `b_${selector}_${tag}`, group: 'B', contract: 'BeastSoundComposer', selector, labels: [label],
    call: `cases::composer(cases::${view}, ${cairoBeast(b)}, ${cairoLive(l)}, $CHECKS)`,
    checks: [{ kind: 'serde', ...frozen() }],
  });
}

// C: MidiSoundPage.token_uri. Fixed MIDI: FixedMidiProvider's fixtures. Members and SVG: the real
// Sepolia genesis Warlock (offchain/beast-sound/onchain/fixtures/warlock_v3.json), or the small
// pair of the page's own tests.
const FIXTURES = [synthetic(31), genesisBytes(21, 0), genesisBytes(1, 0), genesisBytes(32, 1)];
const FIXTURE_NOTES = ['31 synthetic bytes ((i * 37 + 11) % 256)', 'Genesis Track of species 21 (1,406 bytes)', 'Genesis Track of species 1 (4,726 bytes)', 'Genesis Track of species 32, shiny (7,197 bytes)'];
const SMALL = { members: '"name":"Test","attributes":[]', svg_b64: Buffer.from("<svg xmlns='http://www.w3.org/2000/svg'/>").toString('base64') };
const ESCAPED_MEMBERS = WARLOCK.members + ',"note":"#1 of 75, 100% onchain, #beasts 50%"';
const PAGE_INPUTS = {
  warlock: [WARLOCK.members, WARLOCK.svg_b64, 'fixtures::warlock_members()', 'fixtures::warlock_svg_b64()', `real Warlock members (${WARLOCK.members.length} B) and svg_b64 (${WARLOCK.svg_b64.length} B)`],
  escaped: [ESCAPED_MEMBERS, WARLOCK.svg_b64, 'fixtures::escaped_members()', 'fixtures::warlock_svg_b64()', `Warlock members plus a member with '#' and '%' (${ESCAPED_MEMBERS.length} B), Warlock svg_b64`],
  small: [SMALL.members, SMALL.svg_b64, 'fixtures::small_members()', 'fixtures::small_svg_b64()', `small members (${SMALL.members.length} B) and svg_b64 (${SMALL.svg_b64.length} B) of the page's tests`],
};
const uriDigest = (input, midi) => bytesDigest(utf8(tokenUri(STORED, PAGE_INPUTS[input][0], PAGE_INPUTS[input][1], midi)));
for (const [tag, fixture, input] of [['l31', 0, 'warlock'], ['l1406', 1, 'warlock'], ['l4726', 2, 'warlock'], ['l7197', 3, 'warlock'], ['l1406_escaped', 1, 'escaped'], ['l1406_small', 1, 'small']]) {
  const [, , m, s, note] = PAGE_INPUTS[input];
  add({
    name: `c_token_uri_fixed_${tag}`, group: 'C', contract: 'MidiSoundPage', selector: 'token_uri', labels: [FIXTURE_NOTES[fixture], note],
    call: `cases::token_uri_fixed(${fixture}, ${m}, ${s}, $CHECKS)`,
    checks: [{ kind: 'bytes', ...js(() => uriDigest(input, FIXTURES[fixture])) }],
  });
}
for (const [id, shiny] of [[1, 0], [32, 1]]) {
  add({
    name: `c_token_uri_e2e_s${pad3(id)}_${sx(shiny)}`, group: 'C', contract: 'MidiSoundPage', selector: 'token_uri',
    labels: [...speciesLabels(id, shiny), 'end to end: the page calls the production BeastMidiProvider', PAGE_INPUTS.warlock[4]],
    call: `cases::token_uri_e2e(cases::gbeast(${id}, ${shiny}), ${cairoLive(GAS_LIVE)}, fixtures::warlock_members(), fixtures::warlock_svg_b64(), $CHECKS)`,
    checks: [{ kind: 'bytes', ...js(() => uriDigest('warlock', genesisBytes(id, shiny))) }],
  });
}
add({ name: 'c_get_midi_provider', group: 'C', contract: 'MidiSoundPage', selector: 'get_midi_provider', labels: [], call: 'cases::get_midi_provider($CHECKS)', checks: [{ kind: 'serde', ...frozen() }] });

// D: ScaleMidiProvider
for (const [tag, id] of [['t1', '1'], ['t42', '42'], ['t_warlock', '0x7006400010000000000000000001']]) {
  for (const selector of ['get_midi', 'get_midi_for']) {
    add({
      name: `d_scale_${selector}_${tag}`, group: 'D', contract: 'ScaleMidiProvider', selector, labels: [`token ${id}, collection 'BEASTS'`],
      call: `cases::scale_${selector}(${id}, $CHECKS)`,
      checks: [{ kind: 'bytes', ...frozen() }],
    });
  }
}

// E: library probes through BenchLib, BenchGenesis (T0) and BenchScore (T1)
for (const len of [0, 1, 30, 31, 32, 62, 1406, 7197]) {
  const l = String(len).padStart(4, '0');
  add({ name: `e_pack_input_l${l}`, group: 'E', contract: 'BenchLib', selector: 'pack_input', labels: [`input only: synthetic(${len})`], call: `cases::pack_input(${len}, $CHECKS)`, checks: [{ kind: 'serde', ...js(() => serdeDigest([len])) }] });
  add({ name: `e_bytes_to_byte_array_l${l}`, group: 'E', contract: 'BenchLib', selector: 'bytes_to_byte_array', labels: [`midi::pack::bytes_to_byte_array(synthetic(${len}))`], call: `cases::bytes_to_byte_array(${len}, $CHECKS)`, checks: [{ kind: 'bytes', ...js(() => bytesDigest(synthetic(len))) }] });
  add({ name: `e_to_felt252_array_l${l}`, group: 'E', contract: 'BenchLib', selector: 'to_felt252_array', labels: [`midi::pack::to_felt252_array(synthetic(${len}))`], call: `cases::to_felt252_array(${len}, $CHECKS)`, checks: [{ kind: 'serde', ...js(() => { const f = E.bytesToFelts(synthetic(len)); return serdeDigest([f.length, ...f]); }) }] });
}
FIXTURES.forEach((bytes, i) => {
  const l = String(bytes.length).padStart(4, '0');
  add({ name: `e_b64_input_l${l}`, group: 'E', contract: 'BenchLib', selector: 'b64_input', labels: [`input only: ${FIXTURE_NOTES[i]}`], call: `cases::b64_input(${i}, $CHECKS)`, checks: [{ kind: 'serde', ...js(() => serdeDigest([bytes.length])) }] });
  add({ name: `e_append_base64_l${l}`, group: 'E', contract: 'BenchLib', selector: 'append_base64', labels: [`midi_contracts::page::append_base64 of ${FIXTURE_NOTES[i]}`], call: `cases::append_base64(${i}, $CHECKS)`, checks: [{ kind: 'bytes', ...js(() => utf8ToDigest(Buffer.from(bytes).toString('base64'))) }] });
  add({ name: `e_midi_html_l${l}`, group: 'E', contract: 'BenchLib', selector: 'midi_html', labels: [`midi_contracts::page::midi_html of ${FIXTURE_NOTES[i]}`], call: `cases::midi_html(${i}, $CHECKS)`, checks: [{ kind: 'bytes', ...js(() => utf8ToDigest(midiHtml(bytes))) }] });
});
function utf8ToDigest(s) { return bytesDigest(utf8(s)); }
// Return-value costs of the stage probes: an Array<u8> of the T0 lengths (with the input-only row
// pack_input at the same length), an Array<felt252> of the T1 lengths.
add({ name: 'e_pack_input_l4726', group: 'E', contract: 'BenchLib', selector: 'pack_input', labels: ['input only: synthetic(4726)'], call: 'cases::pack_input(4726, $CHECKS)', checks: [{ kind: 'serde', ...js(() => serdeDigest([4726])) }] });
for (const len of [1406, 4726, 7197]) {
  add({ name: `e_u8_output_l${len}`, group: 'E', contract: 'BenchLib', selector: 'u8_output', labels: [`synthetic(${len}) returned as Array<u8>`], call: `cases::u8_output(${len}, $CHECKS)`, checks: [{ kind: 'bytes', ...js(() => bytesDigest(synthetic(len))) }] });
}
for (const n of [1073, 2203, 2763]) {
  const counting = Array.from({ length: n }, (_, i) => i);
  add({ name: `e_felt_input_n${n}`, group: 'E', contract: 'BenchLib', selector: 'felt_input', labels: [`input only: [0..${n}) as felts`], call: `cases::felt_input(${n}, $CHECKS)`, checks: [{ kind: 'serde', ...js(() => serdeDigest([n])) }] });
  add({ name: `e_felt_output_n${n}`, group: 'E', contract: 'BenchLib', selector: 'felt_output', labels: [`[0..${n}) returned as Array<felt252>`], call: `cases::felt_output(${n}, $CHECKS)`, checks: [{ kind: 'serde', ...js(() => serdeDigest([n, ...counting])) }] });
}
// Direct genesis_smf_bytes (stage T0 for 21, 1 and 32 shiny): lightest, heaviest, Yeti, swaps, Nue,
// community, both shiny states.
for (const [id, shiny] of [[21, 0], [21, 1], [1, 0], [1, 1], [32, 0], [32, 1], [28, 1], [68, 0], [68, 1], [39, 0], [40, 0], [33, 0]]) {
  add({
    name: `e_genesis_smf_bytes_s${pad3(id)}_${sx(shiny)}`, group: 'E', contract: 'BenchGenesis', selector: 'genesis_smf_bytes', labels: speciesLabels(id, shiny),
    call: `cases::genesis_smf_bytes(cases::gbeast(${id}, ${shiny}), $CHECKS)`,
    checks: [{ kind: 'bytes', ...js(() => bytesDigest(genesisBytes(id, shiny))) }],
  });
}
add({
  name: 'e_genesis_smf_bytes_c076', group: 'E', contract: 'BenchGenesis', selector: 'genesis_smf_bytes', labels: [COMMUNITY[0].note],
  call: `cases::genesis_smf_bytes(${cairoBeast(COMMUNITY[0].b)}, $CHECKS)`,
  checks: [{ kind: 'bytes', ...jsOpt(() => bytesDigest(communityBytes(COMMUNITY[0].b))) }],
});
// Stage T1: parameters + build_v11_score_with
for (const [id, shiny] of [[21, 0], [1, 0], [32, 1]]) {
  add({
    name: `e_genesis_score_s${pad3(id)}_${sx(shiny)}`, group: 'E', contract: 'BenchScore', selector: 'genesis_score', labels: speciesLabels(id, shiny),
    call: `cases::genesis_score(cases::gbeast(${id}, ${shiny}), $CHECKS)`,
    checks: [{ kind: 'serde', ...frozen() }],
  });
}

// M: measurement check. get_midi with an NFT whose get_beast_rank costs more (BurnBeasts): get_midi
// must grow by exactly what get_beast_rank grows (gas_bench.py checks it against a_get_midi_s021_n).
add({
  name: 'm_get_midi_s021_n_burn_rank', group: 'M', contract: 'BeastMidiProvider', selector: 'get_midi',
  labels: ['as a_get_midi_s021_n, with BurnBeasts as the NFT (get_beast_rank does 200 extra poseidon rounds)'],
  call: `cases::get_midi_burn(cases::gbeast(21, 0), ${cairoLive(GAS_LIVE)}, $CHECKS)`,
  checks: [{ kind: 'bytes', ...js(() => bytesDigest(genesisBytes(21, 0))) }],
});

// ── resolve expected values ─────────────────────────────────────────────────────────────────────
const names = new Set();
for (const c of cases) {
  if (names.has(c.name)) throw new Error(`duplicate case ${c.name}`);
  names.add(c.name);
}
const frozenPath = join(BENCH, 'expected', 'frozen.json');
const frozenFile = existsSync(frozenPath) ? JSON.parse(readFileSync(frozenPath, 'utf8')) : null;
const frozenValues = frozenFile ? frozenFile.values : {};
const problems = [];
const missing = [];
for (const c of cases) for (const k of c.checks) {
  const f = frozenValues[k.key];
  if (k.source === 'js') {
    const [len, hash] = k.js();
    if (f && (f[0] !== len || BigInt(f[1]) !== BigInt(hash))) {
      if (k.optional) {
        k.source = 'baseline-frozen';
        k.note = `JS sampleTrackMidi gives (${len}, ${hash}); the baseline Cairo differs, so frozen from the baseline`;
        k.len = f[0]; k.hash = hex(f[1]);
      } else problems.push(`${k.key}: js (${len}, ${hash}) but the baseline Cairo recorded (${f[0]}, ${hex(f[1])})`);
    } else { k.len = len; k.hash = hash; if (k.optional) k.note = 'JS sampleTrackMidi with the Genesis defaults on the token\'s tier and type'; }
    if (!f && frozenFile) missing.push(k.key);
  } else if (f) { k.len = f[0]; k.hash = hex(f[1]); }
  else { k.len = 0; k.hash = '0x0'; missing.push(k.key); }
}
if (frozenFile) {
  const known = new Set(cases.flatMap((c) => c.checks.map((k) => k.key)));
  for (const key of Object.keys(frozenValues)) if (!known.has(key)) problems.push(`frozen.json has ${key}, which no case checks`);
}
if (problems.length) { console.error('gen_expected: the JS reference and the baseline disagree:\n  ' + problems.join('\n  ')); process.exit(1); }

// ── outputs ─────────────────────────────────────────────────────────────────────────────────────
const HEADER = '// Generated by bench/scripts/gen_expected.mjs. Do not edit.\n';
const cairoStr = (s) => `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
function byteArrayFelts(bytes) {
  const buf = Buffer.from(bytes);
  const words = [];
  let i = 0;
  for (; i + 31 <= buf.length; i += 31) words.push('0x' + buf.subarray(i, i + 31).toString('hex'));
  const rest = buf.subarray(i);
  return [String(words.length), ...words, rest.length ? '0x' + rest.toString('hex') : '0', String(rest.length)];
}
const fixturesCairo = `${HEADER}//! Page fixtures: FixedMidiProvider's MIDI files (token ID 0 to 3) and the members and SVG base64 the
//! group C cases pass to \`token_uri\`.

/// MIDI fixture \`index\`: ${FIXTURE_NOTES.map((n, i) => `${i}: ${n}`).join('; ')}.
pub fn midi_fixture(index: u256) -> ByteArray {
    let felts: Array<felt252> = ${FIXTURES.map((b, i) => `if index == ${i} {
        array![${byteArrayFelts(b).join(', ')}]
    }`).join(' else ')} else {
        panic!("no MIDI fixture")
    };
    let mut span = felts.span();
    Serde::deserialize(ref span).unwrap()
}

/// The real Sepolia genesis Warlock's JSON members (offchain/beast-sound/onchain/fixtures/warlock_v3.json).
pub fn warlock_members() -> ByteArray {
    ${cairoStr(WARLOCK.members)}
}

/// The real Sepolia genesis Warlock's SVG, base64.
pub fn warlock_svg_b64() -> ByteArray {
    ${cairoStr(WARLOCK.svg_b64)}
}

/// The Warlock members plus a member with '#' and '%', which the page escapes.
pub fn escaped_members() -> ByteArray {
    ${cairoStr(ESCAPED_MEMBERS)}
}

/// The members of the page's own tests.
pub fn small_members() -> ByteArray {
    ${cairoStr(SMALL.members)}
}

pub fn small_svg_b64() -> ByteArray {
    ${cairoStr(SMALL.svg_b64)}
}
`;
const expectedCairo = `${HEADER}//! The expected (len, hash) of every check: \`js\` from the JS engine, \`baseline-frozen\` from the
//! baseline commit (bench/expected/frozen.json). See bench/expected/cases.json for each one's source.

${cases.flatMap((c) => c.checks.map((k) => `/// ${k.source}\npub const ${k.key}: (u32, felt252) = (${k.len}, ${k.hash});`)).join('\n')}
`;
const testsCairo = `${HEADER}//! One test per bench case (bench/expected/cases.json), each making one measured call.
use crate::{cases, expected, fixtures};

${cases.map((c) => `#[test]\nfn ${c.name}() {\n    ${c.test}\n}`).join('\n\n')}
`;
const casesJson = JSON.stringify({
  generator: 'bench/scripts/gen_expected.mjs',
  frozen_from: frozenFile ? frozenFile.baseline : null,
  cases: cases.map((c) => ({
    name: c.name, group: c.group, contract: c.contract, selector: c.selector, labels: c.labels,
    checks: c.checks.map((k) => ({ key: k.key, kind: k.kind, source: k.source, len: k.len, hash: k.hash, ...(k.note ? { note: k.note } : {}) })),
  })),
}, null, 2) + '\n';

// Cairo goes through `scarb fmt` (in bench/target, so nothing is written in --check mode).
const tmp = join(BENCH, 'target', 'gen_expected');
mkdirSync(tmp, { recursive: true });
const outputs = [
  ['src/fixtures.cairo', fixturesCairo, true], ['src/expected.cairo', expectedCairo, true],
  ['src/tests.cairo', testsCairo, true], ['expected/cases.json', casesJson, false],
];
let stale = 0;
for (const [rel, text, cairo] of outputs) {
  let out = text;
  if (cairo) {
    const t = join(tmp, rel.replace('/', '_'));
    writeFileSync(t, text);
    execFileSync('scarb', ['fmt', t], { cwd: BENCH, stdio: 'inherit' });
    out = readFileSync(t, 'utf8');
  }
  const path = join(BENCH, rel);
  const now = existsSync(path) ? readFileSync(path, 'utf8') : null;
  if (CHECK) {
    if (now !== out) { stale++; console.error(`gen_expected --check: ${rel} is not what the generator writes`); }
  } else if (now !== out) {
    mkdirSync(dirname(path), { recursive: true });
    writeFileSync(path, out);
    console.log(`wrote ${rel}`);
  }
}
const nChecks = cases.reduce((n, c) => n + c.checks.length, 0);
const bySource = cases.flatMap((c) => c.checks).reduce((m, k) => ({ ...m, [k.source]: (m[k.source] || 0) + 1 }), {});
console.log(`${cases.length} cases, ${nChecks} checks (${Object.entries(bySource).map(([s, n]) => `${n} ${s}`).join(', ')})`);
if (missing.length) console.log(`${missing.length} checks not in frozen.json yet${frozenFile ? '' : ' (no frozen.json: run gas_bench.py freeze at the baseline)'}`);
if (CHECK && (stale || missing.length)) process.exit(1);
