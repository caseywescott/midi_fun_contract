// The onchain token_uri layout decodes like a normal one: valid JSON, the unchanged SVG as `image`,
// and an animation_url page holding the TinySynth player, the token's exact MIDI, and the same SVG.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { engine } from '../src/index.js';
import { TINYCHIP_ONCHAIN } from '../onchain/tinychip/config.mjs';
import { BEATSYNC_ONCHAIN } from '../onchain/beatsync/config.mjs';
import { animationHtml, midiHtml, pageHtml, parseTokenUri, storedSegment, tokenUri } from '../onchain/page.js';

const dir = new URL('../onchain/', import.meta.url);
const built = existsSync(new URL('dist/player.js', dir)) && existsSync(new URL('dist/tinysynth.min.js', dir));
const fromDataUri = (uri, type) => {
  const prefix = `data:${type};base64,`;
  assert.ok(uri.startsWith(prefix), `expected ${prefix}`);
  return Buffer.from(uri.slice(prefix.length), 'base64').toString('utf8');
};
// The stored script, as onchain/build.mjs assembles it (TinyChip and BeatSync included when their switches are on).
const pageScript = () => [
  readFileSync(new URL('dist/tinysynth.min.js', dir), 'utf8').trim(),
  ...(TINYCHIP_ONCHAIN ? [readFileSync(new URL('dist/tinychip.min.js', dir), 'utf8').trim()] : []),
  ...(BEATSYNC_ONCHAIN ? [readFileSync(new URL('dist/beatsync.min.js', dir), 'utf8').trim()] : []),
  readFileSync(new URL('dist/player.js', dir), 'utf8').trim(),
].join('\n');
const synthetic = (n) => Uint8Array.from({ length: n }, (_, i) => (i * 37 + 11) % 256);

test('token_uri decodes to valid JSON with image, animation_url and the exact MIDI', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const js = pageScript();
  const fx = JSON.parse(readFileSync(new URL('fixtures/warlock_v3.json', dir), 'utf8'));
  const stored = storedSegment(js);
  assert.equal(stored, readFileSync(new URL('dist/stored.b64', dir), 'utf8'));
  const beast = engine.decodeTokenId(BigInt(fx.token_id));
  const midis = [
    Uint8Array.from(engine.toMidiFile(engine.render(beast, fx.live))),
    Uint8Array.from(engine.toMidiFile(engine.render(beast, { adventurers_killed: 412, scars: 7, summit_held_seconds: 0, rank: 0, species_count: 1243 }))),
    synthetic(0), synthetic(1), synthetic(2), synthetic(31),
  ];
  for (const midi of midis) {
    const uri = tokenUri(stored, fx.members, fx.svg_b64, midi);
    const meta = parseTokenUri(uri);
    assert.equal(uri.indexOf(stored) % 31, 0); // the stored page lands on a 31-byte word boundary
    assert.equal(meta.name, fx.name);
    const svg = Buffer.from(fx.svg_b64, 'base64').toString('utf8');
    assert.equal(fromDataUri(meta.image, 'image/svg+xml'), svg);
    const html = fromDataUri(meta.animation_url, 'text/html');
    assert.equal(html, animationHtml(js, midi, svg));
    // The browser's view: the MIDI block holds the provider's bytes, the art block the SVG.
    const block = html.match(/<script type="text\/plain" id="midi">([^<]*)<\/script>/);
    assert.ok(block, 'midi block');
    assert.deepEqual(Uint8Array.from(Buffer.from(block[1].replace(/\s+/g, ''), 'base64')), midi);
    assert.ok(html.endsWith('<script type="text/plain" id="art">' + svg));
    assert.ok(Array.isArray(meta.attributes) && meta.attributes.length > 0);
  }
});

test('the fixed page is whole words and the MIDI block whole base64 groups', () => {
  for (const js of ['', 'x', 'xy', 'void 0;</script>']) {
    const html = pageHtml(js);
    assert.equal(Buffer.byteLength(html) % 279, 0); // 9 × 31: base64 is whole groups and whole words
    assert.ok(html.trimEnd().endsWith('</script><script type="text/plain" id="midi">'));
    assert.equal(html.split('</script><script').length, 2, 'script text cannot close its own tag');
  }
  for (let n = 0; n <= 200; n++) {
    const d = midiHtml(synthetic(n));
    assert.equal(Buffer.byteLength(d) % 3, 0);
    assert.match(d, /^[A-Za-z0-9+/=]* *<\/script><script type="text\/plain" id="art">$/);
  }
});

test('plain-JSON token_uri: % and # are escaped, the rest is raw', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const js = readFileSync(new URL('dist/tinysynth.min.js', dir), 'utf8').trim() + '\n' + readFileSync(new URL('dist/player.js', dir), 'utf8').trim();
  const uri = tokenUri(storedSegment(js), '"name":"100% #1 Beast","description":"a\\nb","attributes":[]', 'PHN2Zy8+', synthetic(40));
  assert.ok(uri.startsWith('data:application/json;utf8,{"name":"100%25 %231 Beast"'));
  assert.ok(!uri.includes('#'));
  assert.equal(parseTokenUri(uri).name, '100% #1 Beast');
});
