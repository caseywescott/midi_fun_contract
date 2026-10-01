// Chiptune synthesis shared by the simulator, the hosted player and the onchain composer.
//
// Needs only an AudioContext: pass any object with `ac` as the kit. Kept separate from patches.js so
// a page that plays chip sounds alone (the token_uri composer) can bundle just this file.

// ── chiptune voices ───────────────────────────────────────────────
// Single-cycle looped buffers (no band-limiting, like sound-chip channels), volume stepped at
// 60 frames/s in 16 levels, and per-frame pitch effects (vibrato, arpeggio, blips, drops).
const FRAME = 1 / 60;
const CYCLE = 64; // samples per single-cycle waveform

function chipWaves(kit) {
  if (kit.chip) return kit.chip;
  const ac = kit.ac, sr = ac.sampleRate;
  const make = (values) => { const b = ac.createBuffer(1, values.length, sr); b.getChannelData(0).set(values); return b; };
  const pulse = (duty) => make(Array.from({ length: CYCLE }, (_, i) => (i < CYCLE * duty ? 0.5 : -0.5)));
  // NES triangle: 32 four-bit steps (15..0, 0..15), two samples each.
  const triSteps = [...Array.from({ length: 16 }, (_, i) => 15 - i), ...Array.from({ length: 16 }, (_, i) => i)];
  const tri = make(triSteps.flatMap((v) => [v / 7.5 - 1, v / 7.5 - 1]).map((v) => v * 0.6));
  // Game Boy-style wave channel: 4-bit sawtooth.
  const saw = make(Array.from({ length: CYCLE }, (_, i) => (Math.floor((i / CYCLE) * 16) / 7.5 - 1) * 0.45));
  // NES noise, short mode: 93-step periodic LFSR (bit 6 tap) gives a pitched metallic tone.
  const bits = []; let reg = 1;
  for (let i = 0; i < 93; i++) { const fb = (reg & 1) ^ ((reg >> 6) & 1); reg = (reg >> 1) | (fb << 14); bits.push(reg & 1 ? 0.4 : -0.4); }
  const noise = make(bits);
  // NES noise, long mode: 15-bit LFSR (bit 1 tap), period 32,767: white-ish hiss for snares.
  const hiss = []; let r2 = 1;
  for (let i = 0; i < 32767; i++) { const fb = (r2 & 1) ^ ((r2 >> 1) & 1); r2 = (r2 >> 1) | (fb << 14); hiss.push(r2 & 1 ? 0.5 : -0.5); }
  const longNoise = make(hiss);
  kit.chip = { p12: pulse(0.125), p25: pulse(0.25), p50: pulse(0.5), tri, saw, noise, longNoise, len: { p12: CYCLE, p25: CYCLE, p50: CYCLE, tri: CYCLE, saw: CYCLE, noise: 93 } };
  return kit.chip;
}

// Stepped 16-level envelope: attack frames up to `peak`, decay frames to `sustain` (0..1 of peak),
// hold until note-off, then release frames.
function chipEnvelope(param, t, dur, peak, { attack = 0, decay = 0, sustain = 1, release = 2 }) {
  const q = (v) => Math.round(v * 15) / 15;
  const at = (n) => t + n * FRAME;
  const end = t + Math.max(dur, FRAME);
  // Onset: a 3 ms ramp to the first level removes the click of jumping from silence to full
  // volume; every later step stays an instant 8-bit jump.
  const DECLICK = 0.003;
  const first = attack ? peak * q(1 / attack) : peak;
  param.setValueAtTime(0, t);
  param.linearRampToValueAtTime(first, t + DECLICK);
  let frame = 1;
  for (let i = 2; i <= attack && at(frame + 1) < end; i++) param.setValueAtTime(peak * q(i / attack), at(frame++));
  if (attack) frame--;
  let level = 1;
  for (let i = 1; i <= decay && at(frame + 1) < end; i++) { level = 1 - (1 - sustain) * (i / decay); param.setValueAtTime(peak * q(level), at(++frame)); }
  for (let i = 1; i <= release; i++) param.setValueAtTime(peak * q(level * (1 - i / release)), end + (i - 1) * FRAME);
  return end + release * FRAME;
}

export function chipVoice(kit, dest, t, dur, f, vel, o) {
  const ac = kit.ac, w = chipWaves(kit);
  const src = ac.createBufferSource(), g = ac.createGain();
  src.buffer = w[o.wave];
  src.loop = true;
  const base = ac.sampleRate / w.len[o.wave];
  src.playbackRate.value = (f * (o.octave ? 2 ** o.octave : 1)) / base;
  const stopAt = chipEnvelope(g.gain, t, dur, vel, o.env || {});
  const det = src.detune;
  if (o.arp) {
    // Arpeggio: cycle chord offsets (in cents) every `rate` frames for the whole note.
    const rate = o.arp.frames || 2;
    for (let k = 0, at = t; at < stopAt; k++, at += rate * FRAME) det.setValueAtTime(o.arp.cents[k % o.arp.cents.length], at);
  } else if (o.blip) {
    // Pitch blip: start `cents` away and step back to the note over a few frames.
    for (let k = 0; k <= o.blip.frames; k++) det.setValueAtTime(o.blip.cents * (1 - k / o.blip.frames), t + k * FRAME);
  } else if (o.drop) {
    // Bass drop: fall `cents` over the note's first frames and stay there.
    for (let k = 0; k <= o.drop.frames; k++) det.setValueAtTime(-o.drop.cents * (k / o.drop.frames), t + k * FRAME);
  }
  if (o.vib && dur > o.vib.delay) {
    const lfo = ac.createOscillator(), depth = ac.createGain();
    lfo.type = 'triangle'; lfo.frequency.value = o.vib.rate;
    depth.gain.setValueAtTime(0, t);
    depth.gain.setValueAtTime(o.vib.cents, t + o.vib.delay);
    lfo.connect(depth); depth.connect(det);
    lfo.start(t); lfo.stop(stopAt + 0.05);
  }
  src.connect(g); g.connect(dest);
  src.start(t); src.stop(stopAt + 0.05);
}

export const chip = (id, name, gain, opts) => ({ id, name, family: 'chip', gain, play: (kit, dest, t, dur, f, vel) => chipVoice(kit, dest, t, dur, f, vel, opts) });

// ── chiptune drums ────────────────────────────────────────────────
// kind: 'kick' (triangle pitch dive, NES style), 'snare' (long-mode LFSR noise + pulse body),
// 'hat' / 'openhat' (metallic short-mode noise, short or long stepped decay).
export function chipDrum(kit, dest, t, kind, level) {
  const ac = kit.ac, w = chipWaves(kit), sr = ac.sampleRate;
  const DECLICK = 0.003;
  if (kind === 'kick') {
    const src = ac.createBufferSource(), g = ac.createGain();
    src.buffer = w.tri; src.loop = true;
    const base = sr / w.tri.length;
    src.playbackRate.setValueAtTime(160 / base, t);
    src.playbackRate.exponentialRampToValueAtTime(45 / base, t + 0.09);
    g.gain.setValueAtTime(0, t);
    g.gain.linearRampToValueAtTime(level, t + DECLICK);
    g.gain.setValueAtTime(level, t + 0.04);
    g.gain.linearRampToValueAtTime(0, t + 0.17);
    src.connect(g); g.connect(dest);
    src.start(t); src.stop(t + 0.2);
    // short noise click on the beat
    const n = ac.createBufferSource(), ng = ac.createGain();
    n.buffer = w.longNoise; n.loop = true; n.playbackRate.value = 1;
    ng.gain.setValueAtTime(0, t); ng.gain.linearRampToValueAtTime(level * 0.25, t + 0.002); ng.gain.linearRampToValueAtTime(0, t + 0.012);
    n.connect(ng); ng.connect(dest);
    n.start(t, Math.random()); n.stop(t + 0.02);
    return;
  }
  if (kind === 'hat' || kind === 'openhat') {
    // Metallic short-mode noise pitched high (~6-7 kHz cycle), stepped decay; open hats ring longer.
    const n = ac.createBufferSource(), ng = ac.createGain();
    n.buffer = w.noise; n.loop = true;
    const base = sr / w.len.noise;
    n.playbackRate.value = (6200 + Math.random() * 900) / base;
    const steps = kind === 'openhat' ? 12 : 3;
    ng.gain.setValueAtTime(0, t);
    ng.gain.linearRampToValueAtTime(level, t + 0.002);
    for (let k = 1; k <= steps; k++) ng.gain.setValueAtTime(level * Math.round(15 * (1 - k / steps)) / 15, t + k * FRAME);
    const hp = ac.createBiquadFilter(); hp.type = 'highpass'; hp.frequency.value = 3000;
    n.connect(ng); ng.connect(hp); hp.connect(dest);
    n.start(t); n.stop(t + (steps + 1) * FRAME);
    return;
  }
  // snare: noise with a stepped (per-frame) decay
  const n = ac.createBufferSource(), ng = ac.createGain();
  n.buffer = w.longNoise; n.loop = true; n.playbackRate.value = 0.6;
  ng.gain.setValueAtTime(0, t);
  ng.gain.linearRampToValueAtTime(level, t + DECLICK);
  const STEPS = 9;
  for (let k = 1; k <= STEPS; k++) ng.gain.setValueAtTime(level * Math.round(15 * (1 - k / STEPS)) / 15, t + k * FRAME);
  n.connect(ng); ng.connect(dest);
  n.start(t, Math.random()); n.stop(t + (STEPS + 1) * FRAME);
  // pulse body with a quick pitch drop
  const b = ac.createBufferSource(), bg = ac.createGain();
  b.buffer = w.p50; b.loop = true;
  const base = sr / w.p50.length;
  b.playbackRate.setValueAtTime(200 / base, t);
  b.playbackRate.exponentialRampToValueAtTime(110 / base, t + 0.05);
  bg.gain.setValueAtTime(0, t); bg.gain.linearRampToValueAtTime(level * 0.35, t + DECLICK); bg.gain.linearRampToValueAtTime(0, t + 0.07);
  b.connect(bg); bg.connect(dest);
  b.start(t); b.stop(t + 0.09);
}
