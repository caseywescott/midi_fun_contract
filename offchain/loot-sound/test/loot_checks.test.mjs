// The Sound Check's promises, checked on the notes: every pitched note is in the Beast's mode, nothing
// collides, every routine fits its ten bars, and the Beasts and the takes differ.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SPECIES } from '../src/loot_species.js';
import * as C from '../src/loot_checks.js';

const takes = [0n, 1n, 2n, 3n, 0xdeadbeefcafen];

test('the file parses, every note is in the mode and in range, and nothing runs past the end', () => {
  for (const sp of SPECIES) for (const take of takes) for (const mega of [false, true]) {
    const { midi, score: sc } = C.soundCheckMidi(sp, mega, take);
    assert.equal(String.fromCharCode(...midi.slice(0, 4)), 'MThd');
    let i = 14, n = 0;
    while (i < midi.length) { assert.equal(String.fromCharCode(...midi.slice(i, i + 4)), 'MTrk'); i += 8 + ((midi[i + 4] << 24) | (midi[i + 5] << 16) | (midi[i + 6] << 8) | midi[i + 7]); n++; }
    assert.equal(i, midi.length); assert.equal(n, (midi[10] << 8) | midi[11]);
    const pcs = sc.scale.map((x) => (sc.tonic + x) % 12);
    sc.parts.forEach((_, part) => {
      const notes = C.checkNotes(sc, part);
      for (const [t, len, p, v] of notes) {
        assert.ok(pcs.includes(p % 12), `species ${sp.id} take ${take} part ${part}: ${p} is not in the mode`);
        assert.ok(p >= 24 && p <= 103 && len > 0 && v >= 40 && v <= 127 && t >= 0 && t + len <= sc.end, `species ${sp.id} take ${take} part ${part}: note ${p} at ${t} for ${len}, velocity ${v}`);
      }
      // no note starts on a pitch that is still sounding in its own part
      for (let a = 0; a < notes.length; a++) for (let b = a + 1; b < notes.length; b++) if (notes[a][2] === notes[b][2]) assert.ok(notes[a][0] + notes[a][1] <= notes[b][0] || notes[b][0] + notes[b][1] <= notes[a][0], `species ${sp.id} take ${take} part ${part}: ${notes[a][2]} overlaps itself at ${notes[b][0]}`);
    });
    for (const h of sc.perc) assert.ok(C.CHECK_DRUMS.includes(h.key) && h.v >= 40 && h.v <= 127 && h.t < sc.end);
    assert.equal(sc.parts[5].length > 0, mega);
  }
});

test('a routine is ten bars: an opening, three different drills, a close', () => {
  const secs = [];
  for (const sp of SPECIES) for (const take of takes) {
    const sc = C.soundCheckScore(sp, false, take);
    assert.equal(sc.end, 10 * C.BAR); assert.equal(new Set(sc.drills).size, 3);
    // every two bars have notes in them
    for (let k = 0; k < 5; k++) assert.ok([...sc.parts.flat(), ...sc.perc].some((n) => n.t >= k * C.SEG && n.t < (k + 1) * C.SEG));
    secs.push(sc.info.seconds);
  }
  console.log(`lengths: ${Math.min(...secs)} to ${Math.max(...secs)} s`);
  assert.ok(Math.min(...secs) >= 14 && Math.max(...secs) <= 28);
});

test('the same Beast and take give the same bytes; the Beasts and the takes differ', () => {
  const own = new Set(), routines = new Set(), used = { o: new Set(), d: new Set(), c: new Set() };
  for (const sp of SPECIES) {
    const a = C.soundCheckMidi(sp, false, 0n), b = C.soundCheckMidi(sp, false, 0n);
    assert.deepEqual([...a.midi], [...b.midi]);
    own.add(a.midi.join(',')); routines.add(a.info.opening + a.info.drills + a.info.close);
    const files = new Set();
    for (let k = 0; k < 100; k++) {
      const o = C.soundCheckMidi(sp, false, BigInt(k) * 0x9e3779b97f4a7c15n);
      files.add(o.midi.join(',')); used.o.add(o.score.opening); used.c.add(o.score.close); o.score.drills.forEach((d) => used.d.add(d));
      assert.equal(o.score.tonic, a.score.tonic); assert.equal(o.score.mode, a.score.mode);
    }
    assert.ok(files.size >= 90, `species ${sp.id}: ${files.size} files in 100 takes`);
  }
  console.log(`30 species: ${own.size} files, ${routines.size} routines`);
  assert.equal(own.size, 30); assert.ok(routines.size >= 25);
  assert.equal(used.o.size, C.OPENINGS.length); assert.equal(used.d.size, C.DRILLS.length); assert.equal(used.c.size, C.CLOSES.length);
});
