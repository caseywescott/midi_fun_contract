// Cue extraction (onchain/cues/cues.js): read from the composer's render result, the default MIDI left
// byte for byte as it was, and the optional FF 06 marker track as a separate file.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { engine as E } from '../src/index.js';
import { createEngineV11 } from '../src/engine_v11.js';
import { genesisMidi } from '../src/lab.js';
import { songCues, withCueTrack, readMarkers, midiNotes, markerText } from '../onchain/cues/cues.js';

const v11 = createEngineV11(E);
// sha256 over the 150 Species Songs (species 1-75, regular then shiny) as origin/main 89a16b3 writes them
const GENESIS_150 = '6cac6a2c39963731644fe6b54e2d44292cd98cfd790e55a85e8ac88ec2cb2f7f';

test('extracting cues leaves every Species Song MIDI unchanged', () => {
  const h = createHash('sha256');
  for (let id = 1; id <= 75; id++) for (const s of [0, 1]) {
    const r = genesisMidi(id, s, E, v11), before = Buffer.from(r.midi);
    const cues = songCues(r.result, r.midi);
    assert.ok(cues.cues.length > 0);
    assert.deepEqual(Buffer.from(r.midi), before, `species ${id}: cues must not touch the MIDI`);
    h.update(before);
  }
  assert.equal(h.digest('hex'), GENESIS_150);
});

test('cues follow the composer structure', () => {
  const r = genesisMidi(3, 1, E, v11), c = songCues(r.result, r.midi);
  assert.equal(c.source, 'engine');
  assert.equal(c.length, E.formLength(r.result.form));
  const of = (t) => c.cues.filter((x) => x.type === t);
  assert.equal(of('section').length, r.result.form.sections.length);
  assert.equal(of('cadence').filter((x) => x.final).length, 1);
  assert.equal(of('climax').length, 1);
  assert.equal(of('bar').length, c.length / c.bar);
  // every section has the theme entering in voice 0 on its downbeat
  for (const s of of('section')) assert.ok(c.cues.some((x) => x.type === 'entry' && x.voice === 0 && x.tick === s.tick));
  // entries sit on real note-ons of their channel
  const ons = new Set(c.notes.map((n) => n[1] + ':' + n[0]));
  for (const e of of('entry')) assert.ok(ons.has(e.voice + ':' + e.tick));
});

test('the marker track is a separate file: same notes, markers readable, header +1 track', () => {
  for (const id of [3, 49, 65, 68]) {
    const r = genesisMidi(id, 0, E, v11), c = songCues(r.result, r.midi);
    const midi = Uint8Array.from(r.midi), cued = withCueTrack(midi, c.cues);
    assert.deepEqual(Buffer.from(cued.subarray(14, midi.length)), Buffer.from(midi.subarray(14)));
    assert.equal(((cued[10] << 8) | cued[11]), ((midi[10] << 8) | midi[11]) + 1);
    assert.deepEqual(midiNotes(cued).notes, midiNotes(midi).notes);
    assert.equal(midiNotes(cued).length, midiNotes(midi).length);
    const want = c.cues.filter((x) => x.type !== 'bar').map((x) => ({ tick: x.tick, text: markerText(x) }));
    assert.deepEqual(readMarkers(cued).map((m) => m.tick + m.text).sort(), want.map((m) => m.tick + m.text).sort());
  }
});

test('a track without roles falls back to cues from the MIDI', () => {
  const r = genesisMidi(44, 0, E, v11), c = songCues(r.result, r.midi); // the authored Satori song
  assert.equal(c.source, 'midi');
  assert.ok(c.cues.some((x) => x.type === 'cadence' && x.final));
  assert.ok(c.cues.some((x) => x.type === 'climax'));
});
