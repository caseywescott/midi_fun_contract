// The loop covers the whole form: every section closes with its rest, the last one included. The MIDI
// file's End of Track carries the length, and every reader of it keeps it.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { engine, composeBeast, bsnToMidi } from '../src/index.js';
import { parse } from '../onchain/lib/smf.js';
import { write } from '../onchain/lib/midi.js';
import { createLoopScheduler } from '../server/scheduler.js';

const BEASTS = [
  [{ id: 47, prefix: 13, suffix: 6, level: 22, health: 60, shiny: 0, animated: 0, tier: 5, beast_type: 1 }, { adventurers_killed: 0, scars: 0, rank: 0, species_count: 0 }],
  [{ id: 1, prefix: 57, suffix: 15, level: 126, health: 229, shiny: 0, animated: 0, tier: 1, beast_type: 0 }, { adventurers_killed: 40, scars: 9, rank: 1, species_count: 954 }],
  [{ id: 53, prefix: 69, suffix: 18, level: 255, health: 1023, shiny: 1, animated: 1, tier: 1, beast_type: 2 }, { adventurers_killed: 500, scars: 20, rank: 1, species_count: 40 }], // lag 1: 21 beats raw
  [{ id: 47, prefix: 13, suffix: 6, level: 22, health: 60, shiny: 0, animated: 0, tier: 5, beast_type: 1 }, { adventurers_killed: 7, scars: 0, rank: 0, species_count: 0 }],        // lag 3: 21 beats raw
];

for (const [beast, live] of BEASTS) {
  test(`${beast.id}/${beast.prefix}/${beast.suffix}: the MIDI lasts the whole form and the loop seam matches the section gaps`, () => {
    const r = engine.render(beast, { summit_held_seconds: 0, ...live }), f = r.form;
    const length = f.section_ticks * f.sections.length;
    const song = parse(engine.toMidiFile(r));
    assert.equal(song.length_ticks, length, 'End of Track at the form length');
    assert.equal(f.section_ticks % 1920, 0, 'sections are whole bars, so each starts on a downbeat');
    assert.equal(length % 1920, 0, 'whole bars');
    const end = Math.max(...song.notes.map((n) => n[0] + n[1]));
    const rest = length - end;
    assert.ok(rest > 0, 'the form closes with a rest');
    for (let s = 1; s < f.sections.length; s++) {
      const prevEnd = Math.max(...f.events.filter((e) => e.section === s - 1).map((e) => e.time + e.duration));
      const start = Math.min(...f.events.filter((e) => e.section === s).map((e) => e.time));
      assert.equal(start - prevEnd, rest, `gap before section ${s} equals the rest at the loop`);
    }
    // every path to the MIDI keeps the length: BSN1 felts, the library writer, composeBeast
    const song2 = composeBeast(beast, { summit_held_seconds: 0, ...live });
    assert.deepEqual(bsnToMidi(song2.bsnFelts), engine.toMidiFile(r));
    assert.deepEqual(write(song), engine.toMidiFile(r));
    assert.equal(song2.lengthTicks, length);
    // and the chip engine's scheduler loops there
    const sched = createLoopScheduler(song.notes, { tick: 0.001, length: song.length_ticks, drums: false, onNote() {}, onDrum() {} });
    assert.equal(sched.loopTicks, length);
  });
}
