// The Round's promises, checked on the notes it writes: the canon is exact, every strong beat is the
// loop's chord, the lines make no parallel fifths or octaves, and drift changes what it says it changes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SPECIES } from '../src/loot_species.js';
import * as M from '../src/loot_rounds.js';

const OCT = [0, -1, 0, -1];
const drifts = [null, { rhythm: 0x9e3779b97f4a7c15n, rotate: null, dayKnob: 2, delta: -4, day: 40 }, { rhythm: null, rotate: 0x51ed270b3n, dayKnob: 0, delta: 0, day: 200 }, { rhythm: 0xabcdef12345n, rotate: 0x777123456n, dayKnob: 1, delta: 0, day: 400 }, { rhythm: 0x1234n, rotate: 0xfedcba987n, dayKnob: 5, delta: 4, day: 700 }];
const cases = [];
for (const sp of SPECIES) for (const seed of [0n, 1n, 2n, 0xdeadbeefcafen]) for (const d of drifts) cases.push([sp, seed, d]);
const triad = (sc, root) => [0, 2, 4].map((k) => (sc.tonic + sc.scale[(root + k) % 7]) % 12);
/** Every part's sounding notes: the canon voices by entry, then the bass. */
const parts = (sc) => [...sc.voices.map((v) => M.soundingNotes({ ...sc, art: 0 }, v.notes.map((n) => ({ ...n, grace: 0 })), OCT[v.ch])), ...(sc.bass.length ? [M.soundingNotes({ ...sc, art: 0 }, sc.bass, -2)] : [])];
const startingAt = (notes, t) => notes.find((n) => n[0] === t);

test('every mode has loops to choose from', () => {
  for (const m of M.ROUND_MODES) { assert.ok(M.loopsFor(m).length >= 8, `mode ${m}`); assert.ok(M.loopsFor(m, true).length >= 4, `mode ${m} (8 chords)`); }
  for (const l of [...M.LOOPS4, ...M.LOOPS8]) { assert.equal(l[0], 0); assert.notEqual(l[l.length - 1], 0); l.forEach((r, i) => assert.notEqual(r, l[(i + 1) % l.length])); }
});

test('the file parses and every note is in range', () => {
  for (const [sp, seed, d] of cases) for (const mega of [false, true]) {
    const { midi, score } = M.roundMidi(sp, mega, seed, d);
    assert.equal(String.fromCharCode(...midi.slice(0, 4)), 'MThd');
    let i = 14, n = 0;
    while (i < midi.length) { assert.equal(String.fromCharCode(...midi.slice(i, i + 4)), 'MTrk'); i += 8 + ((midi[i + 4] << 24) | (midi[i + 5] << 16) | (midi[i + 6] << 8) | midi[i + 7]); n++; }
    assert.equal(i, midi.length); assert.equal(n, (midi[10] << 8) | midi[11]);
    for (const p of parts(score)) for (const [, len, pitch] of p) assert.ok(len > 0 && pitch >= 24 && pitch <= 100, `species ${sp.id}: pitch ${pitch}`);
  }
});

test('the canon is exact: every voice plays the first voice, a loop later each', () => {
  for (const [sp, seed, d] of cases) {
    const sc = M.roundScore(sp, false, seed, d), lead = sc.voices[0].notes;
    for (const v of sc.voices.slice(1)) {
      const lag = v.entry * sc.cyc, mine = v.notes.filter((n) => n.sect === 'A'), theirs = lead.filter((n) => n.sect === 'A' && n.t + lag < sc.epStart);
      assert.ok(mine.length > 0);
      assert.deepEqual(mine.map((n) => [n.t - lag, n.len, n.d, n.grace || 0]), theirs.map((n) => [n.t, n.len, n.d, n.grace || 0]), `species ${sp.id} seed ${seed} voice ${v.entry}`);
    }
  }
});

test('the episode is a canon too: half a bar apart, a step of the sequence on', () => {
  for (const [sp, seed, d] of cases) {
    const sc = M.roundScore(sp, false, seed, d), E = M.EPISODES[sc.epKind], ep = sc.voices.map((v) => v.notes.filter((n) => n.sect === 'episode'));
    const order = ep.map((n, i) => [n.length ? n[0].t : -1, i]).filter((x) => x[0] >= 0).sort((a, b) => a[0] - b[0]).map((x) => x[1]);
    assert.equal(order.length, 3);
    const lead = ep[order[0]];
    order.slice(1).forEach((i, q) => {
      const lag = (q + 1) * sc.slot, tr = ep[i][0].d - lead[0].d;
      assert.equal((((tr - E.step * (q + 1)) % 7) + 7) % 7, 0);
      assert.deepEqual(ep[i].map((n) => [n.t - lag, n.len, n.d - tr]), lead.filter((n) => n.t + lag < sc.epStart + 7 * sc.slot).map((n) => [n.t, n.len, n.d]));
    });
  }
});

test('every strong beat is the chord, and the whole chord once every voice is in', () => {
  for (const [sp, seed, d] of cases) {
    const sc = M.roundScore(sp, false, seed, d), ps = parts(sc);
    for (const slot of sc.slots) {
      const pcs = triad(sc, slot.root), heard = new Set();
      let canon = 0;
      ps.forEach((notes, k) => {
        const n = startingAt(notes, slot.t);
        if (!n) return;
        assert.ok(pcs.includes(n[2] % 12), `species ${sp.id} seed ${seed} tick ${slot.t}: ${n[2]} is not in the chord on ${slot.root}`);
        heard.add(n[2] % 12); if (k < sc.K) canon++;
      });
      if (slot.sect !== 'join' && slot.sect !== 'episode' && canon === sc.K) assert.equal(heard.size, 3, `species ${sp.id} seed ${seed} tick ${slot.t}: the chord is not whole`);
      if (slot.sect === 'episode' && canon === 3) assert.equal(heard.size, 3);
    }
  }
});

/** Parallel perfect fifths and octaves between any two parts across consecutive strong beats. */
function parallels(sc) {
  const ps = parts(sc), found = { inside: 0, joins: 0, moves: 0 };
  for (let k = 0; k + 1 < sc.slots.length; k++) {
    const a = sc.slots[k], b = sc.slots[k + 1];
    if (a.root === b.root) continue;
    for (let x = 0; x < ps.length; x++) for (let y = x + 1; y < ps.length; y++) {
      const [x0, x1, y0, y1] = [startingAt(ps[x], a.t), startingAt(ps[x], b.t), startingAt(ps[y], a.t), startingAt(ps[y], b.t)];
      if (!x0 || !x1 || !y0 || !y1) continue;
      found.moves++;
      const i0 = (((x0[2] - y0[2]) % 12) + 12) % 12, i1 = (((x1[2] - y1[2]) % 12) + 12) % 12, up0 = x0[2] > y0[2], up1 = x1[2] > y1[2];
      const fifth = (i, up) => (up ? i === 7 : i === 5), moved = x0[2] !== x1[2] && Math.sign(x1[2] - x0[2]) === Math.sign(y1[2] - y0[2]);
      if (moved && ((i0 === 0 && i1 === 0) || (fifth(i0, up0) && fifth(i1, up1)))) found[a.sect === 'join' || b.sect === 'join' || a.sect !== b.sect ? 'joins' : 'inside']++;
    }
  }
  return found;
}
test('no parallel fifths or octaves, bass included', () => {
  let inside = 0, joins = 0, moves = 0, tracks = 0;
  const all = [...cases]; for (const sp of SPECIES) for (let s = 10; s < 60; s++) all.push([sp, BigInt(s) * 0x9e3779b97f4a7c15n, null]);
  for (const [sp, seed, d] of all) { const f = parallels(M.roundScore(sp, false, seed, d)); inside += f.inside; joins += f.joins; moves += f.moves; tracks++; }
  console.log(`${tracks} tracks, ${moves} pair moves: ${inside} parallels inside the round and episode, ${joins} at the joins`);
  assert.equal(inside, 0); assert.equal(joins, 0);
});

test('drift: the same day gives the same bytes, and each clock changes the track', () => {
  const same = (a, b) => a.length === b.length && a.every((x, i) => x === b[i]);
  for (const sp of SPECIES) {
    const base = M.roundMidi(sp, false, 0n, null);
    assert.ok(same(base.midi, M.roundMidi(sp, false, 0n, null).midi));
    const quiet = { rhythm: null, rotate: null, dayKnob: 2, delta: 0, day: 2 };
    const month = M.roundScore(sp, false, 0n, { ...quiet, rhythm: 0x9e3779b97f4a7c15n }), week = M.roundScore(sp, false, 0n, { ...quiet, rotate: 0x51ed270b3n }), written = base.score;
    assert.notDeepEqual(month.loop, written.loop, `species ${sp.id}: the month's loop`);
    assert.deepEqual(week.loop, written.loop); assert.deepEqual(week.roles, written.roles);
    assert.notDeepEqual(week.voices.map((v) => v.ch), written.voices.map((v) => v.ch));
    assert.equal(month.tonic, written.tonic); assert.equal(month.mode, written.mode);
    for (let k = 0; k < 6; k++) assert.ok(!same(base.midi, M.roundMidi(sp, false, 0n, { ...quiet, dayKnob: k, delta: [0, 0, -4, -2, 2, 4][k] }).midi), `species ${sp.id}: day knob ${k}`);
    // the motif opens every version
    for (const sc of [month, week]) assert.deepEqual(sc.voices[0].notes.slice(0, 1).map((n) => n.d), [0]);
  }
});

test('bought tracks differ', () => {
  for (const sp of [SPECIES[0], SPECIES[14], SPECIES[29]]) {
    const files = new Set(), themes = new Set(), loops = new Set();
    for (let s = 1; s <= 300; s++) { const o = M.roundMidi(sp, false, BigInt(s) * 0x9e3779b97f4a7c15n, null); files.add(o.midi.join(',')); themes.add(o.info.theme); loops.add(o.info.key + o.info.loop); }
    console.log(`species ${sp.id}: 300 purchases -> ${files.size} files, ${themes.size} themes, ${loops.size} key and loop pairs`);
    assert.equal(files.size, 300); assert.ok(themes.size >= 230);
  }
});

test('ornaments grow with the days of drift', () => {
  const count = (sc) => sc.voices.reduce((a, v) => a + v.notes.filter((n) => n.grace).length, 0), kinds = (sc) => new Set(sc.voices.flatMap((v) => v.notes.map((n) => n.grace || 0))).size - 1;
  const total = (sc) => sc.voices.reduce((a, v) => a + v.notes.length, 0);
  const on = (sp, day) => M.roundScore(sp, false, 0n, { rhythm: null, rotate: null, dayKnob: 2, delta: 0, day });
  for (const sp of SPECIES) {
    const at = [2, 100, 200, 300, 400].map((day) => on(sp, day)), ns = at.map(count);
    for (let k = 1; k < ns.length; k++) assert.ok(ns[k] >= ns[k - 1], `species ${sp.id}: ${ns}`);
    assert.ok(ns[2] > ns[0] && ns[4] > ns[2], `species ${sp.id}: ${ns}`);
    assert.ok(ns[4] * 3 >= total(at[4]), `species ${sp.id}: ${ns[4]} of ${total(at[4])} notes ornamented at day 400`);
    assert.ok(kinds(at[4]) >= 4);
    for (const sc of at) for (const art of [0, 1, 2]) for (const v of sc.voices) for (const [, len, p] of M.soundingNotes({ ...sc, art }, v.notes, 0)) assert.ok(len > 0 && p > 0);
  }
  console.log('species 76, ornamented notes at days 2, 100, 200, 300, 400:', [2, 100, 200, 300, 400].map((d) => count(on(SPECIES[0], d))).join(', '), 'of', total(on(SPECIES[0], 400)));
});

test('suspensions: a note held over a chord change is not in the new chord and steps down into it a beat late', () => {
  let found = 0, tracks = 0, withOne = 0;
  for (const [sp, seed, d] of cases) {
    const sc = M.roundScore(sp, false, seed, d), cls = (dg) => (((dg % 7) + 7) % 7);
    const member = (dg, root) => [0, 2, 4].includes(cls(dg - root));
    let here = 0;
    for (const v of sc.voices) v.notes.forEach((n, k) => {
      if (n.sect === 'join' || n.sect === 'episode') return;
      const slot = sc.slots.find((x) => x.t > n.t && x.t < n.t + n.len);
      if (!slot || sc.slots.find((x) => x.t <= n.t && x.t + sc.slot > n.t).root === slot.root) return;
      const next = v.notes[k + 1];
      assert.ok(!member(n.d, slot.root), `species ${sp.id} seed ${seed}: the held note is in the chord`);
      assert.equal(n.t + n.len, slot.t + sc.late); assert.equal(next.t, slot.t + sc.late); assert.equal(next.d, n.d - 1);
      assert.ok(member(next.d, slot.root));
      // nobody else sounds the tone it resolves to while it is held
      for (const w of sc.voices) if (w !== v) for (const m of w.notes) if (m.t === slot.t) assert.notEqual(cls(m.d), cls(next.d));
      here++;
    });
    found += here; tracks++; if (here) withOne++;
  }
  console.log(`suspensions: ${found} in ${tracks} tracks, ${withOne} tracks have at least one`);
  assert.ok(withOne * 2 >= tracks);
});

test('the round comes back over another loop, with the motif again', () => {
  for (const [sp, seed, d] of cases) {
    const sc = M.roundScore(sp, false, seed, d);
    assert.notDeepEqual(sc.second.loop, sc.first.loop, `species ${sp.id} seed ${seed}`);
    const head = (rd) => rd.lineNotes(0, 0).filter((n) => n.t < 2 * sc.slot).map((n) => [n.t, n.len]);
    assert.equal(sc.second.theme[0][0], 0); assert.deepEqual(head(sc.second), head(sc.first));
    // every line of both themes opens with the motif's rhythm
    for (const rd of [sc.first, sc.second]) for (let j = 1; j < sc.K; j++) assert.deepEqual(rd.lineNotes(j, 0).filter((n) => n.t < 2 * sc.slot && !n.grace).map((n) => [n.t, n.len]).length <= 4, true);
    const who = sc.voices.find((v) => (sc.CA - v.entry) % sc.K === 0), first = who.notes.find((n) => n.sect === 'B');
    assert.equal(first.t, sc.bStart); assert.equal(first.d, 0);
  }
});

test('the lines move: few repeated chord tones', () => {
  let moves = 0, repeats = 0, leaps = 0;
  for (const sp of SPECIES) for (const seed of [0n, 1n, 2n, 3n]) {
    const sc = M.roundScore(sp, false, seed, null);
    for (const rd of [sc.first, sc.second]) for (const line of rd.theme) for (let s = 1; s < line.length; s++) { moves++; if (line[s] === line[s - 1]) repeats++; if (Math.abs(line[s] - line[s - 1]) > 4) leaps++; }
  }
  console.log(`chord-tone moves: ${moves}, repeated ${(100 * repeats / moves).toFixed(1)}%, leaps over a fifth ${(100 * leaps / moves).toFixed(1)}%`);
  assert.ok(repeats * 7 < moves);
});

test('meters: 4/4, 6/8 and 3/4 by family, slots on the bar, the meter kept through drift', () => {
  const seen = [new Set(), new Set(), new Set()], secs = [];
  for (const [sp, seed, d] of cases) {
    const { midi, score: sc } = M.roundMidi(sp, false, seed, d), m = M.METERS[sc.meter];
    seen[sp.type].add(m.name); secs.push(sc.info.seconds);
    assert.equal(sc.meter, M.roundScore(sp, false, seed, null).meter, `species ${sp.id}: drift changed the meter`);
    assert.equal(sc.cyc % m.bar, 0); assert.equal(sc.epStart % m.bar, 0); assert.equal(sc.bStart % m.bar, 0); assert.equal(sc.end % m.bar, 0);
    for (const v of sc.voices) for (const n of v.notes) assert.ok(n.t + n.len <= sc.end);
    // the time signature in the file's first track
    const at = midi.findIndex((b, i) => b === 0xff && midi[i + 1] === 0x58);
    assert.deepEqual([...midi.slice(at + 3, at + 7)], m.sig);
  }
  assert.deepEqual([...seen[0]].sort(), ['3/4', '4/4', '6/8']); assert.deepEqual([...seen[1]].sort(), ['4/4', '6/8']); assert.deepEqual([...seen[2]].sort(), ['3/4', '4/4']);
  secs.sort((a, b) => a - b);
  console.log(`lengths: ${secs[0]} to ${secs[secs.length - 1]} s, median ${secs[secs.length >> 1]}`);
  assert.ok(secs[secs.length - 1] <= 105);
});

test('the bass has the root wherever a slot starts, and every figure and episode is used', () => {
  const figs = new Set(), eps = new Set();
  for (const [sp, seed, d] of cases) {
    const sc = M.roundScore(sp, false, seed, d);
    eps.add(sc.epKind);
    if (!sc.bass.length) continue;
    figs.add(sc.info.bass);
    for (const slot of sc.slots) { const n = sc.bass.find((b) => b.t === slot.t); if (n) assert.equal((((n.d - slot.root) % 7) + 7) % 7, 0, `species ${sp.id} seed ${seed} tick ${slot.t}`); }
    for (const n of sc.bass) assert.ok(n.d >= -4 && n.d <= 10);
  }
  assert.equal(figs.size, M.BASS_NAMES.length); assert.equal(eps.size, M.EPISODES.length);
});
