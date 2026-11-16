// Harp glissandi: at most one a track and some tracks none, some an octave higher, each a run of
// scale steps a thirty-second note apart, up or down, ending where a section ends; shorter on a faster track.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';
import * as E from '../src/loot_editions.js';
import * as R from '../src/loot_rounds.js';
import * as C from '../src/loot_checks.js';

const seedOf = (k) => BigInt(k) * 0x9e3779b97f4a7c15n + BigInt(k * k) * 0x2545f4914f6cdd1dn;
const week = (k) => ({ rhythm: null, rotate: seedOf(k + 3), dayKnob: 2, delta: 0, day: 30 });
/** Split sounding notes [t, len, pitch, vel] into runs a step apart in time. */
function runs(notes) {
  const out = [];
  for (const n of [...notes].sort((a, b) => a[0] - b[0])) { const last = out[out.length - 1]; if (last && n[0] - last[last.length - 1][0] === E.GLISS_STEP) last.push(n); else out.push([n]); }
  return out;
}
/** Check a track's glissandi; returns how many it has. */
function check(label, notes, plan, ends, pcs, trackEnd, bpm) {
  // 12-16 notes under 120 BPM, 6-8 from there, 4-6 from 160, and no note rings longer than half the run
  const [least, most, ring] = bpm >= 160 ? [4, 6, 180] : bpm >= 120 ? [6, 8, 240] : [12, 16, 360];
  lengths.add(least);
  const rs = runs(notes);
  assert.equal(rs.length, plan.length, `${label}: ${rs.length} runs for ${plan.length} planned`);
  assert.ok(plan.length <= 1);
  rs.forEach((run, k) => {
    assert.ok(run.length >= least && run.length <= most, `${label}: ${run.length} notes at ${bpm} BPM`);
    assert.ok(run.every((n) => n[1] <= ring), `${label}: a note rings longer than ${ring} ticks`);
    assert.ok(ends.includes(run[run.length - 1][0] + E.GLISS_STEP), `${label}: a glissando ends at ${run[run.length - 1][0] + E.GLISS_STEP}, not at a section's end`);
    const up = run[1][2] > run[0][2];
    assert.equal(up, plan[k].up);
    for (let i = 1; i < run.length; i++) { const d = (run[i][2] - run[i - 1][2]) * (up ? 1 : -1); assert.ok(d >= 1 && d <= 3, `${label}: a step of ${d} semitones`); }
    for (const [t, len, p, v] of run) { assert.ok(v >= 43 && v <= 63 && len > 0 && t >= 0 && t + len <= trackEnd && p >= 36 && p <= 96, `${label}: note ${p} at ${t}`); if (pcs) assert.ok(pcs.includes(p % 12), `${label}: ${p} is not in the scale`); }
  });
  if (rs.length) { const low = Math.min(...rs[0].map((n) => n[2])); (plan[0].high ? highs : lows).push(low); }
  return rs.length;
}
const highs = [], lows = [], lengths = new Set();
const tally = (name, counts) => {
  console.log(`${name}: ${counts[0]} tracks with none, ${counts[1]} with one; ${highs.length} of ${highs.length + lows.length} so far an octave higher`);
  assert.equal(counts[2], 0); assert.ok(counts[0] * 4 >= counts[0] + counts[1] && counts[1] * 4 >= counts[0] + counts[1]);
  // the higher ones sit an octave above the others' range
  assert.ok(highs.length > 0 && lows.length > highs.length); assert.ok(Math.min(...highs) >= Math.min(...lows) + 12);
};

test('Rounds', () => {
  const counts = [0, 0, 0], spots = new Set(), ways = new Set();
  for (const sp of SPECIES) for (let k = 0; k < 12; k++) for (const d of [null, week(k)]) {
    const sc = R.roundScore(sp, false, k ? seedOf(k) : 0n, d), pcs = sc.scale.map((x) => (sc.tonic + x) % 12);
    counts[check(`round ${sp.id} ${k}`, R.glissNotes(sc), sc.glPlan, sc.glAt, pcs, sc.end, sc.bpm0)]++;
    sc.glPlan.forEach((x) => { spots.add(x.spot); ways.add(x.up); });
    assert.equal(R.roundMidi(sp, false, k ? seedOf(k) : 0n, d).info.channels.includes(E.GLISS_CHANNEL), sc.gliss.length > 0);
  }
  tally('Rounds', counts); assert.equal(spots.size, 4); assert.equal(ways.size, 2);
});

test('Sound Checks', () => {
  const counts = [0, 0, 0];
  for (const sp of SPECIES) for (let k = 0; k < 20; k++) {
    const sc = C.soundCheckScore(sp, false, k ? seedOf(k) : 0n), pcs = sc.scale.map((x) => (sc.tonic + x) % 12);
    counts[check(`check ${sp.id} ${k}`, C.checkNotes(sc, 6), sc.glPlan, sc.glAt, pcs, sc.end, sc.info.bpm)]++;
  }
  tally('Sound Checks', counts);
});

test('editions', () => {
  const counts = [0, 0, 0];
  let moved = 0, weeks = 0;
  for (let e = 1; e <= STYLES.length; e++) for (const sp of [SPECIES[1], SPECIES[12], SPECIES[27]]) for (let k = 1; k <= 8; k++) for (const d of [null, week(k)]) {
    // without the intro some purchases have: this test reads the tunes by their place in time
    const tr = E.editionTrack(sp, false, e, seedOf(k), d, false, null, false), at = tr.info.channels.indexOf(E.GLISS_CHANNEL), bar = tr.ticks / 32;
    assert.equal(at >= 0, tr.info.gliss.length > 0);
    const notes = [];
    if (at >= 0) {
      // the harp's track: note-ons and note-offs on its channel
      const body = tr.bodies[at + 1], on = new Map(); let i = 0, t = 0;
      while (i < body.length) {
        let dl = 0; for (;;) { const b = body[i++]; dl = (dl << 7) | (b & 127); if (!(b & 128)) break; }
        t += dl;
        if (body[i] === 0xff) { i += 3 + body[i + 2]; continue; }
        const st = body[i++];
        if ((st & 0xf0) === 0xc0) { i++; continue; }
        const a = body[i++], b = body[i++];
        if ((st & 0xf0) === 0x90) on.set(a, [t, b]); else if ((st & 0xf0) === 0x80) { const s = on.get(a); notes.push([s[0], t - s[0], a, s[1]]); on.delete(a); }
      }
      assert.equal(on.size, 0);
    }
    counts[check(`edition ${e} species ${sp.id} ${k}`, notes, tr.info.gliss, [8, 16, 24, 32].map((b) => b * bar), null, tr.ticks, tr.bpm)]++;
    if (d) { weeks++; const base = E.editionTrack(sp, false, e, seedOf(k), null).info.glissandi; if (base !== tr.info.glissandi) moved++; assert.equal(tr.info.gliss.length, E.editionTrack(sp, false, e, seedOf(k), null).info.gliss.length); }
  }
  tally('editions', counts);
  console.log(`a week of drift moves or turns the glissandi in ${moved} of ${weeks} tracks`);
  assert.ok(moved > 0);
  assert.equal(lengths.size, 3, 'slow, quick and fast tracks all met');
});
