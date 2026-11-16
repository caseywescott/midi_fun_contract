// A track that ends on the tune it began with (A or A') plays it a third higher that last time
// (loot_editions.js, `grand`): same rhythm, every note within a third or so above the first tune's, the
// last note the tonic. Other forms are untouched.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LOOT_BEASTS } from '../src/loot_beasts.js';
import { SPECIES } from '../src/loot_species.js';
import * as E from '../src/loot_editions.js';

const U64 = (1n << 64n) - 1n;
const seed = (n) => { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); };
const BEASTS = LOOT_BEASTS.map((b) => ({ ...b, ...SPECIES.find((s) => s.id === b.id) }));
// a track body's notes as [start tick, pitch]
function notes(body) { const out = []; let i = 0, t = 0, run = 0; while (i < body.length) { let d = 0, b; do { b = body[i++]; d = (d << 7) | (b & 127); } while (b & 128); t += d; let s = body[i]; if (s & 128) i++; else s = run; if (s === 0xff) { i++; let l = 0; do { b = body[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; } run = s; const ty = s & 0xf0; if (ty === 0xc0 || ty === 0xd0) { i++; continue; } if (ty === 0x90 && body[i + 1]) out.push([t, body[i]]); i += 2; } return out; }

test('the last tune is a third higher when it is the first tune come back, and only then', () => {
  let grand = 0, plain = 0, compared = 0;
  for (const sp of BEASTS.slice(0, 10)) for (let e = 1; e <= 30; e++) for (const p of [1, 2, 3]) {
    const tr = E.editionTrack(sp, false, e, seed(p), null, false, null, false), form = tr.info.form.split(' (')[0].split(' ');
    const back = form[3] === 'A' || form[3] === "A'";
    assert.equal(tr.info.grand, back, `edition ${e}: form ${form.join(' ')}`);
    if (!back) { plain++; continue; }
    grand++;
    // the lead of tune 4 against tune 1 (where neither is on the second lead's channel, and with no grace notes)
    if (tr.info.ornaments !== 'none' || form[3] !== 'A') continue;
    const span = tr.ticks / 4, lead = notes(tr.bodies[1 + tr.info.channels.indexOf(0)]), first = lead.filter(([t]) => t < span), last = lead.filter(([t]) => t >= 3 * span).map(([t, x]) => [t - 3 * span, x]);
    assert.deepEqual(last.map((n) => n[0]), first.map((n) => n[0]), `edition ${e}: the rhythm is the first tune's`);
    // two scale steps up is 3 or 4 semitones; a note moved onto the chord may be a step either side of that
    // (a chromatic bar's scale can stretch a step, hence the wider bounds)
    last.slice(0, -1).forEach(([t, x], i) => { const up = x - first[i][1]; assert.ok(up >= 0 && up <= 7, `edition ${e}: ${up} semitones above the first tune at tick ${t}`); });
    const mean = last.slice(0, -1).reduce((a, [, x], i) => a + x - first[i][1], 0) / (last.length - 1);
    assert.ok(mean > 2.5 && mean < 4.5, `edition ${e}: ${mean.toFixed(2)} semitones higher on average`);
    assert.equal((last.at(-1)[1] - first.at(-1)[1]) % 12, 0, `edition ${e}: the last note is still the tonic`);
    compared++;
  }
  console.log(`${grand} tracks end on their first tune (${compared} compared note for note), ${plain} do not`);
  assert.ok(grand > 100 && plain > 100 && compared > 20);
});

test("the accompaniment's octave doubling sits below the root on about one purchase in three, never when it is already an octave lower", () => {
  let below = 0, n = 0;
  for (const sp of BEASTS.slice(0, 10)) for (let e = 1; e <= 15; e++) for (let p = 1; p <= 6; p++) {
    const i = E.editionTrack(sp, false, e, seed(p), null, false, null, false).info; n++;
    if (i.octaveBelow) { below++; assert.equal(i.accompLow, false); }
  }
  console.log(`${below} of ${n} tracks have the octave below`);
  assert.ok(below / n > 0.22 && below / n < 0.4);
});
