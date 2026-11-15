// Instruments the page builds when it loads, one buffer per key zone, for the sampler to play: additive
// resynthesis of a recorded note (sustained, or partials that each decay at their measured rate), FM,
// physical models (plucked string, struck bar and drum modes, clarinet, flute, bowed string), and a
// recorded attack joined to any of them. A definition is pitch-free; `zone` makes it for one note.
// Prototype for listening.
import { tone, rng, fft, RATE, N } from './synth.js';
import { decodeBRR } from '../brr.js';
import { fromBase91 } from '../pack.js';
export { RATE };
const TAU = 2 * Math.PI, hz = (m) => 440 * 2 ** ((m - 69) / 12);
const level = (y, a, b, lvl) => { let s = 0; for (let i = a; i < b; i++) s += y[i] * y[i]; const k = lvl / (Math.sqrt(s / (b - a)) || 1); for (let i = 0; i < y.length; i++) y[i] *= k; return y; };
const fade = (y, n = 640) => { for (let i = 0; i < n && i < y.length; i++) y[y.length - 1 - i] *= i / n; return y; };
const delay = (max) => { const b = new Float32Array(max); let w = 0; return { put(v) { b[w] = v; w = (w + 1) % max; }, get(d) { let r = w - d; while (r < 0) r += max; const i = r | 0, f = r - i; return b[i % max] * (1 - f) + b[(i + 1) % max] * f; } }; };

// additive, sustained: the nearest described note's harmonics at this pitch (synth.js)
const additive = (d, midi) => { const z = d.notes.reduce((a, b) => (Math.abs(b[0] - midi) < Math.abs(a[0] - midi) ? b : a)), f = hz(midi); return tone({ cycles: Math.round(f * N / RATE), amps: z[2].slice(0, Math.floor(14500 / f)), noise: z[3], cents: d.vib ? Math.min(z[1], 1.5) : z[1], voices: d.voices, vib: d.vib }, midi); };

// partials [ratio, dB, dB per second], each decaying on its own; an optional noise strike [dB, ms, lowpass]
function modal(d, midi) {
  const f = hz(midi), k = (f / hz(d.root ?? 60)) ** (d.dk ?? 0.5), slow = Math.min(...d.parts.filter((p) => p[1] > -30).map((p) => p[2])) * k;
  const n = Math.round(Math.min(d.len ?? 2.5, 55 / slow + 0.1) * RATE), y = new Float32Array(n);
  for (const [r, db, dec] of d.parts) {
    const fr = f * r; if (fr > 15000) continue;
    // `tilt`: dB per octave taken off the partials above the fundamental, which also die away faster
    const oct = Math.max(0, Math.log2(r)), tl = d.tilt ?? 0, w = TAU * fr / RATE, cw = Math.cos(w), sw = Math.sin(w), g = 10 ** (-dec * k * (1 + tl * oct / 12) / 20 / RATE); let s = 0, c = 1, e = 10 ** ((db - tl * oct) / 20);
    for (let i = 0; i < n; i++) { y[i] += e * s; const t = s * cw + c * sw; c = c * cw - s * sw; s = t; e *= g; }
  }
  if (d.strike) { const [db, ms, lp] = d.strike, rnd = rng(midi), g = Math.exp(-1000 / (ms * RATE)); let e = 10 ** (db / 20), z = 0; for (let i = 0; i < n && e > 1e-4; i++) { z += lp * ((rnd() * 2 - 1) * e - z); y[i] += z; e *= g; } }
  return fade(y);
}

// a patch's tone control: `eq`, fixed bands that do not follow the note (an instrument's body):
// ['p', Hz, Q, dB] a peak or dip, ['s', Hz, 1, dB] a high shelf, ['l', Hz, 1, dB] a low shelf, ['b', Hz, Q, dry] a bandpass with that
// much of the unfiltered sound mixed in; a fifth entry of 1 reads Hz as a multiple of the note (a band
// that does follow it). Then a 12 dB/octave lowpass at `lp` Hz,
// or `lpk` times the note plus `lpo` Hz if that is higher (so high notes keep their first overtones).
// A loop is run through twice so its ends still meet.
function tone12(d, f, y, loopStart) {
  const eq = (d.eq ?? []).map(([type, hz0, q, db, track]) => {
    const fc = Math.min(14000, track ? hz0 * f : hz0), A = 10 ** (db / 40), w = TAU * fc / RATE, cs = Math.cos(w), sn = Math.sin(w);
    if (type === 'l') { const r = 2 * Math.sqrt(A) * sn / 2 * Math.SQRT2, a0 = (A + 1) + (A - 1) * cs + r; return [A * ((A + 1) - (A - 1) * cs + r) / a0, 2 * A * ((A - 1) - (A + 1) * cs) / a0, A * ((A + 1) - (A - 1) * cs - r) / a0, -2 * ((A - 1) + (A + 1) * cs) / a0, ((A + 1) + (A - 1) * cs - r) / a0]; }
    if (type === 'b') { const al = sn / (2 * q), a0 = 1 + al; return [(al + db * a0) / a0, db * -2 * cs / a0, (-al + db * (1 - al)) / a0, -2 * cs / a0, (1 - al) / a0]; }
    if (type === 'p') { const al = sn / (2 * q), a0 = 1 + al / A; return [(1 + al * A) / a0, -2 * cs / a0, (1 - al * A) / a0, -2 * cs / a0, (1 - al / A) / a0]; }
    const al = sn / 2 * Math.SQRT2, r = 2 * Math.sqrt(A) * al, a0 = (A + 1) - (A - 1) * cs + r;
    return [A * ((A + 1) + (A - 1) * cs + r) / a0, -2 * A * ((A - 1) + (A + 1) * cs) / a0, A * ((A + 1) + (A - 1) * cs - r) / a0, 2 * ((A - 1) - (A + 1) * cs) / a0, ((A + 1) - (A - 1) * cs - r) / a0];
  });
  const c = d.lp || d.lpk ? 1 - Math.exp(-TAU * Math.min(14000, Math.max(d.lp ?? 0, (d.lpk ?? 0) * f + (d.lpo ?? 0))) / RATE) : 0;
  if (!c && !eq.length) return y;
  const st = eq.map(() => [0, 0, 0, 0]); let a = 0, b = 0;
  for (let pass = 0; pass < (loopStart ? 2 : 1); pass++) for (let i = pass ? loopStart : 0; i < y.length; i++) {
    let v = y[i];
    for (let k = 0; k < eq.length; k++) { const q = eq[k], z = st[k], o = q[0] * v + q[1] * z[0] + q[2] * z[1] - q[3] * z[2] - q[4] * z[3]; z[1] = z[0]; z[0] = v; z[3] = z[2]; z[2] = o; v = o; }
    if (c) { a += c * (v - a); b += c * (a - b); v = b; }
    if (pass || !loopStart || i < loopStart) y[i] = v; // the loop's first pass only settles the filters
  }
  return y;
}
// FM: operators [carrier ratio, modulator ratio, index at the attack, index held, index time constant (s),
// level, level decay dB/s (struck) or beat cycles over the loop (sustained), feedback, [ratio, index]]:
// a carrier with its modulator; `feedback` turns the modulator on itself (towards a sawtooth: bowed and
// brassy tones; eased off up the keyboard, where its overtones would fold), and the last pair is a
// second modulator stacked on the first (richer, less regular overtones).
function fm(d, midi) {
  const f = hz(midi), ease = Math.min(1, Math.sqrt(523 / f));
  if (!d.sus) {
    // Struck or plucked. Beyond the fields above an operator may give, after two unused places, `i2`
    // [index, s]: a second, slower stage the index settles to after the first (a bright attack, a warm
    // tail); its own attack time in s; and `dry`, to skip the pluck-position comb. `comb` is where along
    // the string it is plucked (0.08-0.48): the sound minus itself delayed by that fraction of a period,
    // which notches the harmonics at multiples of 1/position. `len` caps the seconds kept.
    const k = (f / hz(60)) ** (d.dk ?? 0.4), n = Math.round(Math.min(d.len ?? 2.5, 55 / (Math.min(...d.ops.map((o) => o[6])) * k) + 0.1) * RATE), y = new Float32Array(n), dry = d.comb ? new Float32Array(n) : y;
    for (const [cr, mr, i0, is, tau, lv, ad, fb = 0, st, , , i2, atk = 0, isDry] of d.ops) {
      if (f * cr > 14000) continue; // a negative ratio is a fixed frequency in Hz (a pick's click does not follow the note)
      const out = isDry ? dry : y, [is2, tau2] = i2 ?? [is, 1], wc = TAU * (cr < 0 ? -cr : f * cr) / RATE, wm = TAU * (mr < 0 ? -mr : f * mr) / RATE, w2 = st ? TAU * f * st[0] / RATE : 0, dec = Math.exp(-ad * k * Math.LN10 / 20 / RATE); let m1 = 0, m2 = 0, amp = lv;
      for (let i = 0; i < n; i++) { const t = i / RATE, e = Math.exp(-t / tau), m = Math.sin(wm * i + fb * ease * 0.5 * (m1 + m2) + (st ? st[1] * (0.15 + 0.85 * e) * Math.sin(w2 * i) : 0)); m2 = m1; m1 = m;
        out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(wc * i + (is2 + (is - is2) * Math.exp(-t / tau2) + (i0 - is) * e) * m); amp *= dec; }
    }
    if (d.trem) for (let i = 0; i < n; i++) y[i] *= 1 + d.trem[0] * Math.sin(TAU * d.trem[1] * i / RATE); // a vibraphone's motor: [depth, Hz]
    if (d.comb) { const D = d.comb * RATE / f, g = 1 / (2 * Math.sin(Math.PI * d.comb)); for (let i = n - 1; i >= 0; i--) { const x = i - D, j = Math.floor(x), fr = x - j; y[i] = (y[i] - (j >= 0 ? y[j] * (1 - fr) + y[j + 1] * fr : 0)) * g + dry[i]; } }
    return fade(tone12(d, f, y, 0));
  }
  // Sustained: `pre` samples of attack, then a loop. `vib` is [cents, cycles in the loop, delay s, fade s]:
  // with a delay the vibrato arrives during the attack, so short notes stay plain. `vibAmp`, `vibIdx` and
  // the air's `vib` move level, brightness and breath with it. `drift` is a slow pitch wander in cents and
  // `scoop` [cents, s] a dip as the note is tongued. The attack's pitch is integrated back from the loop's
  // first sample, so whatever happens in it the phase arrives where the loop begins.
  const A = d.pre, cycles = Math.round(f * N / RATE), y = new Float32Array(A + N), [vc, vm, vdel = 0, vfade = 0] = d.vib, pv = cycles * vc * Math.LN2 / 1200 / vm;
  const reg = Math.max(0, Math.min(1, Math.log2(f / 261.626) / 3)), ph = new Float64Array(A + N), vcos = new Float32Array(A + N), rnd = rng(midi + 3);
  const dr = [1, 2, 3].map((m) => [m, (d.drift ?? 0) / Math.sqrt(0.9167) * cycles * Math.LN2 / 1200 / m / Math.sqrt(m), TAU * rnd()]);
  // `vibWob`: the vibrato's depth itself swells and eases once over the loop, by this fraction (no player's is even)
  const wob = (n) => 1 + (d.vibWob ?? 0) * Math.sin(TAU * n / N + 1.3), vibOf = (n) => pv * wob(n) * Math.sin(TAU * vm * n / N), dev = (n) => { let v = vibOf(n); for (const [m, c, p] of dr) v += c * Math.sin(TAU * m * n / N + p); return v; };
  for (let n = 0; n < N; n++) { ph[A + n] = dev(n); vcos[A + n] = Math.cos(TAU * vm * n / N); }
  for (let n = -1, acc = dev(0); n >= -A; n--) {
    const t = (n + A) / RATE, x = vdel || vfade ? Math.max(0, Math.min(1, (t - vdel) / Math.max(vfade, 1e-3))) : 1, e = 1 - (1 - x) ** 2;
    acc -= (vibOf(n + 1) - vibOf(n)) * e + (dev(n + 1) - vibOf(n + 1)) - (dev(n) - vibOf(n)) - (d.scoop ? TAU * f / RATE * d.scoop[0] * Math.LN2 / 1200 * Math.exp(-t / d.scoop[1]) : 0);
    ph[A + n] = acc; vcos[A + n] = e * Math.cos(TAU * vm * n / N);
  }
  // an operator may add modulators in parallel, `par` [ratio, index, key scaling] or a list of them, and ease its
  // indices up the keyboard, `ks` (a flute's upper register is purer): index * (1 - ks * register)
  d.ops.forEach(([cr, mr, i0, is, tau, lv, beat, fb = 0, st, par, ks = 0], j) => {
    // each operator starts at its own phase, or a detuned stack would meet in a peak where the loop begins
    let m1 = 0, m2 = 0; const phj = d.align ? 0 : TAU * ((j * 0.618034 * (1 + (d.ps ?? 0))) % 1), kI = 1 - reg * ks, pars = (par ? (Array.isArray(par[0]) ? par : [par]) : []).map(([r, x, k = 0]) => [Math.round(r * cycles), r, x * (1 - reg * k)]);
    for (let n = -A; n < N; n++) {
      const i = n + A, p = ph[i], u = i / A, bright = 1 + (d.vibIdx ?? 0) * vcos[i], m = Math.sin(TAU * Math.round(mr * cycles) * n / N + mr * p + fb * ease * 0.5 * (m1 + m2) + (st ? st[1] * Math.sin(TAU * Math.round(st[0] * cycles) * n / N + st[0] * p) : 0)); m2 = m1; m1 = m;
      let pm = 0; for (const [c, r, x] of pars) pm += x * Math.sin(TAU * c * n / N + r * p);
      y[i] += lv * Math.sin(TAU * (Math.round(cr * cycles) + beat) * n / N + phj + cr * p + bright * ((is + (n < 0 ? (i0 - is) * Math.exp(-i / (tau * RATE)) * (1 - u ** 4) : 0)) * kI * m + pm));
    }
  });
  // air: noise bands [Hz, + this many times the note, bandwidth/centre, gain, lowest, highest centre, kind],
  // kind 0 white, 1 pink, 2 pink above the centre only; outside the FM. `pre`: before the tone control (bow
  // friction, coloured by the body); otherwise after it (a flute's breath). `reg` raises it up the register;
  // `puff` [Hz, bandwidth/centre, gain, + times the note, decay s] is a burst as the note starts.
  const air = () => {
    const re = new Float64Array(N), im = new Float64Array(N), bands = d.air.bands.map(([b, k, rq, g, lo = 0, hi = 14000, kind = 0]) => [Math.max(lo, Math.min(hi, b + k * f)), rq, g * g, kind]), ga = (d.airGain ?? d.air.gain) * (1 + reg * (d.air.reg ?? 0));
    for (let k = 1; k < N / 2; k++) { const fr = k * RATE / N; let h = 0; for (const [fc, rq, g2, kind] of bands) h += g2 * (kind === 2 ? 1 / (1 + (fc / fr) ** 4) : 1 / (1 + ((fr / fc - fc / fr) / rq) ** 2)) * (kind ? 311.6 / fr : 1); const c = Math.sqrt(2 / 72000 * RATE / N * h), q = TAU * rnd(); re[k] = c * Math.cos(q); im[k] = -c * Math.sin(q); }
    fft(re, im);
    const [pf0, prq, pg, pk = 0, ptau = 0.025] = d.air.puff ?? [2600, 0.9, 0], w0 = TAU * Math.max(500, Math.min(8000, pf0 + pk * f)) / RATE, al = Math.sin(w0) * prq / 2, b0 = al / (1 + al), a1 = -2 * Math.cos(w0) / (1 + al), a2 = (1 - al) / (1 + al); let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (let i = 0; i < A + N; i++) {
      const n = i - A, t = i / RATE, blow = n < 0 ? Math.min(1, t / 0.025) * (1 + 0.1 * Math.exp(-t / 0.19)) : 1; let puff = 0;
      if (n < 0 && t < 0.25) { const w = rnd() * 2 - 1, o = b0 * (w - x2) - a1 * y1 - a2 * y2; x2 = x1; x1 = w; y2 = y1; y1 = o; puff = o * pg * Math.min(1, t / Math.min(0.004, ptau / 3)) * Math.exp(-t / ptau); }
      y[i] += re[(n % N + N) % N] * ga * blow * (1 + (d.air.vib ?? 0) * vcos[i]) + puff;
    }
  };
  if (d.air?.pre) air();
  tone12(d, f, y, A);
  if (d.vibAmp) for (let i = 0; i < A + N; i++) y[i] *= 1 + d.vibAmp * vcos[i];
  if (d.air && !d.air.pre) air();
  for (let i = 0; i < 96 && i < A; i++) y[i] *= i / 96; // 3 ms in from silence: the filters above start from rest, which leaves a step in the first samples
  return y;
}

// plucked or struck string (Karplus-Strong with a tuned allpass): t60 seconds at middle C, loop lowpass
// `damp`, excitation lowpass `bright`, pluck position `pick`, `strings` detuned in cents
function pluck(d, midi) {
  const f = hz(midi), t60 = d.t60 * (hz(60) / f) ** (d.dk ?? 0.5), n = Math.round(Math.min(d.len ?? 2.5, t60 * 0.95 + 0.1) * RATE), y = new Float32Array(n), rnd = rng(midi);
  for (const det of d.strings ?? [0]) {
    const P = RATE / (f * 2 ** (det / 1200)), g = 10 ** (-3 * P / (t60 * RATE)), D = P - d.damp, M = Math.floor(D - 0.1), eta = D - M, C = (1 - eta) / (1 + eta), buf = new Float32Array(M), e = new Float32Array(M);
    let z = 0; for (let i = 0; i < M; i++) { z += d.bright * (rnd() * 2 - 1 - z); e[i] = z; }
    const pk = Math.max(1, Math.round(d.pick * M)); let mean = 0; for (let i = 0; i < M; i++) { buf[i] = e[i] - e[(i + M - pk) % M]; mean += buf[i] / M; } for (let i = 0; i < M; i++) buf[i] -= mean;
    let p = 0, x1 = 0, a1 = 0, l1 = 0;
    for (let i = 0; i < n; i++) { const x = buf[p], ap = C * x + x1 - C * a1; x1 = x; a1 = ap; buf[p] = g * ((1 - d.damp) * ap + d.damp * l1); l1 = ap; p = (p + 1) % M; y[i] += ap; }
  }
  return fade(y);
}

// clarinet, flute and bowed string after the STK models (Cook and Scavone); `n` samples from the note's start
function clarinet(d, midi, n) {
  const L = RATE / hz(midi) * 0.5 - 1.5, dl = delay(1024), rnd = rng(midi), y = new Float32Array(n); let z = 0;
  for (let i = 0; i < n; i++) { const breath = Math.min(1, i / (0.03 * RATE)) * d.p * (1 + d.noise * (rnd() * 2 - 1)), o = dl.get(L), pd = -0.95 * 0.5 * (o + z) - breath; z = o; dl.put(breath + pd * Math.max(-1, Math.min(1, 0.7 - 0.3 * pd))); y[i] = o; }
  return y;
}
function flute(d, midi, n) {
  const L = RATE / (hz(midi) * 0.66666) - 2, bore = delay(2048), jet = delay(1024), pole = 0.7 - 0.1 * 22050 / RATE, rnd = rng(midi), y = new Float32Array(n); let lp = 0, x1 = 0, y1 = 0;
  for (let i = 0; i < n; i++) {
    const breath = d.p * Math.min(1, i / (0.05 * RATE)) * (1 + d.noise * (rnd() * 2 - 1) + 0.06 * Math.sin(TAU * 6 * i / RATE) * Math.min(1, i / (0.25 * RATE)));
    lp = (1 - pole) * bore.get(L) + pole * lp; const dc = -lp - x1 + 0.99 * y1; x1 = -lp; y1 = dc;
    jet.put(breath - 0.5 * dc); let pd = jet.get(L * 0.32); pd = Math.max(-1, Math.min(1, pd * (pd * pd - 1))) + 0.5 * dc;
    bore.put(pd); y[i] = 0.3 * pd;
  }
  return y;
}
function bowed(d, midi, n) {
  const base = RATE / hz(midi) - 4, neck = delay(4096), bridge = delay(1024), pole = 0.75 - 0.2 * 22050 / RATE, rnd = rng(midi), y = new Float32Array(n); let sf = 0, o1 = 0;
  for (let i = 0; i < n; i++) {
    const B = base / (1 + d.vib * Math.LN2 / 1200 * Math.sin(TAU * 5.5 * i / RATE) * Math.min(1, i / (0.3 * RATE))), bo = bridge.get(B * d.beta);
    sf = 0.95 * (1 - pole) * bo + pole * sf;
    const nr = -neck.get(B * (1 - d.beta)), dv = d.v * Math.min(1, i / (0.04 * RATE)) * (1 + d.noise * (rnd() * 2 - 1)) - (nr - sf); let s = (Math.abs(dv * d.slope) + 0.75) ** -4; if (s > 1) s = 1;
    neck.put(dv * s - sf); bridge.put(nr + dv * s); y[i] = bo - 0.7 * o1; o1 = bo;
  }
  return y;
}
// two players: a second bowed string a beat or two per loop away (none in the bass, where that is too wide)
const duo = (d, midi, n) => { const y = bowed(d, midi, n), f = hz(midi), beat = !d.duo ? 0 : f >= 180 ? 1.818 : f >= 90 ? 0.909 : 0; if (!beat) return y; const z = bowed({ ...d, v: d.v * 1.15, vib: d.vib * 0.7 }, 69 + 12 * Math.log2((f + beat) / 440), n); for (let i = 0; i < n; i++) y[i] += 0.8 * z[i]; return y; };
// noise drums: a hat (clipped noise and five square "metal" oscillators through a highpass) and a snare
// (a sine body, band-passed noise and a burst of gated noise for the snap), each soft-clipped
function hat(d) {
  const n = Math.round(d.len * RATE), y = new Float32Array(n), rnd = rng(11), c = Math.exp(-TAU * d.hp / RATE); let x1 = 0, h1 = 0, h2 = 0, g1 = 0;
  for (let i = 0; i < n; i++) { const t = i / RATE; let v = (rnd() < 0.5 ? -0.72 : 0.72); for (const f of d.metal) v += 0.07 * (((f * t) % 1) < 0.5 ? 1 : -1);
    h1 = c * (h1 + v - x1); x1 = v; h2 = c * (h2 + h1 - g1); g1 = h1; y[i] = Math.tanh(h2 * 1.45) * Math.min(1, t / d.atk) * Math.exp(-t / d.tau); }
  return fade(y, 160);
}
function snare(d) {
  const n = Math.round(d.len * RATE), y = new Float32Array(n), rnd = rng(23), w0 = TAU * d.band / RATE, al = Math.sin(w0) * d.rq / 2, a0 = 1 + al, b0 = al / a0, a1 = -2 * Math.cos(w0) / a0, a2 = (1 - al) / a0, hc = Math.exp(-TAU * 1200 / RATE);
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0, pk = 0, hx = 0, hy = 0, lag = 0;
  for (let i = 0; i < n; i++) { const t = i / RATE, w = rnd() * 2 - 1, bp = b0 * (w - x2) - a1 * y1 - a2 * y2; x2 = x1; x1 = w; y2 = y1; y1 = bp;
    pk += 0.2 * (rnd() * 2 - 1 - pk); const pn = pk * 2 + 0.3 * w; hy = hc * (hy + pn - hx); hx = pn; lag += 0.06 * ((((d.rattle * t) % 1) < 0.38 ? 1 : 0) - lag);
    y[i] = Math.tanh(1.6 * (0.55 * 0.35 * Math.sin(TAU * d.body * t) + bp * d.noise + 0.6 * hy * lag * Math.exp(-t / d.snap)) * Math.min(1, t / d.atk) * Math.exp(-t / d.tau)); }
  return fade(y, 320);
}
// kick and toms: a sine that drops from (1 + `sweep`) times `f` to `f` (time constant `st`), an optional
// sub an octave below, a band of noise for the knock [Hz, bandwidth/centre, gain] and high noise for the
// click [highpass Hz, gain], both gone with the drop; `tau` is the body's decay; soft-clipped
function boom(d) {
  const n = Math.round(d.len * RATE), y = new Float32Array(n), rnd = rng(31), w0 = TAU * d.knock[0] / RATE, al = Math.sin(w0) * d.knock[1] / 2, b0 = al / (1 + al), a1 = -2 * Math.cos(w0) / (1 + al), a2 = (1 - al) / (1 + al), hc = Math.exp(-TAU * d.click[0] / RATE);
  let ph = 0, ph2 = 0, x1 = 0, x2 = 0, y1 = 0, y2 = 0, hx = 0, hy = 0, pk = 0;
  for (let i = 0; i < n; i++) { const t = i / RATE, snap = Math.exp(-t / d.st), w = rnd() * 2 - 1; pk += 0.25 * (w - pk); const pn = pk * 2, bp = b0 * (pn - x2) - a1 * y1 - a2 * y2; x2 = x1; x1 = pn; y2 = y1; y1 = bp; hy = hc * (hy + w - hx); hx = w;
    ph += TAU * d.f * (1 + d.sweep * snap) / RATE; ph2 += TAU * d.f * 0.5 / RATE;
    y[i] = Math.tanh((0.9 * Math.sin(ph) + (d.sub ?? 0) * Math.sin(ph2)) * Math.exp(-t / d.tau) * Math.min(1, t / 0.0005) + bp * d.knock[2] * snap * 3 + hy * d.click[1] * snap); }
  return fade(y, 320);
}
const peak = (y, p) => { let m = 0; for (const v of y) m = Math.max(m, Math.abs(v)); for (let i = 0; i < y.length; i++) y[i] *= p / (m || 1); return y; };
const BLOWN = { c: clarinet, u: flute, b: duo }, XF = 0.03 * RATE;

/** One zone of definition `d` at `midi` (the k-th zone): where it loops (null: plays once), its tuning
 *  in cents, and `make()`, its samples at 16-bit scale with the level `d.lvl`. */
/** A take: the definition with its `var` settings moved a little, each by up to the amount given: `comb`
 *  (pluck position), `index` (brightness, as a fraction), `vibRate` (cycles in the loop), `vibDepth` and
 *  `vibDelay` (fractions), `air` (breath or bow noise, dB). */
function vary(d, rnd) {
  const v = d.var, u = () => rnd() * 2 - 1, o = { ...d };
  if (v.comb) o.comb = d.comb + v.comb * u();
  if (v.index) { const g = 1 + v.index * u(); o.ops = d.ops.map((op) => { const q = [...op]; q[2] *= g; q[3] *= g; if (q[11]) q[11] = [q[11][0] * g, q[11][1]]; return q; }); }
  if (d.vib && (v.vibRate || v.vibDepth || v.vibDelay)) { const [c, m, del = 0, fd = 0] = d.vib; o.vib = [c * (1 + (v.vibDepth ?? 0) * u()), m + Math.round((v.vibRate ?? 0) * u()), del * (1 + (v.vibDelay ?? 0) * u()), fd]; }
  if (v.air && d.air) { const g = 10 ** (v.air * u() / 20); o.air = { ...d.air, gain: d.air.gain * g, puff: d.air.puff && d.air.puff.map((x, i) => (i === 2 ? x * g : x)) }; if (d.airGain) o.airGain = d.airGain * g; }
  return o;
}

export function zone(d, midi, k, take) {
  if (d.zones) d = { ...d, ...d.zones[k], zones: undefined }; // settings that change with the register, per zone
  if (d.var && take !== undefined) d = vary(d, rng(midi * 131 + take * 977 + 5));
  const cyc = Math.round(hz(midi) * N / RATE), exact = 1200 * Math.log2(hz(midi) / (cyc * RATE / N));
  if (d.t === 'a' && d.chiff) { // a blown start [seconds, noise dB against the tone]: the tone swells in under a puff of breath
    const A = Math.round(d.chiff[0] * RATE);
    return { loopStart: A, tune: exact, make: () => { const L = additive(d, midi), y = new Float32Array(A + N), rnd = rng(midi + 7); let e = 0; for (let i = 0; i < N; i++) e += L[i] * L[i]; const nz = Math.sqrt(e / N) * 10 ** (d.chiff[1] / 20) * 3; let lp = 0, hp = 0;
      for (let i = 0; i < A; i++) { const w = rnd() * 2 - 1; lp += 0.45 * (w - lp); hp += 0.08 * (lp - hp); const t = i / RATE; y[i] = L[(i - A + N) % N] * (i / A) ** 1.5 + (lp - hp) * nz * Math.min(1, t / 0.004) * Math.exp(-t / 0.022); }
      y.set(L, A); return level(y, A, A + N, d.lvl); } };
  }
  if (d.t === 'a') return { loopStart: 0, tune: exact, make: () => level(additive(d, midi), 0, N, d.lvl) };
  if (d.t === 'm') return { loopStart: null, tune: 0, make: () => level(modal(d, midi), 0, 3200, d.lvl) };
  if (d.t === 'f') return d.sus ? { loopStart: d.pre, tune: exact, make: () => level(fm(d, midi), d.pre, d.pre + N, d.lvl) } : { loopStart: null, tune: 0, make: () => level(fm(d, midi), 0, 3200, d.lvl) };
  if (d.t === 'hh' || d.t === 'sn' || d.t === 'kd') return { loopStart: null, tune: 0, make: () => peak((d.t === 'hh' ? hat : d.t === 'sn' ? snare : boom)(d), d.peak) };
  if (d.t === 'k') return { loopStart: null, tune: d.tune?.[k] ?? 0, make: () => level(pluck(d, midi), 0, 3200, d.lvl) };
  if (BLOWN[d.t]) {
    if (d.zp) d = { ...d, p: d.zp[k] }; // a note's own blowing pressure, where the shared one overblows
    const [start, end] = d.loops?.[k] ?? [0, 0];
    return { loopStart: start, tune: d.tune?.[k] ?? 0, raw: (n) => BLOWN[d.t](d, midi, n), make: () => { const y = BLOWN[d.t](d, midi, end); for (let i = 0; i < XF; i++) { const b = 0.5 - 0.5 * Math.cos(Math.PI * i / (XF - 1)); y[end - XF + i] = y[end - XF + i] * (1 - b) + y[start - XF + i] * b; } return level(y, start, end, d.lvl); } };
  }
  if (d.t === 'h') { // a recorded attack [root, rate, samples, BRR as base91] crossfaded into the inner definition
    const inner = zone(d.in, midi, k), [root, rate, len] = d.atk, step = rate / RATE * 2 ** ((midi - root) / 12), La = Math.floor((len - 2) / step), xf = Math.min(480, La >> 1);
    return { loopStart: inner.loopStart === null ? null : La, tune: inner.tune, make: () => {
      const tail = inner.make(), a = Float32Array.from(decodeBRR(Uint8Array.from(fromBase91(d.atk[3])), null)); if (d.soft) { let z = 0; for (let i = 0; i < a.length; i++) a[i] = z += d.soft * (a[i] - z); }
      const at = (i) => { const x = i * step, j = x | 0; return a[j] + (a[j + 1] - a[j]) * (x - j); };
      const loop = inner.loopStart !== null, P = tail.length, tv = (i) => (loop ? tail[((i - La) % P + P) % P] : tail[i] ?? 0), y = new Float32Array(loop ? La + P : Math.max(P, La));
      let ea = 0, et = 0; for (let i = La - 2 * xf; i < La; i++) { ea += at(i) ** 2; et += tv(i) ** 2; } const ga = Math.sqrt(et / (ea || 1));
      for (let i = 0; i < y.length; i++) { const w = i < La - xf ? 0 : i < La ? (i - (La - xf)) / xf : 1; y[i] = (w < 1 ? at(i) * ga * Math.sqrt(1 - w) : 0) + (w > 0 ? tv(i) * Math.sqrt(w) : 0); }
      return y; } };
  }
  throw new Error('Unknown definition');
}
