// TinySynth sound page player: stored onchain once, embedded in every token's animation_url.
//
// Generic: it plays whatever Standard MIDI File the page carries and knows nothing about the
// collection that composed it. The page is
//   [TinySynth + this script]
//   <script type="text/plain" id="midi"> base64 MIDI </script>
//   <script type="text/plain" id="art"> the token's SVG
// Both blocks follow this script, so it waits for the document. The SVG is shown through an <img>
// (it may use XML-only syntax the HTML parser cannot inline). Audio starts on a click or tap and
// loops in whole bars; nothing is fetched.
//
// Orchestration v1 (player-core.js): a bare score (no program changes, no channel 10) plays every
// channel with the chip lead, spread across the stereo field, over a kick/snare/hi-hat pattern
// whose hi-hat levels are rolled again on every Play. Any other score plays as written with
// TinySynth's General MIDI set.
import {
  LEAD, LEAD_PROGRAM, ORCHESTRATION, decodeMidi, drumEvents, isBareScore, loopEndTicks, noteChannels, panValue,
} from './player-core.js';

let midi = null, synth = null, base = null, bare = false, playing = false;

addEventListener('DOMContentLoaded', () => {
  const art = document.getElementById('art');
  if (art) {
    const img = document.createElement('img');
    img.alt = '';
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(art.textContent.trim());
    document.body.insertBefore(img, document.body.firstChild);
  }
  const block = document.getElementById('midi');
  midi = block && decodeMidi(block.textContent);
  if (!midi) controls.remove();
});

function load() {
  // Created inside the first tap, so TinySynth's own AudioContext starts running.
  synth = new window.WebAudioTinySynth({ quality: 1, useReverb: 0, voices: 64 });
  synth.loadMIDI(midi.slice().buffer);
  base = synth.song.ev.slice();
  bare = isBareScore(base);
  synth.loopEnd = loopEndTicks(synth.maxTick, synth.song.timebase);
  synth.setLoop(1);
  if (bare) {
    synth.program[LEAD_PROGRAM] = { name: 'Chip lead', p: LEAD };
    const channels = noteChannels(base);
    channels.forEach((ch, i) => {
      synth.setProgram(ch, LEAD_PROGRAM);
      synth.setPan(ch, panValue(i, channels.length));
    });
  }
}

function play() {
  if (!midi) return;
  if (!synth) load();
  const ac = synth.getAudioContext();
  if (ac.state !== 'running') ac.resume().catch(() => {});
  if (bare) {
    const ppq = synth.song.timebase / 4;
    synth.song.ev = base.concat(drumEvents(synth.loopEnd, ppq)).sort((x, y) => x.t - y.t);
  }
  synth.locateMIDI(0);
  synth.playMIDI();
  playing = true;
  toggle.textContent = '■';
  toggle.setAttribute('aria-label', 'Stop sound');
}

function stop() {
  synth.stopMIDI();
  playing = false;
  toggle.textContent = '♪';
  toggle.setAttribute('aria-label', 'Play sound');
}

const button = (label, text, right) => {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = text;
  b.setAttribute('aria-label', label);
  b.style.cssText = `position:fixed;right:${right}px;bottom:12px;width:44px;height:44px;border-radius:50%;border:1px solid rgba(255,255,255,.35);background:rgba(0,0,0,.55);color:#fff;font:20px/1 system-ui,sans-serif;cursor:pointer;z-index:1`;
  return b;
};
const controls = document.createElement('div');
const toggle = button('Play sound', '♪', 12);
const restart = button('Restart', '↺', 64);
restart.addEventListener('click', (e) => { e.stopPropagation(); play(); });
controls.append(restart, toggle);
document.body.appendChild(controls);
// Tap anywhere (art or button) toggles; browsers only start audio from a gesture.
document.addEventListener('click', () => (playing ? stop() : play()));

// Read-only handle for inspection and tests.
window.SOUND = { orchestration: ORCHESTRATION, get midi() { return midi; }, get synth() { return synth; }, get bare() { return bare; } };
