// The onchain token_uri layout decodes like a normal one: valid JSON, the unchanged SVG as `image`,
// and an animation_url page holding the composer, the inputs and the same SVG.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { animationHtml, inputsHtml, storedSegment, tokenUri } from '../onchain/page.js';
import { loadBuiltModules } from '../onchain/modules.mjs';

const dir = new URL('../onchain/', import.meta.url);
const built = existsSync(new URL('dist/composer.js', dir));
const fromDataUri = (uri, type) => {
  const prefix = `data:${type};base64,`;
  assert.ok(uri.startsWith(prefix), `expected ${prefix}`);
  return Buffer.from(uri.slice(prefix.length), 'base64').toString('utf8');
};

test('token_uri decodes to valid JSON with image and animation_url', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const js = loadBuiltModules(PAGES.inputs);
  const fx = JSON.parse(readFileSync(new URL('fixtures/warlock_v3.json', dir), 'utf8'));
  const stored = storedSegment(js);
  assert.equal(stored, readFileSync(new URL('dist/stored.b64', dir), 'utf8'));
  for (const live of [fx.live, { adventurers_killed: 412, scars: 7, summit_held_seconds: 86400, rank: 3, species_count: 1243 }]) {
    const meta = JSON.parse(fromDataUri(tokenUri(stored, fx.members, fx.svg_b64, fx.token_id, live), 'application/json'));
    assert.equal(meta.name, fx.name);
    const svg = Buffer.from(fx.svg_b64, 'base64').toString('utf8');
    assert.equal(fromDataUri(meta.image, 'image/svg+xml'), svg);
    assert.equal(fromDataUri(meta.animation_url, 'text/html'), animationHtml(js, fx.token_id, live, svg));
    assert.ok(Array.isArray(meta.attributes) && meta.attributes.length > 0);
  }
});

test('inputs line is padded to whole base64 groups', () => {
  for (const kills of [0, 9, 99, 12345, 2n ** 64n - 1n]) {
    const line = inputsHtml(1n, { adventurers_killed: kills, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1 });
    assert.equal(Buffer.byteLength(line) % 9, 0);
    assert.match(line, /^<script>BEAST_SOUND="1,\d+,0,0,0,1"<\/script> *<script type="text\/plain" id="art">$/);
  }
});

// The onchain library blob itself, run in a sandbox: compose + MIDI must equal the Cairo reference.
import vm from 'node:vm';
import { engine, encodeTokenId, composeBeast, genesisBeast, decodeTokenId, poseidonHashMany } from '../src/index.js';

function loadLibrary() {
  const js = readFileSync(new URL('dist/composer.js', dir), 'utf8');
  const window = { addEventListener() {} };
  vm.runInNewContext(js, { window, addEventListener() {}, matchMedia: undefined, URL, Blob, setTimeout, setInterval, clearInterval, BigInt, Math, Uint8Array });
  return window.BeastSound;
}

test('library blob composes and writes MIDI identical to Cairo', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const lib = loadLibrary();
  const golden = JSON.parse(readFileSync(new URL('../test/golden.json', import.meta.url), 'utf8'));
  for (const c of golden.cases) {
    const song = lib.compose(encodeTokenId(c.beast), c.live);
    assert.equal(BigInt(song.scoreHash).toString(), c.expected.score);
    const midi = lib.midi(song);
    assert.equal(String(midi.length), c.expected.midi_len);
    assert.equal(poseidonHashMany(engine.bytesToFelts(midi)).toString(), c.expected.midi_hash);
  }
});

test('library blob matches the package engine on 300 random Beasts', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const lib = loadLibrary();
  let x = 12345;
  const r = (n) => ((x = (x * 1103515245 + 12345) % 2147483648) % n);
  for (let i = 0; i < 300; i++) {
    const id = 1 + r(75);
    const genesis = r(10) === 0;
    const beast = genesisBeast({ id, prefix: genesis ? 0 : 1 + r(69), suffix: genesis ? 0 : 1 + r(18), level: 1 + r(300), health: 1 + r(1000), shiny: r(2), animated: r(2) });
    const ref = composeBeast(beast, { adventurers_killed: r(500), scars: r(20), summit_held_seconds: r(200000), rank: genesis ? 0 : 1 + r(1243), species_count: 1243 });
    const song = lib.compose(ref.tokenId, ref.live);
    assert.equal(BigInt(song.scoreHash), BigInt(ref.scoreHash));
    assert.deepEqual(lib.midi(song), ref.midi);
  }
});

test('v1 layers compose separately to the same song as compose()', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const { v1 } = loadLibrary();
  const golden = JSON.parse(readFileSync(new URL('../test/golden.json', import.meta.url), 'utf8'));
  for (const c of golden.cases) {
    const tokenId = encodeTokenId(c.beast);
    const traits = v1.beast.decode(tokenId);
    const song = v1.music.generate(v1.beast.params(traits, c.live), v1.beast.seed(traits));
    assert.equal(BigInt(song.scoreHash).toString(), c.expected.score);
    assert.deepEqual(song.notes, v1.compose(tokenId, c.live).notes);
    assert.equal(poseidonHashMany(engine.bytesToFelts(v1.midi.write(song))).toString(), c.expected.midi_hash);
  }
});

test('v1 midi.write takes any notes; fx transforms are pure', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const { v1 } = loadLibrary();
  const custom = v1.music.fromNotes([[0, 480, 60, 100, 0], [480, 480, 64, 100, 0], [0, 960, 48, 90, 1]], 500000);
  const bytes = v1.midi.write(custom);
  assert.equal(String.fromCharCode(...bytes.slice(0, 4)), 'MThd');
  assert.equal(bytes[11], 3); // tempo track + 2 voices
  assert.equal(custom.durationSeconds, 1);

  const a = v1.compose(encodeTokenId(genesisBeast({ id: 1 })), {});
  const b = v1.compose(encodeTokenId(genesisBeast({ id: 29 })), {});
  const before = JSON.stringify(a.notes);
  const up = v1.fx.transpose(a, 5);
  assert.deepEqual(up.notes.map((n) => n[2]), a.notes.map((n) => Math.min(127, n[2] + 5)));
  assert.equal(JSON.stringify(a.notes), before);
  assert.equal(v1.fx.tempo(a, 2).tempo_us, Math.round(a.tempo_us / 2));
  const voicesA = new Set(a.notes.map((n) => n[4])).size, voicesB = new Set(b.notes.map((n) => n[4])).size;
  const duet = v1.fx.layer(a, b);
  assert.equal(duet.notes.length, a.notes.length + b.notes.length);
  assert.equal(new Set(duet.notes.map((n) => n[4])).size, voicesA + voicesB);
  const suite = v1.fx.concat(a, b);
  assert.equal(suite.notes.length, a.notes.length + b.notes.length);
  assert.equal(Math.min(...suite.notes.slice(a.notes.length).map((n) => n[0])) % 1920, 0); // b starts on a bar
  assert.deepEqual(new Set(v1.fx.voices(a, [0]).notes.map((n) => n[4])), new Set([0]));
});

test('modules load separately: any dependency-ordered subset works, missing deps fail fast', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const mods = Object.fromEntries(loadBuiltModules().map((m) => [m.name, m.js]));
  const run = (names) => {
    const window = { addEventListener() {} };
    const ctx = { window, addEventListener() {}, matchMedia: undefined, URL, Blob, setTimeout, setInterval, clearInterval, BigInt, Math, Uint8Array };
    for (const n of names) vm.runInNewContext(mods[n], ctx);
    return window.BeastSound;
  };
  // MIDI alone: under 1.1 KB, works on any note list
  const onlyMidi = run(['midi']);
  assert.deepEqual([...onlyMidi.v1.modules], ['midi']);
  assert.equal(String.fromCharCode(...onlyMidi.v1.midi.write({ notes: [[0, 480, 60, 100, 0]], tempo_us: 500000 }).slice(0, 4)), 'MThd');
  // fx alone
  assert.equal(run(['fx']).v1.fx.transpose({ notes: [[0, 1, 60, 1, 0]], tempo_us: 1 }, 2).notes[0][2], 62);
  // Beast → song without any audio code
  const noAudio = run(['core', 'beast', 'music', 'midi']).v1;
  const traits = noAudio.beast.decode(encodeTokenId(genesisBeast({ id: 1 })));
  const song = noAudio.music.generate(noAudio.beast.params(traits, {}), noAudio.beast.seed(traits));
  const ref = composeBeast(genesisBeast({ id: 1 }), {});
  assert.equal(BigInt(song.scoreHash), BigInt(ref.scoreHash));
  assert.deepEqual(noAudio.midi.write(song), ref.midi);
  // a module whose dependency is missing throws before doing anything
  assert.throws(() => run(['beast']), /module beast needs module core/);
  // all modules == the all-in-one blob
  assert.deepEqual([...run(Object.keys(mods)).v1.modules], Object.keys(mods));
});

// ── notes page: the chain composes (BSN1 felts), the page only decodes and plays ──
import { notesHtml, tokenUriWithNotes, animationHtmlWithNotes } from '../onchain/page.js';
import { PAGES } from '../onchain/modules.mjs';

test('notes module plays chain-composed felts: same notes and MIDI as Cairo, no composer loaded', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const mods = Object.fromEntries(loadBuiltModules().map((m) => [m.name, m.js]));
  const window = { addEventListener() {} };
  const ctx = { window, addEventListener() {}, matchMedia: undefined, URL, Blob, setTimeout, setInterval, clearInterval, BigInt, Math, Uint8Array };
  for (const n of PAGES.notes) vm.runInNewContext(mods[n], ctx);
  const v1 = window.BeastSound.v1;
  assert.equal(v1.core, undefined); // no engine on a notes page
  const golden = JSON.parse(readFileSync(new URL('../test/golden.json', import.meta.url), 'utf8'));
  for (const c of golden.cases) {
    const ref = composeBeast(c.beast, c.live);
    const felts = ref.bsnFelts; // == Cairo get_score_notes (golden bsn_hash)
    assert.equal(poseidonHashMany(felts).toString(), c.expected.bsn_hash); // the felts Cairo emits
    for (const input of [felts, felts.map((f) => '0x' + f.toString(16)).join(',')]) {
      const song = v1.notes.decode(input);
      assert.deepEqual(Array.from(song.notes, (n) => Array.from(n)), ref.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice]));
      assert.equal(song.tempo_us, ref.params.tempo_us);
      assert.equal(poseidonHashMany(engine.bytesToFelts(v1.midi.write(song))).toString(), c.expected.midi_hash);
    }
  }
});

test('notes token_uri decodes to the notes page', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const fx = JSON.parse(readFileSync(new URL('fixtures/warlock_v3.json', dir), 'utf8'));
  const mods = loadBuiltModules(PAGES.notes);
  const stored = storedSegment(mods);
  assert.equal(stored, readFileSync(new URL('dist/stored-notes.b64', dir), 'utf8'));
  const felts = composeBeast(decodeTokenId(BigInt(fx.token_id)), fx.live).bsnFelts;
  const meta = JSON.parse(fromDataUri(tokenUriWithNotes(stored, fx.members, fx.svg_b64, felts), 'application/json'));
  const svg = Buffer.from(fx.svg_b64, 'base64').toString('utf8');
  assert.equal(fromDataUri(meta.image, 'image/svg+xml'), svg);
  assert.equal(fromDataUri(meta.animation_url, 'text/html'), animationHtmlWithNotes(mods, felts, svg));
  assert.equal(Buffer.byteLength(notesHtml(felts)) % 9, 0);
});
