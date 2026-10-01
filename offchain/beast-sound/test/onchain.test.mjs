// The onchain token_uri layout decodes like a normal one: valid JSON, the unchanged SVG as `image`,
// and an animation_url page holding the composer, the inputs and the same SVG.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { animationHtml, inputsHtml, storedSegment, tokenUri } from '../onchain/page.js';

const dir = new URL('../onchain/', import.meta.url);
const built = existsSync(new URL('dist/composer.js', dir));
const fromDataUri = (uri, type) => {
  const prefix = `data:${type};base64,`;
  assert.ok(uri.startsWith(prefix), `expected ${prefix}`);
  return Buffer.from(uri.slice(prefix.length), 'base64').toString('utf8');
};

test('token_uri decodes to valid JSON with image and animation_url', { skip: !built && 'run node onchain/build.mjs' }, () => {
  const js = readFileSync(new URL('dist/composer.js', dir), 'utf8');
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
