// The sampler's playback buffers (decoded and upsampled for the AudioContext's rate) built by the reference
// bank script and by the pack, for one zone of every instrument and drum, compared value for value.
//   node pack/sampler-parity.mjs [sample rate, default 48000]
import { readFileSync } from 'node:fs';
const rate = +(process.argv[2] ?? 48000);
const load = (file) => {
  const win = {}, fail = () => { throw new Error('no workers'); };
  new Function('window', 'self', 'navigator', 'URL', 'Blob', 'Worker', 'setTimeout', 'atob', readFileSync(file, 'utf8'))(win, win, {}, { createObjectURL: fail }, class {}, class {}, () => 0, (s) => Buffer.from(s, 'base64').toString('binary'));
  return win.SnesBank;
};
// an AudioContext that only keeps what the sampler puts in its buffers
const param = () => ({ value: 0, setValueAtTime() {}, linearRampToValueAtTime() {}, cancelScheduledValues() {} });
const node = () => ({ connect() {}, disconnect() {}, gain: param(), frequency: param(), Q: param(), delayTime: param(), playbackRate: param(), detune: param(), start() {}, stop() {} });
const context = (got) => ({ sampleRate: rate, currentTime: 0, destination: node(), createGain: node, createBiquadFilter: node, createDelay: node, createConvolver: node,
  createBuffer: (ch, length, sr) => { const data = new Float32Array(length); return { length, sampleRate: sr, duration: length / sr, getChannelData: () => data }; },
  createBufferSource: () => { const n = node(); return new Proxy(n, { set(t, k, v) { if (k === 'buffer') got.push(v); t[k] = v; return true; } }); } });
const run = (bank) => { const got = [], s = bank.createSampler(context(got)); const seen = new Set();
  for (const i of bank.bank.instruments) { const key = i.drum !== undefined ? 'd' + i.drum : i.id.replace(/-\d+$/, ''); if (seen.has(key)) continue; seen.add(key);
    s.noteOn(i.drum !== undefined ? { drum: true, note: i.drum, time: 0 } : { program: i.program, note: i.rootNote, time: 0 }); }
  return { got, ids: [...seen] }; };
const a = run(load('kankyo.min.js')), b = run(load('dist/loot-fm-pack.min.js'));
let same = 0;
a.got.forEach((x, n) => { const y = b.got[n], p = x.getChannelData(), q = y.getChannelData(); let d = x.length === y.length && x.sampleRate === y.sampleRate; for (let i = 0; d && i < p.length; i++) if (p[i] !== q[i]) d = false; if (d) same++; else console.log('DIFFERS', a.ids[n]); });
console.log(`${rate} Hz: ${same}/${a.got.length} playback buffers identical (${a.got.reduce((s, x) => s + x.length, 0)} samples)`);
process.exitCode = same === a.got.length ? 0 : 1;
