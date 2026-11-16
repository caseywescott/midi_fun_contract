// The editions' intro (loot_editions.js, `introBars`): on half the purchases, one to four bars before the
// first tune, at most INTRO_MAX_S seconds long, which it leaves note for note as it was.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { LOOT_BEASTS } from '../src/loot_beasts.js';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';
import * as E from '../src/loot_editions.js';

const U64 = (1n << 64n) - 1n;
const seed = (n) => { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); };
const BEASTS = LOOT_BEASTS.map((b) => ({ ...b, ...SPECIES.find((s) => s.id === b.id) }));
// a track body's events as [tick, status, data1, data2], meta events left out
function events(body) { const out = []; let i = 0, t = 0, run = 0; while (i < body.length) { let d = 0, b; do { b = body[i++]; d = (d << 7) | (b & 127); } while (b & 128); t += d; let s = body[i]; if (s & 128) i++; else s = run; if (s === 0xff) { i++; let l = 0; do { b = body[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; } run = s; const ty = s & 0xf0; if (ty === 0xc0 || ty === 0xd0) { out.push([t, s, body[i], 0]); i++; continue; } out.push([t, s, body[i], body[i + 1]]); i += 2; } return out; }

test('half the purchases have an intro of one to four bars, at most four and a half seconds, and the tunes after it are unchanged', () => {
  let n = 0, withIntro = 0, runs = 0; const lengths = new Set(), layers = new Set();
  for (const sp of BEASTS.filter((_, i) => i % 3 === 0)) for (let e = 1; e <= STYLES.length; e++) for (const p of [1, 2, 3, 4]) {
    const S = STYLES[E.editionGenome(e).style], bar = S.num * (1920 / S.den), a = E.editionTrack(sp, false, e, seed(p)), plain = E.editionTrack(sp, false, e, seed(p), null, false, null, false);
    n++; assert.equal(plain.info.introBars, 0); assert.equal(plain.info.intro, 'none'); assert.equal(plain.ticks, 32 * bar);
    const N = a.info.introBars, shift = a.info.introTicks;
    assert.equal(shift, N * bar); assert.equal(a.ticks, 32 * bar + shift);
    if (!N) { assert.deepEqual(a.bodies, plain.bodies); continue; }
    withIntro++; lengths.add(N); assert.ok(N >= (S.num === 2 ? 2 : 1) && N <= 4, `${S.key}: an intro of ${N} bars`);
    const secs = shift / 480 * 60 / a.bpm; assert.ok(secs <= E.INTRO_MAX_S + 0.01 || N === (S.num === 2 ? 2 : 1), `${S.key}: an intro of ${secs.toFixed(1)} s`);
    for (const x of a.info.intro.split(': ')[1].split(', ')) layers.add(x.replace(/ (up|down) /, ' '));
    assert.deepEqual(a.info.channels, plain.info.channels, 'the intro brings in no part the track does not have');
    a.info.channels.forEach((ch, k) => {
      const ev = events(a.bodies[k + 1]), was = events(plain.bodies[k + 1]);
      // from the first tune on: the same events, later by the intro (the drums also get the crash that ends it)
      const isNote = (x) => (x[1] & 0xf0) === 0x90 || (x[1] & 0xf0) === 0x80;
      const after = ev.filter((x) => isNote(x) && x[0] >= shift).map(([t, ...r]) => [t - shift, ...r]);
      // a note ended exactly where the tune starts belongs to the intro
      const tuneOnly = []; const open = new Map(); for (const x of ev.filter(isNote)) { if (x[0] < shift) { if ((x[1] & 0xf0) === 0x90 && x[3]) open.set(x[2], 1); else open.delete(x[2]); } }
      assert.deepEqual(after.filter((x, i) => !(x[0] === 0 && (x[1] & 0xf0) === 0x80 && i < after.findIndex((y) => (y[1] & 0xf0) === 0x90))), was.filter(isNote), `${S.key} edition ${e}: channel ${ch} differs after the intro`);
      // in the intro: notes only, each ended before the tune begins
      const sounding = new Map();
      for (const [t, s, p1, p2] of ev.filter((x) => x[0] < shift || (x[0] === shift && (x[1] & 0xf0) === 0x80))) { if ((s & 0xf0) === 0x90 && p2) sounding.set(p1, t); else if ((s & 0xf0) === 0x80) sounding.delete(p1); }
      assert.equal(sounding.size, 0, `${S.key}: channel ${ch} holds a note across the start of the tune`);
    });
    // the lead calls in the intro; when there is a run, it arrives next to the tune's first note
    // (a step in the dominant's colour, to a first note that may carry a grace: allow a fifth)
    const lead = events(a.bodies[1 + a.info.channels.indexOf(0)]).filter((x) => (x[1] & 0xf0) === 0x90 && x[3]), before = lead.filter((x) => x[0] < shift), first = lead.find((x) => x[0] >= shift);
    assert.ok(before.length >= 1, 'the lead plays in the intro');
    if (a.info.intro.includes('a quiet run') && first) assert.ok(Math.abs(before.at(-1)[2] - first[2]) <= 7, `${S.key}: the run ends ${before.at(-1)[2] - first[2]} semitones from the tune`);
    // nothing in the intro's drums is loud, and there is no crash
    const drums = a.info.channels.indexOf(9); if (drums >= 0) for (const x of events(a.bodies[drums + 1]).filter((y) => y[0] < shift && (y[1] & 0xf0) === 0x90 && y[3])) { assert.ok(x[3] <= 50, `${S.key}: an intro drum at velocity ${x[3]}`); assert.notEqual(x[2], 49); }
    if (a.info.intro.includes('a quiet run')) runs++;
  }
  assert.ok(withIntro > n * 0.4 && withIntro < n * 0.6, `${withIntro} of ${n} have an intro`);
  assert.deepEqual([...lengths].sort(), [1, 2, 3, 4]);
  for (const x of ['call and response between the lead and the accompaniment', 'a counter-line in the bass', 'a quiet drum fill', 'a bass pedal', 'the accompaniment figure', 'a quiet run into the tune']) assert.ok(layers.has(x), `no intro has ${x}`);
  assert.ok(runs < withIntro * 0.4, `the run is the exception: ${runs} of ${withIntro}`);
});
