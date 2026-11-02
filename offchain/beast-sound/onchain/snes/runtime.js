import { decodeBRR } from './brr.js';
import { envelope, fromBase64, validateBank } from './bank.js';

// Decode once per AudioContext. Browser resampling + binomial smoothing approximate
// the soft SNES character; this is deliberately not a cycle-accurate S-DSP emulator.
export function createSampler(ac, bank, { maxVoices = 8, smoothing = true, echo = true } = {}) {
  validateBank(bank);
  if (!Number.isInteger(maxVoices) || maxVoices < 1 || maxVoices > 64) throw new Error('maxVoices must be 1–64');
  const buffers = new Map(), buses = new Map(), voices = new Set();
  const programs = new Map(), drums = new Map();
  for (const inst of bank.instruments) (inst.drum === undefined ? programs : drums).set(inst.drum ?? inst.program, inst);
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
    for (let i = 0; i < pcm.length; i++) out[i] = smoothing
      ? (read(i - 2, i) + 4 * read(i - 1, i) + 6 * read(i, i) + 4 * read(i + 1, i) + read(i + 2, i)) / 16 : pcm[i] / 32768;
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
  function level(voice, time) {
    const dt = Math.max(0, time - voice.start), e = voice.env;
    if (e.attack && dt < e.attack) return voice.peak * dt / e.attack;
    if (e.decay && dt < e.attack + e.decay) return voice.peak * (1 - (1 - e.sustain) * (dt - e.attack) / e.decay);
    return voice.peak * e.sustain;
  }
  function release(voice, time) {
    if (voice.released) return;
    const t = Math.max(ac.currentTime, time, voice.start), g = voice.gain.gain;
    voice.released = true;
    g.cancelScheduledValues(t); g.setValueAtTime(level(voice, t), t);
    g.linearRampToValueAtTime(0, t + voice.env.release);
    voice.end = Math.min(voice.end, t + voice.env.release + 0.002);
    voice.source.stop(voice.end);
  }
  function kill(voice, time) {
    const t = Math.max(ac.currentTime, time);
    voice.gain.gain.cancelScheduledValues(t); voice.gain.gain.setValueAtTime(0, t);
    voice.end = Math.min(voice.end, t); voice.source.stop(voice.end);
  }
  const api = {
    get activeVoices() { return [...voices].filter((v) => v.start <= ac.currentTime && v.end > ac.currentTime).length; },
    noteOn({ channel = 0, program = 0, drum = false, note, velocity = 100, time = ac.currentTime, destination = ac.destination, bend = 0 }) {
      if (disposed) throw new Error('Sampler is disposed');
      const inst = (drum ? drums : programs).get(drum ? note : program);
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
      const peak = inst.volume * (velocity / 127) ** 2;
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
