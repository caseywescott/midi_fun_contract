import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createCoreEngine } from '../src/engine.js';
import { createEngineV11 } from '../src/engine_v11.js';
import { poseidonHashMany } from '../src/poseidon_lite.js';
import { normalizedCase, SCORE_CASE_COUNT } from './normalized-cases.mjs';
const E = createCoreEngine({poseidonHashMany});
const V = createEngineV11(E);
const events = (r) => r.form.events.map(({time,duration,pitch,velocity,voice_id}) => [time,duration,pitch,velocity,voice_id]);
test('direct normalized score consumes independent theme, score, treatment and identity controls', () => {
  const base = V.renderInputs(normalizedCase(0));
  for (let i=1;i<SCORE_CASE_COUNT;i++) {
    const changed = V.renderInputs(normalizedCase(i));
    if (i === 15 || i === 19) {
      // Normal gates already hold their full durations; tenuto intentionally
      // has the same notes. Tempo is carried to the later MIDI writer.
      assert.deepEqual(events(changed), events(base));
      if (i === 19) assert.equal(changed.params.tempo_us,400001);
    } else assert.notDeepEqual(events(changed), events(base), `score control ${i} discarded`);
    for (const e of changed.form.events) {
      assert(e.pitch >=24 && e.pitch <=108, `pitch ${i}`);
      assert(e.velocity >=1 && e.velocity <=changed.params.velocity_ceiling, `velocity ${i}`);
      assert(e.duration >=60 && e.time+e.duration <= changed.form.section_ticks*changed.form.sections.length, `time ${i}`);
    }
  }
});
