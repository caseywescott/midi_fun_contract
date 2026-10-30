import test from 'node:test';
import assert from 'node:assert/strict';
import { playbackSeconds } from '../onchain/lab-card-preview.js';

test('card clock follows audible loop boundaries and resets when new MIDI is loaded', () => {
  const ctx = { currentTime: 0, outputLatency: 0.1 };
  let startTime = 0.2;
  const synth = { song: {}, getAudioContext: () => ctx, getPlayStatus: () => ({ startTime }) };
  assert.equal(playbackSeconds(synth), 0);
  ctx.currentTime = 1.3;
  assert.ok(Math.abs(playbackSeconds(synth) - 1) < 1e-9);
  // The sequencer is already scheduling the next loop, but it is not audible yet.
  startTime = 10.2;
  ctx.currentTime = 10.25;
  assert.ok(Math.abs(playbackSeconds(synth) - 9.95) < 1e-9);
  ctx.currentTime = 10.4;
  assert.ok(Math.abs(playbackSeconds(synth) - 0.1) < 1e-9);
  // A track switch must not reuse the old song's position during the startup lead-in.
  synth.song = {};
  startTime = 10.6;
  assert.equal(playbackSeconds(synth), 0);
  ctx.currentTime = 10.9;
  assert.ok(Math.abs(playbackSeconds(synth) - 0.2) < 1e-9);
});
