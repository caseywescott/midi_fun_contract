import { decodeBRR } from './brr.js';
import { envelope, fromBase64, validateBank } from './bank.js';

// Decode once per AudioContext. Binomial smoothing approximates the soft SNES character; this is
// deliberately not a cycle-accurate S-DSP emulator. `upsample` raises each decoded sample by a whole
// factor (to at least the context rate) with a windowed sinc before the browser plays it: the browser's
// own resampler is linear interpolation, which leaves audible images of a 12-16 kHz sample in the
// 6-12 kHz band. A whole factor keeps loop points on exact frames. `softSteal` fades a stolen or
// stopped voice over 5 ms instead of cutting it. The old behaviour: { upsample: false,
// softSteal: false, maxVoices: 8 }.
const STEAL_FADE = 0.005;
// The sample layer's level against TinySynth: with it, each instrument's manifest volume puts a stem at
// the loudness the TinyChip presets gave the same part (measured 10 Nov 2026, integrated LUFS, per stem).
export const LEVEL = 2.5;
export function createSampler(ac, bank, { maxVoices = 16, smoothing = true, echo = true, upsample = true, softSteal = true, layerGain = LEVEL } = {}) {
  validateBank(bank);
  if (!Number.isInteger(maxVoices) || maxVoices < 1 || maxVoices > 64) throw new Error('maxVoices must be 1–64');
  const buffers = new Map(), buses = new Map(), voices = new Set();
  const programs = new Map(), drums = new Map();
  for (const inst of bank.instruments) { const m = inst.drum === undefined ? programs : drums, k = inst.drum ?? inst.program; m.set(k, [...(m.get(k) ?? []), inst]); }
  // the zone for a note: the one whose key range holds it, else the nearest range
  const zone = (zones, note) => zones && (zones.find((i) => !i.keys || (note >= i.keys[0] && note <= i.keys[1]))
    ?? zones.reduce((a, b) => (Math.min(Math.abs(note - a.keys[0]), Math.abs(note - a.keys[1])) <= Math.min(Math.abs(note - b.keys[0]), Math.abs(note - b.keys[1])) ? a : b)));
  let disposed = false;
  function buffer(index) {
    if (buffers.has(index)) return buffers.get(index);
    const sample = bank.samples[index], pcm = decodeBRR(fromBase64(sample.data), sample.loopStart);
    const result = ac.createBuffer(1, pcm.length, sample.rate), out = result.getChannelData(0);
    const read = (i, center) => {
      if (sample.loopStart !== null && center >= sample.loopStart) {
        const length = pcm.length - sample.loopStart;
        i = sample.loopStart + ((i - sample.loopStart) % length + length) % length;
      }
      return pcm[Math.max(0, Math.min(pcm.length - 1, i))] / 32768;
    };
    // a sample marked `smoothing: false` keeps its top end (recordings meant to sound as recorded)
    for (let i = 0; i < pcm.length; i++) out[i] = smoothing && sample.smoothing !== false
      ? (read(i - 2, i) + 4 * read(i - 1, i) + 6 * read(i, i) + 4 * read(i + 1, i) + read(i + 2, i)) / 16 : pcm[i] / 32768;
    const k = upsample ? Math.max(1, Math.ceil(ac.sampleRate / sample.rate)) : 1;
    if (k > 1) {
      // Windowed sinc (8 source samples each side, cutoff 0.95 of the source Nyquist), reading
      // through the loop so the seam is interpolated as it plays.
      const src = out.slice(), n = src.length, R = 8, fc = 0.95, up = ac.createBuffer(1, n * k, sample.rate * k), dst = up.getChannelData(0);
      const at = (i, center) => {
        if (sample.loopStart !== null && center >= sample.loopStart) { const length = n - sample.loopStart; i = sample.loopStart + ((i - sample.loopStart) % length + length) % length; }
        return src[Math.max(0, Math.min(n - 1, i))];
      };
      const taps = [];
      for (let f = 0; f < k; f++) {
        const row = [];
        for (let j = -R + 1; j <= R; j++) { const d = j - f / k, x = Math.PI * fc * d; row.push(fc * (d === 0 ? 1 : Math.sin(x) / x) * (0.5 + 0.5 * Math.cos(Math.PI * d / R))); }
        const sum = row.reduce((a, b) => a + b, 0); taps.push(row.map((w) => w / sum));
      }
      for (let i = 0; i < n; i++) for (let f = 0; f < k; f++) {
        let v = 0; const row = taps[f];
        for (let j = -R + 1, t = 0; j <= R; j++, t++) v += row[t] * at(i + j, i);
        dst[i * k + f] = v;
      }
      buffers.set(index, up); return up;
    }
    buffers.set(index, result); return result;
  }
  function bus(destination) {
    if (buses.has(destination)) return buses.get(destination).input;
    const input = ac.createBiquadFilter(); input.type = 'lowpass'; input.frequency.value = 11000; input.Q.value = 0.5;
    input.connect(destination);
    const nodes = [input];
    if (echo) {
      const delay = ac.createDelay(0.25), fir = ac.createConvolver(), feedback = ac.createGain(), wet = ac.createGain();
      delay.delayTime.value = 0.096; feedback.gain.value = 0.28; wet.gain.value = 0.18;
      // Eight taps spread over the equivalent of 8 samples at 32 kHz.
      const ir = ac.createBuffer(1, Math.ceil(8 * ac.sampleRate / 32000), ac.sampleRate);
      const data = ir.getChannelData(0), taps = [0.30, 0.25, 0.18, 0.12, 0.07, 0.04, 0.025, 0.015];
      taps.forEach((v, i) => { data[Math.round(i * ac.sampleRate / 32000)] += v; });
      fir.normalize = false; fir.buffer = ir;
      input.connect(delay); delay.connect(fir); fir.connect(wet); wet.connect(destination); fir.connect(feedback); feedback.connect(delay);
      nodes.push(delay, fir, feedback, wet);
    }
    buses.set(destination, { input, nodes }); return input;
  }
  // The envelope's level at `time`, including a release in progress.
  function level(voice, time) {
    if (voice.released) return time >= voice.relTime + voice.env.release ? 0 : voice.relLevel * (1 - (time - voice.relTime) / Math.max(1e-6, voice.env.release));
    const dt = Math.max(0, time - voice.start), e = voice.env;
    if (e.attack && dt < e.attack) return voice.peak * dt / e.attack;
    if (e.decay && dt < e.attack + e.decay) return voice.peak * (1 - (1 - e.sustain) * (dt - e.attack) / e.decay);
    return voice.peak * e.sustain;
  }
  function release(voice, time) {
    if (voice.released) return;
    const t = Math.max(ac.currentTime, time, voice.start), g = voice.gain.gain, from = level(voice, t);
    // Cancelling removes the ramp in progress, so redraw it up to `t` (a linear ramp to the level
    // it has reached there) instead of jumping from the ramp's start to that level: the click.
    g.cancelScheduledValues(t); g.linearRampToValueAtTime(from, t);
    g.linearRampToValueAtTime(0, t + voice.env.release);
    Object.assign(voice, { released: true, relTime: t, relLevel: from });
    voice.end = Math.min(voice.end, t + voice.env.release + 0.002);
    voice.source.stop(voice.end);
  }
  function kill(voice, time) {
    const t = Math.max(ac.currentTime, time), g = voice.gain.gain;
    if (!softSteal) {
      g.cancelScheduledValues(t); g.setValueAtTime(0, t);
      voice.end = Math.min(voice.end, t); voice.source.stop(voice.end); return;
    }
    // redraw the envelope up to the level it has reached, then fade it out
    const from = level(voice, t);
    g.cancelScheduledValues(t); g.linearRampToValueAtTime(from, t);
    g.linearRampToValueAtTime(0, t + STEAL_FADE);
    Object.assign(voice, { released: true, relTime: t, relLevel: from, env: { ...voice.env, release: STEAL_FADE } });
    voice.end = Math.min(voice.end, t + STEAL_FADE + 0.001); voice.source.stop(voice.end);
  }
  const api = {
    get activeVoices() { return [...voices].filter((v) => v.start <= ac.currentTime && v.end > ac.currentTime).length; },
    noteOn({ channel = 0, program = 0, drum = false, note, velocity = 100, time = ac.currentTime, destination = ac.destination, bend = 0 }) {
      if (disposed) throw new Error('Sampler is disposed');
      const inst = zone((drum ? drums : programs).get(drum ? note : program), note);
      if (!inst) return false; // caller may fall back to TinySynth
      if (velocity === 0) { api.noteOff(channel, note, time); return true; }
      if (![note, velocity, time, bend].every(Number.isFinite) || note < 0 || note > 127 || velocity < 0 || velocity > 127) throw new Error('Invalid note');
      const t = Math.max(ac.currentTime, time), sample = bank.samples[inst.sample], env = envelope(inst.envelope);
      // Scheduler submits notes chronologically. Pending future voices are not stolen early.
      const overlapping = [...voices].filter((v) => v.start <= t && v.end > t).sort((a, b) => a.start - b.start);
      while (overlapping.length >= maxVoices) kill(overlapping.shift(), t);
      const source = ac.createBufferSource(), gain = ac.createGain();
      source.buffer = buffer(inst.sample);
      source.loop = sample.loopStart !== null;
      if (source.loop) { source.loopStart = sample.loopStart / sample.rate; source.loopEnd = source.buffer.duration; }
      source.playbackRate.value = 2 ** ((note - inst.rootNote) / 12);
      source.detune.setValueAtTime(inst.tuneCents + bend, t);
      const peak = layerGain * inst.volume * (velocity / 127) ** 2;
      gain.gain.setValueAtTime(0, t); gain.gain.linearRampToValueAtTime(peak, t + env.attack);
      gain.gain.linearRampToValueAtTime(peak * env.sustain, t + env.attack + env.decay);
      source.connect(gain); gain.connect(bus(destination));
      const voice = { channel, note, source, gain, env, peak, start: t, end: Infinity, released: false, held: false, tune: inst.tuneCents };
      voices.add(voice);
      source.onended = () => { source.disconnect(); gain.disconnect(); voices.delete(voice); };
      source.start(t);
      // One-shots end naturally; loops require a note-off (drum loops get an automatic gate).
      if (!source.loop) voice.end = t + source.buffer.duration / (source.playbackRate.value * 2 ** ((inst.tuneCents + bend) / 1200));
      if (drum && source.loop) release(voice, t + env.attack + env.decay + 0.1);
      return true;
    },
    noteOff(channel, note, time = ac.currentTime, sustain = false) {
      for (const v of voices) if (v.channel === channel && v.note === note && v.start <= time && !v.released) {
        if (sustain) v.held = true; else release(v, time);
      }
    },
    releaseSustain(channel, time = ac.currentTime) {
      for (const v of voices) if (v.channel === channel && v.held) release(v, time);
    },
    bend(channel, cents, time = ac.currentTime) {
      for (const v of voices) if (v.channel === channel && v.start <= time) {
        v.source.detune.setValueAtTime(v.tune + cents, time);
        // Pitch changes alter one-shot duration; onended remains the authority for cleanup.
        if (!v.source.loop && !v.released) v.end = Infinity;
      }
    },
    stop(channel, time = ac.currentTime) {
      for (const v of [...voices]) if (channel === undefined || v.channel === channel) kill(v, time);
    },
    dispose() {
      api.stop(); for (const b of buses.values()) for (const n of b.nodes) n.disconnect();
      buses.clear(); buffers.clear(); disposed = true;
    },
  };
  return api;
}

// Adapter for the pinned Provable Games TinySynth fork; no vendor source edits.
// Its channel buses keep MIDI volume/expression/pan, and unmatched programs fall back.
export function attach(synth, bank, options) {
  if (synth.__snesSampler) throw new Error('SNES sampler already attached');
  const sampler = createSampler(synth.getAudioContext(), bank, options), original = {};
  const wrap = (name, fn) => { original[name] = synth[name]; synth[name] = (...args) => fn(original[name], ...args); };
  wrap('noteOn', (next, ch, note, velocity, time) => {
    if (!velocity) return synth.noteOff(ch, note, time);
    if (!sampler.noteOn({ channel: ch, note, velocity, time: synth._tsConv(time), program: synth.pg[ch], drum: !!synth.rhythm[ch], destination: synth.chvol[ch], bend: synth.bend[ch] })) next.call(synth, ch, note, velocity, time);
  });
  wrap('noteOff', (next, ch, note, time) => {
    if (!synth.rhythm[ch]) sampler.noteOff(ch, note, synth._tsConv(time), synth.sustain[ch] >= 64);
    next.call(synth, ch, note, time);
  });
  wrap('setSustain', (next, ch, value, time) => { next.call(synth, ch, value, time); if (value < 64) sampler.releaseSustain(ch, synth._tsConv(time)); });
  wrap('setBend', (next, ch, value, time) => { next.call(synth, ch, value, time); sampler.bend(ch, synth.bend[ch], synth._tsConv(time)); });
  wrap('allSoundOff', (next, ch) => { sampler.stop(ch); next.call(synth, ch); });
  wrap('resetAllControllers', (next, ch) => { next.call(synth, ch); sampler.bend(ch, 0); sampler.releaseSustain(ch); });
  synth.__snesSampler = sampler;
  return { sampler, orchestration: 'snes-brr-1', dispose() { sampler.dispose(); Object.assign(synth, original); delete synth.__snesSampler; } };
}
