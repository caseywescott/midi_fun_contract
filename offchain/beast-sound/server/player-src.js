// Beast Sound player: the page behind a Beast's `animation_url`.
//
// The server inlines the Beast's notes (window.BEAST) into the HTML, so the page needs no network
// access and works inside marketplace iframes. Tap to start (browsers require a gesture); the theme
// loops until stopped. Synthesis is the simulator's patch library (Triangle lead by default).
import { createKit, PATCH_BY_ID, chipDrum } from '../../../web/beast_sound/patches.js';
import { createLoopScheduler } from './scheduler.js';

const B = window.BEAST;
const $ = (id) => document.getElementById(id);
const LITE = (() => { try { return matchMedia('(pointer: coarse)').matches; } catch { return false; } })();
const LOOKAHEAD = LITE ? 0.6 : 0.35;
let ctx = null, kit = null, out = null, comp = null, playing = null;

function ensureAudio() {
  if (ctx) return;
  const AC = window.AudioContext || window.webkitAudioContext;
  try { ctx = new AC({ latencyHint: 'playback' }); } catch { ctx = new AC(); }
  comp = ctx.createDynamicsCompressor(); comp.threshold.value = -18; comp.ratio.value = 3; comp.connect(ctx.destination);
  out = ctx.createGain(); out.gain.value = 1; out.connect(comp);
  kit = createKit(ctx);
}
function unlock() {
  ensureAudio();
  if (ctx.state !== 'running') ctx.resume().catch(() => {});
  try { const b = ctx.createBuffer(1, 1, ctx.sampleRate), s = ctx.createBufferSource(); s.buffer = b; s.connect(ctx.destination); s.start(0); } catch { /* not needed */ }
}

function play() {
  unlock();
  const notes = B.notes; // [time, duration, pitch, velocity, voice] in ticks (480 per beat)
  const tick = B.tempo_us / 1e6 / 480;
  const voices = [...new Set(notes.map((n) => n[4]))].sort((a, b) => a - b);
  const buses = voices.map((v, i) => {
    const p = ctx.createStereoPanner(); p.pan.value = voices.length < 2 ? 0 : -0.85 + (1.7 * i) / (voices.length - 1); p.connect(out); return p;
  });
  const patch = PATCH_BY_ID[B.patch] || PATCH_BY_ID.chip_tri_lead;
  const sched = createLoopScheduler(notes, {
    tick, length: B.length_ticks,
    drums: B.drums,
    onNote: (n, t) => patch.play(kit, buses[voices.indexOf(n[4])], t, n[1] * tick, 440 * 2 ** ((n[2] - 69) / 12), 0.16 * (n[3] / 127) * patch.gain),
    onDrum: (d, t) => chipDrum(kit, out, t, d.kind, d.level),
  });
  const p = { started: false, raf: 0, timer: 0 };
  playing = p;
  const pump = () => {
    if (playing !== p) return;
    if (!p.started) { if (ctx.state !== 'running') return; sched.start(ctx.currentTime); p.started = true; }
    sched.pump(ctx.currentTime + LOOKAHEAD);
  };
  pump();
  p.timer = setInterval(pump, 40);
  const bar = $('bar');
  const step = () => {
    if (playing !== p) return;
    if (p.started) bar.style.width = `${(100 * sched.position(ctx.currentTime)) / sched.loopTicks}%`;
    p.raf = requestAnimationFrame(step);
  };
  step();
  $('play').textContent = '■ STOP';
}
function stop() {
  if (!playing) return;
  clearInterval(playing.timer); cancelAnimationFrame(playing.raf); playing = null;
  const now = ctx.currentTime;
  out.gain.setValueAtTime(out.gain.value, now); out.gain.linearRampToValueAtTime(0, now + 0.08);
  const old = out; setTimeout(() => old.disconnect(), 300);
  out = ctx.createGain(); out.connect(comp);
  $('bar').style.width = '0%';
  $('play').textContent = '▶ PLAY';
}
$('play').addEventListener('click', () => (playing ? stop() : play()));
