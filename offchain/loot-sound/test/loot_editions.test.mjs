// Spread chords in the editions' accompaniment: rolled or arpeggiated bars play the same notes as the
// struck chord, in order, inside the chord's room, and nothing else in the track changes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';
import * as E from '../src/loot_editions.js';

/** A track body's notes [time, length, pitch, velocity]; throws on a note left on or struck twice. */
function notesOf(body) {
  const out = [], on = new Map();
  let i = 0, t = 0, status = 0;
  while (i < body.length) {
    let d = 0; for (;;) { const b = body[i++]; d = (d << 7) | (b & 127); if (!(b & 128)) break; }
    t += d;
    if (body[i] === 0xff) { i += 3 + body[i + 2]; continue; }
    if (body[i] & 128) status = body[i++];
    const hi = status & 0xf0;
    if (hi === 0xc0) { i += 1; continue; }
    const a = body[i++], b = body[i++];
    if (hi === 0x90 && b > 0) { assert.ok(!on.has(a), `pitch ${a} struck again at ${t} while sounding`); on.set(a, [t, b]); }
    else if (hi === 0x80 || hi === 0x90) { const s = on.get(a); assert.ok(s, `off without on at ${t}`); out.push([s[0], t - s[0], a, s[1]]); on.delete(a); }
  }
  assert.equal(on.size, 0, 'a note is left on');
  return out.sort((x, y) => x[0] - y[0] || x[2] - y[2]);
}
const seeds = [1n, 2n, 0x9e3779b97f4a7c15n, 0xdeadbeefcafen, 77n];
const drifts = [null, { rhythm: 0xabcdef12345n, rotate: 0x777123456n, dayKnob: 1, delta: 0, day: 200 }];

test('spreadChord: a roll and an arpeggio play the chord\'s notes inside its room', () => {
  const ps = [60, 64, 67, 70];
  for (const [d, room] of [[160, 480], [200, 240], [440, 960], [930, 960], [1880, 1920], [100, 120], [288, 480], [700, 720]]) for (let how = 0; how < 5; how++) {
   for (const step of [undefined, ...E.SPREAD_STEPS]) {
    if (step && Math.floor(room / step) < 2) continue;
    const ns = E.spreadChord(how, 1000, d, room, ps, 72, step);
    for (const [t, len, p, v] of ns) { assert.ok(ps.includes(p)); assert.ok(t >= 1000 && len > 0 && t + len <= 1000 + Math.max(d, room), `how ${how} d ${d} room ${room}: ${t}+${len}`); assert.ok(v > 0 && v < 128); }
    assert.equal(ns[0][0], 1000);
    if (how === 0) assert.ok(ns.every((n) => n[0] === 1000 && n[1] === d));
    else {
      assert.ok(new Set(ns.map((n) => n[0])).size > 1, `how ${how} d ${d}: not spread`);
      if (how <= 2 || ns.length >= ps.length) assert.deepEqual([...new Set(ns.map((n) => n[2]))].sort(), ps);
      // an arpeggio moves at a subdivision of the beat; a roll faster than that
      const gaps = ns.slice(1).map((n, k) => n[0] - ns[k][0]);
      assert.ok(gaps.every((g) => g === gaps[0]) && (E.SPREAD_STEPS.includes(gaps[0]) || gaps[0] <= 40));
      if (how >= 3 && step && gaps[0] > 40) assert.equal(gaps[0], step);
    }
   }
  }
});

test('editions: spread bars keep the accompaniment\'s notes and leave every other part alone', () => {
  let tracks = 0, spread = 0, rolled = 0, arped = 0, withChords = 0, varied = 0, manyArps = 0;
  const stepsSeen = new Set();
  const leans = new Set();
  for (let e = 1; e <= STYLES.length; e++) for (const sp of [SPECIES[0], SPECIES[13], SPECIES[29]]) for (const seed of seeds) for (const d of drifts) {
    const a = E.editionTrack(sp, false, e, seed, d), b = E.editionTrack(sp, false, e, seed, d, true);
    assert.deepEqual(E.editionTrack(sp, false, e, seed, d).bodies, a.bodies);
    assert.equal(a.bodies.length, b.bodies.length); assert.equal(a.ticks, b.ticks);
    const acc = a.info.channels.indexOf(2) + 1;
    a.bodies.forEach((body, k) => { if (k !== acc) assert.deepEqual(body, b.bodies[k], `edition ${e} species ${sp.id}: part ${k} changed`); });
    const na = notesOf(a.bodies[acc]), nb = notesOf(b.bodies[acc]), bar = STYLES[(e - 1) % STYLES.length].num * (1920 / STYLES[(e - 1) % STYLES.length].den);
    // bar by bar: the same pitches, nothing before the bar or past the track
    const byBar = (ns) => { const m = new Map(); for (const [t, , p] of ns) { const k = Math.floor(t / bar); m.set(k, (m.get(k) || new Set()).add(p)); } return m; };
    const pa = byBar(na), pb = byBar(nb);
    assert.deepEqual([...pa.keys()], [...pb.keys()]);
    for (const [k, set] of pa) for (const p of set) assert.ok(pb.get(k).has(p), `edition ${e} species ${sp.id} bar ${k}: ${p} is not in the struck chord`);
    for (const [t, len] of na) assert.ok(t + len <= a.ticks);
    tracks++;
    if (a.info.chords !== 'the figure has no chords') withChords++;
    const starts = new Set(nb.map((n) => n[0])), moved = na.filter((n) => !starts.has(n[0]));
    if (moved.length) { spread++; leans.add(a.info.chords.split(' in ')[0]); if (a.info.spread.rolled) rolled++; if (a.info.spread.steps.length) arped++; }
    a.info.spread.steps.forEach((x) => stepsSeen.add(x));
    // every arpeggio's onsets are a step of its bar's subdivision after the struck chord's
    if (a.info.spread.steps.length && a.info.spread.bars - a.info.spread.rolled >= 4) { manyArps++; if (a.info.spread.steps.length >= 2) varied++; }
    // no triplets in any meter: every accompaniment note starts on the sixteenth grid, or within a roll of it
    assert.ok(a.info.spread.steps.every((x) => [240, 120, 60].includes(x)), 'a triplet');
  }
  console.log(`${tracks} tracks, ${withChords} with chords in the figure: ${spread} have spread chords (${rolled} with rolls, ${arped} with arpeggios)`);
  console.log(`${manyArps} tracks with four or more arpeggiated bars: ${varied} use two or more subdivisions; seen: ${[...stepsSeen].sort((x, y) => y - x).map((x) => E.STEP_NAMES[x]).join(', ')}`);
  assert.ok(spread * 10 >= withChords * 8); assert.ok(rolled > 20 && arped > 20); assert.equal(leans.size, 3);
  assert.ok(varied * 10 >= manyArps * 7); assert.equal(stepsSeen.size, E.SPREAD_STEPS.length);
});

test('the pizzicato accompaniment is an octave lower on some purchases and some weeks, and only in its styles', () => {
  const week = (k) => ({ rhythm: null, rotate: BigInt(k) * 0x51ed270b3n + BigInt(k * k) * 0x2545f4914f6cdd1dn, dayKnob: 2, delta: 0, day: 30 });
  for (let e = 1; e <= STYLES.length; e++) {
    const pizz = E.LOW_ACCOMP_STYLES.includes(STYLES[e - 1].key), sp = SPECIES[e % SPECIES.length];
    let low = 0, flips = 0;
    for (let s = 1; s <= 60; s++) {
      const a = E.editionTrack(sp, false, e, BigInt(s) * 0x9e3779b97f4a7c15n, null);
      if (a.info.accompLow) low++;
      if (!pizz) continue;
      const lowest = (tr) => Math.min(...notesOf(tr.bodies[tr.info.channels.indexOf(2) + 1]).map((n) => n[2]));
      assert.ok(lowest(a) >= 36);
      for (let k = 1; k <= 4; k++) { const w = E.editionTrack(sp, false, e, BigInt(s) * 0x9e3779b97f4a7c15n, week(k + 7 * s)); if (w.info.accompLow !== a.info.accompLow) flips++; assert.ok(lowest(w) >= 36, `edition ${e} purchase ${s} week ${k}: lowest ${lowest(w)}`); }
    }
    if (pizz) { assert.ok(low >= 10 && low <= 45, `edition ${e}: ${low} of 60 purchases low`); assert.ok(flips >= 60 && flips <= 180, `edition ${e}: ${flips} of 240 weeks change the octave`); }
    else assert.ok(low <= 25);
  }
});
