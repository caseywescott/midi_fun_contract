// A second lead on some B or C tunes, and slower styles often taken faster (loot_editions.js).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LOOT_BEASTS } from '../src/loot_beasts.js';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';
import * as E from '../src/loot_editions.js';

const U64 = (1n << 64n) - 1n;
const seed = (n) => { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); };
const BEASTS = LOOT_BEASTS.map((b) => ({ ...b, ...SPECIES.find((s) => s.id === b.id) }));
function ons(body) { const out = []; let i = 0, t = 0, run = 0; while (i < body.length) { let d = 0, b; do { b = body[i++]; d = (d << 7) | (b & 127); } while (b & 128); t += d; let s = body[i]; if (s & 128) i++; else s = run; if (s === 0xff) { i++; let l = 0; do { b = body[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; } run = s; const ty = s & 0xf0; if (ty === 0xc0 || ty === 0xd0) { i++; continue; } if (ty === 0x90 && body[i + 1]) out.push(t); i += 2; } return out; }

test('about two purchases in five give a B or C tune to a second lead, and only that tune', () => {
  let n = 0, alt = 0; const which = new Set();
  for (const sp of BEASTS.filter((_, i) => i % 3 === 0)) for (let e = 1; e <= STYLES.length; e++) for (const p of [1, 2, 3, 4]) {
    const S = STYLES[E.editionGenome(e).style], bar = S.num * (1920 / S.den), tr = E.editionTrack(sp, false, e, seed(p), null, false, null, false), k = tr.info.altKind, at = tr.info.channels.indexOf(E.ALT_CHANNEL);
    n++; assert.equal(at >= 0, k >= 0);
    const kinds = tr.info.form.split(' (')[0].split(' ').map((x) => (x === "A'" ? 3 : x.charCodeAt(0) - 65)), where = (t) => kinds[Math.floor(t / (8 * bar))];
    const lead = ons(tr.bodies[1 + tr.info.channels.indexOf(0)]);
    if (k < 0) { assert.equal(tr.info.secondLead, 'none'); continue; }
    alt++; which.add(k); assert.ok(k === 1 || k === 2); assert.ok(kinds.includes(k));
    const second = ons(tr.bodies[1 + at]);
    assert.ok(second.length > 4 && second.every((t) => where(t) === k), 'the second lead plays only its tune');
    assert.ok(lead.every((t) => where(t) !== k), 'the lead rests in that tune');
  }
  assert.ok(alt > n * 0.28 && alt < n * 0.5, `${alt} of ${n} have a second lead`);
  assert.deepEqual([...which].sort(), [1, 2]);
});

test('slower styles are taken faster by widely varying amounts; faster styles are not', () => {
  for (const S of STYLES) {
    const e = 1 + STYLES.indexOf(S), g = E.editionGenome(e), steps = new Set();
    for (const sp of BEASTS.slice(0, 12)) for (let p = 1; p <= 6; p++) { const tr = E.editionTrack(sp, false, e, seed(p)); steps.add(tr.info.quicker); assert.ok(tr.info.bpm >= Math.round((g.bpm - 4) * (100 + tr.info.quicker) / 100) - 1 && tr.info.bpm <= Math.round((g.bpm + 4) * (100 + tr.info.quicker) / 100) + 1); }
    if (S.bpm[1] <= E.SLOW_TOP) assert.ok(steps.size >= 5 && Math.max(...steps) >= 34, `${S.key}: tempo steps ${[...steps]}`); else assert.deepEqual([...steps], [0], `${S.key} keeps its tempo`);
  }
});
