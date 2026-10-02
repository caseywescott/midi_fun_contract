// Player layer: plays any song through the chip synth. Every call returns its own handle, so
// several songs can play at once, each into its own (or a caller's) audio graph.
import { createLoopScheduler } from '../../server/scheduler.js';
import { instrument, presets, drum } from './synth.js';
import { TICKS_PER_BEAT } from './song.js';

let shared = null;
const LOOKAHEAD = (() => { try { return matchMedia('(pointer: coarse)').matches ? 0.6 : 0.35; } catch { return 0.35; } })();

/** The library's AudioContext, created and unlocked on first use (call from a user gesture). */
export function context() {
  if (!shared) {
    const AC = window.AudioContext || window.webkitAudioContext;
    try { shared = new AC({ latencyHint: 'playback' }); } catch { shared = new AC(); }
  }
  if (shared.state !== 'running') shared.resume().catch(() => {});
  // iOS: a silent buffer inside the gesture unlocks output
  try { const s = shared.createBufferSource(); s.buffer = shared.createBuffer(1, 1, shared.sampleRate); s.connect(shared.destination); s.start(0); } catch { /* not needed */ }
  return shared;
}

const DEFAULT = instrument(presets.triangleLead);

/**
 * Play a song. Options:
 *   instruments  one instrument, an array (by voice order), or (voice) => instrument
 *   drums        true (default) | false
 *   loop         true (default) | false (stops after one pass)
 *   destination  an AudioNode to play into (its context is used); default: the speakers
 *   volume       0–1+ (default 1)
 * @returns handle { stop(), playing, position() 0–1, onNote(fn), onEnd(fn) }
 */
export function play(song, { instruments = DEFAULT, drums = true, loop = true, destination, volume = 1 } = {}) {
  const ac = destination ? destination.context : context();
  const comp = ac.createDynamicsCompressor(); comp.threshold.value = -18; comp.ratio.value = 3;
  comp.connect(destination || ac.destination);
  const out = ac.createGain(); out.gain.value = volume; out.connect(comp);
  const kit = { ac };
  const tick = song.tempo_us / 1e6 / TICKS_PER_BEAT;
  const voices = [...new Set(song.notes.map((n) => n[4]))].sort((a, b) => a - b);
  const pick = (voice) => (typeof instruments === 'function' ? instruments(voice) : Array.isArray(instruments) ? instruments[voices.indexOf(voice) % instruments.length] : instruments);
  const buses = voices.map((v, i) => {
    const p = ac.createStereoPanner(); p.pan.value = voices.length < 2 ? 0 : -0.85 + (1.7 * i) / (voices.length - 1); p.connect(out); return p;
  });
  const noteFns = new Set(), endFns = new Set();
  const sched = createLoopScheduler(song.notes, {
    tick, drums, loop,
    onNote: (n, t) => {
      const inst = pick(n[4]);
      inst.play(kit, buses[voices.indexOf(n[4])], t, n[1] * tick, 440 * 2 ** ((n[2] - 69) / 12), 0.16 * (n[3] / 127) * inst.gain);
      if (noteFns.size) setTimeout(() => handle.playing && noteFns.forEach((fn) => fn(n)), Math.max(0, (t - ac.currentTime) * 1000));
    },
    onDrum: (d, t) => drum(kit, out, t, d.kind, d.level),
  });
  let started = false, timer = 0;
  const handle = {
    playing: true,
    stop() {
      if (!handle.playing) return;
      handle.playing = false;
      clearInterval(timer);
      const now = ac.currentTime;
      out.gain.setValueAtTime(out.gain.value, now); out.gain.linearRampToValueAtTime(0, now + 0.08);
      setTimeout(() => { out.disconnect(); comp.disconnect(); }, 300);
      endFns.forEach((fn) => fn());
    },
    position: () => (started ? sched.position(ac.currentTime) / sched.loopTicks : 0),
    onNote: (fn) => { noteFns.add(fn); return () => noteFns.delete(fn); },
    onEnd: (fn) => { endFns.add(fn); return () => endFns.delete(fn); },
  };
  const pump = () => {
    if (!handle.playing) return;
    if (!started) { if (ac.state !== 'running') return; sched.start(ac.currentTime); started = true; }
    if (!loop && ac.currentTime > sched.endTime() + 0.3) return handle.stop();
    sched.pump(ac.currentTime + LOOKAHEAD);
  };
  timer = setInterval(pump, 40);
  pump();
  return handle;
}
