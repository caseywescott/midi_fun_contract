// The optional BeatSync module (onchain/beatsync): its GIF decoder on real animated Beast art, and the
// audible-tick clock it reads from tinysynth.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

function load() {
  const ctx = {};
  vm.runInNewContext(readFileSync(new URL('../onchain/beatsync/beatsync.js', import.meta.url), 'utf8'), ctx);
  return ctx.BeatSync;
}
const gifOf = (token) => {
  const svg = readFileSync(new URL(`../public/onchain/beasts/${token}.svg`, import.meta.url), 'utf8');
  return Buffer.from(/data:image\/gif;base64,([A-Za-z0-9+/=]+)/.exec(svg)[1], 'base64');
};

test('decodes animated Beast GIFs into full-size frames with their delays', () => {
  const B = load();
  for (const token of ['1949', '3553', '8303', '16615', '58886']) {
    const gif = B.decodeGif(gifOf(token));
    assert.equal(gif.width, 32);
    assert.equal(gif.height, 32);
    assert.ok(gif.frames.length >= 2, `${token}: ${gif.frames.length} frames`);
    for (const f of gif.frames) {
      assert.equal(f.rgba.length, 32 * 32 * 4);
      assert.ok(f.delay >= 20, `${token}: delay ${f.delay}`);
      assert.ok(f.rgba.some((v, i) => i % 4 === 3 && v === 255), `${token}: frame has opaque pixels`);
    }
    // frames differ: it is an animation
    assert.ok(gif.frames.some((f) => !f.rgba.every((v, i) => v === gif.frames[0].rgba[i])));
  }
});

test('audibleTick: scheduled tick minus look-ahead, wrapped at the loop, null when stopped', () => {
  const B = load();
  const synth = (o) => ({ playing: 1, actx: { currentTime: 10 }, tick2Time: 0.01, playTick: 500, playTime: 10.5, maxTick: 1000, loopEnd: 0, ...o });
  assert.equal(B.audibleTick(synth()), 450);                       // 0.5 s ahead = 50 ticks
  assert.equal(B.audibleTick(synth({ playTick: 20 })), 970);       // just past the loop point
  assert.equal(B.audibleTick(synth({ loopEnd: 400 })), 50);
  assert.equal(B.audibleTick(synth({ playing: 0 })), null);
  assert.equal(B.audibleTick(null), null);
});

test('attach returns null when the art has no animated GIF', () => {
  const B = load();
  assert.equal(B.attach({ img: {}, svg: '<svg><image href="data:image/png;base64,AAAA"/></svg>' }), null);
});
