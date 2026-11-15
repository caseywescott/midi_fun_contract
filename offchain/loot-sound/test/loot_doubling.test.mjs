// A tune that follows itself may return with the lead doubled in harmony (loot_editions.js, `doubled`).
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

test('only a tune that follows itself is doubled, four times in five, at a third, fourth or fifth; its first pass has no harmony', () => {
  let repeats = 0, taken = 0; const kinds = new Set();
  for (const sp of BEASTS.slice(0, 10)) for (let e = 1; e <= 24; e++) for (const p of [1, 2, 3]) {
    const tr = E.editionTrack(sp, false, e, seed(p), null, false, null, false), form = tr.info.form.split(' (')[0].split(' '), d = tr.info.doubled;
    form.forEach((x, s) => { const again = s > 0 && x === form[s - 1]; if (again) { repeats++; if (d[s]) { taken++; kinds.add(d[s]); } } else assert.equal(d[s], 0, `edition ${e}: tune ${s + 1} does not repeat the one before`); });
    // the first pass of a repeated tune is plain: nothing in the descant's voice there
    { const ci = tr.info.channels.indexOf(1), span0 = tr.ticks / 4; if (ci >= 0) { const hs = notes(tr.bodies[1 + ci]); form.forEach((x, s) => { if (s < 3 && form[s + 1] === x) assert.equal(hs.filter(([t]) => t >= s * span0 && t < (s + 1) * span0).length, 0, `edition ${e}: the first pass of tune ${s + 1} has harmony`); }); } }
    if (!d.some(Boolean)) { assert.equal(tr.info.doubling, 'none'); continue; }
    // the doubled tune: a lead note has its harmony at the same tick, a third above or a fourth or fifth below
    // (measured where the lead has no grace notes, which start a note a step or two off)
    // (a chromatic bar's scale can stretch a step by a semitone, hence the wider bounds)
    const ch = tr.info.channels, lead = notes(tr.bodies[1 + ch.indexOf(0)]), harm = notes(tr.bodies[1 + ch.indexOf(1)]), span = tr.ticks / 4;
    d.forEach((iv, s) => { if (!iv) return; const from = s * span, to = from + span, at = new Map(harm.filter(([t]) => t >= from && t < to));
      for (const [t, pitch] of lead.filter(([t]) => t >= from && t < to)) { if (!at.has(t)) continue; const gap = at.get(t) - pitch; if (tr.info.ornaments === 'none') assert.ok(iv > 0 ? gap >= 3 && gap <= 5 : iv === -3 ? gap <= -4 && gap >= -7 : gap <= -6 && gap >= -9, `edition ${e}: harmony ${gap} semitones from the lead for step ${iv}`); }
      assert.ok(at.size >= 8, `edition ${e}: the doubled tune has its harmony (${at.size} notes)`); });
  }
  assert.ok(repeats > 50 && taken / repeats > 0.7 && taken / repeats < 0.9, `${taken} of ${repeats} repeats doubled`); // four in five
  assert.deepEqual([...kinds].sort((a, b) => a - b), [-4, -3, 2]);
});
