// Dependency-free PCM WAV ingestion and band-limited resampling. Build-time only.
export function readWav(bytes) {
  const b = Buffer.from(bytes);
  if (b.length < 12 || b.toString('ascii', 0, 4) !== 'RIFF' || b.toString('ascii', 8, 12) !== 'WAVE') throw new Error('Expected RIFF/WAVE');
  const end = b.readUInt32LE(4) + 8;
  if (end > b.length) throw new Error('Truncated WAV');
  let fmt, data;
  for (let p = 12; p + 8 <= end;) {
    const size = b.readUInt32LE(p + 4), start = p + 8;
    if (start + size > end) throw new Error('Truncated WAV chunk');
    const id = b.toString('ascii', p, p + 4);
    if (id === 'fmt ') fmt = b.subarray(start, start + size);
    if (id === 'data') data = b.subarray(start, start + size);
    p = start + size + (size & 1);
  }
  if (!fmt || fmt.length < 16 || !data?.length) throw new Error('WAV needs fmt and data chunks');
  const type = fmt.readUInt16LE(0), channels = fmt.readUInt16LE(2), rate = fmt.readUInt32LE(4), bits = fmt.readUInt16LE(14), stride = fmt.readUInt16LE(12);
  if (![1, 2].includes(channels) || rate < 8000 || rate > 192000 || !((type === 1 && [8, 16, 24, 32].includes(bits)) || (type === 3 && bits === 32)) || stride !== channels * bits / 8 || data.length % stride) throw new Error('Use mono/stereo PCM 8/16/24/32-bit or float32 WAV at 8–192 kHz');
  const pcm = new Float64Array(data.length / stride);
  for (let i = 0; i < pcm.length; i++) {
    for (let ch = 0; ch < channels; ch++) {
      const p = i * stride + ch * bits / 8;
      const v = type === 3 ? data.readFloatLE(p) : bits === 8 ? (data[p] - 128) / 128 : data.readIntLE(p, bits / 8) / 2 ** (bits - 1);
      if (!Number.isFinite(v)) throw new Error('Non-finite WAV sample');
      pcm[i] += v / channels;
    }
  }
  return { pcm, rate };
}

export function prepare(wav, options = {}) {
  const rate = options.sampleRate ?? 16000;
  if (!Number.isInteger(rate) || rate < 16000 || rate > 32000) throw new Error('sampleRate must be 16000–32000');
  const start = options.trimStart ?? 0, end = options.trimEnd ?? wav.pcm.length / wav.rate;
  if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || end <= start || end > wav.pcm.length / wav.rate + 1e-9 || end - start > 4) throw new Error('Trim must select 0–4 seconds inside the WAV');
  const frames = Math.round((end - start) * rate), looping = options.loopStart !== undefined && options.loopStart !== null;
  if (frames < 16) throw new Error('Sample is shorter than one BRR block');
  // Loop trims DOWN to a block boundary; one-shot pads with silence.
  const count = (looping ? Math.floor(frames / 16) : Math.ceil(frames / 16)) * 16;
  const loopStart = looping ? Math.round(options.loopStart * rate / 16) * 16 : null;
  if (looping && (!Number.isFinite(options.loopStart) || options.loopStart < 0 || loopStart >= count)) throw new Error('loopStart is seconds relative to the trimmed sample, before its end');
  const out = new Float64Array(count), cutoff = Math.min(1, rate / wav.rate) * 0.90;
  const radius = Math.ceil(24 / cutoff), sinc = (x) => x === 0 ? 1 : Math.sin(Math.PI * x) / (Math.PI * x);
  const lo = Math.ceil(start * wav.rate), hi = Math.min(wav.pcm.length - 1, Math.ceil(end * wav.rate) - 1);
  for (let i = 0; i < Math.min(count, frames); i++) {
    const position = start * wav.rate + i * wav.rate / rate;
    let sum = 0, weight = 0;
    for (let j = Math.ceil(position - radius); j <= Math.floor(position + radius); j++) {
      const d = j - position, w = cutoff * sinc(d * cutoff) * (0.5 + 0.5 * Math.cos(Math.PI * d / radius));
      sum += wav.pcm[Math.max(lo, Math.min(hi, j))] * w; weight += w;
    }
    out[i] = sum / weight;
  }
  // Headroom helps predictive BRR avoid wraparound. Never amplify by default.
  const gain = options.gain ?? 1;
  if (!Number.isFinite(gain) || gain < 0 || gain > 8) throw new Error('gain must be 0–8');
  const pcm = Int16Array.from(out, (v) => Math.round(Math.max(-0.9, Math.min(0.9, v * gain)) * 32767));
  return { pcm, rate, loopStart };
}
