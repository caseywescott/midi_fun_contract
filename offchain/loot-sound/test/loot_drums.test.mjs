// The drums at the end of a tune: a fill over the last half bar, or a cut (the bar silent), or the pattern.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LOOT_BEASTS } from '../src/loot_beasts.js';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';
import * as E from '../src/loot_editions.js';

const U64 = (1n << 64n) - 1n;
const seed = (n) => { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); };
const BEASTS = LOOT_BEASTS.map((b) => ({ ...b, ...SPECIES.find((s) => s.id === b.id) }));
function ons(body) { const out = []; let i = 0, t = 0, run = 0; while (i < body.length) { let d = 0, b; do { b = body[i++]; d = (d << 7) | (b & 127); } while (b & 128); t += d; let s = body[i]; if (s & 128) i++; else s = run; if (s === 0xff) { i++; let l = 0; do { b = body[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; } run = s; const ty = s & 0xf0; if (ty === 0xc0 || ty === 0xd0) { i++; continue; } if (ty === 0x90 && body[i + 1]) out.push([t, body[i], body[i + 1]]); i += 2; } return out; }

test('a tune ends with a fill 7 times in 20 and a cut 5 in 20; a cut bar has no drums, a fill runs to the bar line', () => {
  const tally = [0, 0, 0];
  for (const sp of BEASTS.filter((_, i) => i % 3 === 0)) for (let e = 1; e <= STYLES.length; e++) for (const p of [1, 2, 3, 4]) {
    const S = STYLES[E.editionGenome(e).style], bar = S.num * (1920 / S.den), tr = E.editionTrack(sp, false, e, seed(p), null, false, null, false), at = tr.info.channels.indexOf(9);
    if (at < 0) { assert.deepEqual(tr.info.drumEnds, [0, 0, 0, 0]); continue; }
    const hits = ons(tr.bodies[at + 1]), usual = hits.filter(([t]) => t < bar).length; // the pattern's hits in a bar
    tr.info.drumEnds.forEach((k, s) => {
      tally[k]++;
      const from = (8 * s + 7) * bar, inBar = hits.filter(([t]) => t >= from && t < from + bar), late = inBar.filter(([t]) => t >= from + (bar >> 1));
      if (k === 2) assert.equal(inBar.length, 0, `${S.key}: a cut bar has drums`);
      else if (k === 1) { const count = Math.floor((bar >> 1) / 120); assert.equal(late.length, count); assert.ok(late.every(([, n, v]) => E.DRUM_FILL.includes(n) && v >= E.DRUM_FILL_VEL[0] && v <= E.DRUM_FILL_VEL[0] + E.DRUM_FILL_VEL[1])); assert.equal(late.at(-1)[0], from + bar - 120); }
      else assert.equal(inBar.length, usual, `${S.key}: an ordinary last bar plays the pattern`);
    });
  }
  const n = tally[0] + tally[1] + tally[2];
  assert.ok(tally[1] > n * 0.28 && tally[1] < n * 0.42 && tally[2] > n * 0.19 && tally[2] < n * 0.31, `${tally} of ${n}`);
});
