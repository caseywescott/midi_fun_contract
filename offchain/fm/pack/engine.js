// Loot FM pack engine: the parts of engines.js the Kankyo bank uses (FM, sustained and struck, and the
// noise drums), as in kankyo.min.js. Reference copy before optimisation.
export const RATE = 32000, N = 65536;
const rng = (a) => () => { a = a + 0x6d2b79f5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) { let bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; } }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) { let cr = 1, ci = 0; for (let k = 0; k < len / 2; k++) { const p = i + k, q = p + len / 2, xr = re[q] * cr - im[q] * ci, xi = re[q] * ci + im[q] * cr; re[q] = re[p] - xr; im[q] = im[p] - xi; re[p] += xr; im[p] += xi; const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t; } }
  }
}
const TAU = 2 * Math.PI, hz = (m) => 440 * 2 ** ((m - 69) / 12);
const level = (y, a, b, lvl) => { let s = 0; for (let i = a; i < b; i++) s += y[i] * y[i]; const k = lvl / (Math.sqrt(s / (b - a)) || 1); for (let i = 0; i < y.length; i++) y[i] *= k; return y; };
const fade = (y, n = 640) => { for (let i = 0; i < n && i < y.length; i++) y[y.length - 1 - i] *= i / n; return y; };
// The biquad cascade of `tone12`, coefficients and state in typed arrays (the same arithmetic as the reference)
function tone12(d, f, y, loopStart) {
  const eq = (d.eq ?? []).map(([type, hz0, q, db, track]) => {
    const fc = Math.min(14000, track ? hz0 * f : hz0), A = 10 ** (db / 40), w = TAU * fc / RATE, cs = Math.cos(w), sn = Math.sin(w);
    if (type === 'l') { const r = 2 * Math.sqrt(A) * sn / 2 * Math.SQRT2, a0 = (A + 1) + (A - 1) * cs + r; return [A * ((A + 1) - (A - 1) * cs + r) / a0, 2 * A * ((A - 1) - (A + 1) * cs) / a0, A * ((A + 1) - (A - 1) * cs - r) / a0, -2 * ((A - 1) + (A + 1) * cs) / a0, ((A + 1) + (A - 1) * cs - r) / a0]; }
    if (type === 'b') { const al = sn / (2 * q), a0 = 1 + al; return [(al + db * a0) / a0, db * -2 * cs / a0, (-al + db * (1 - al)) / a0, -2 * cs / a0, (1 - al) / a0]; }
    if (type === 'p') { const al = sn / (2 * q), a0 = 1 + al / A; return [(1 + al * A) / a0, -2 * cs / a0, (1 - al * A) / a0, -2 * cs / a0, (1 - al / A) / a0]; }
    const al = sn / 2 * Math.SQRT2, r = 2 * Math.sqrt(A) * al, a0 = (A + 1) - (A - 1) * cs + r;
    return [A * ((A + 1) + (A - 1) * cs + r) / a0, -2 * A * ((A - 1) + (A + 1) * cs) / a0, A * ((A + 1) + (A - 1) * cs - r) / a0, 2 * ((A - 1) - (A + 1) * cs) / a0, ((A + 1) - (A - 1) * cs - r) / a0];
  });
  const c = d.lp || d.lpk ? 1 - Math.exp(-TAU * Math.min(14000, Math.max(d.lp ?? 0, (d.lpk ?? 0) * f + (d.lpo ?? 0))) / RATE) : 0, K = eq.length, Q = new Float64Array(eq.flat()), Z = new Float64Array(4 * K), L = y.length;
  if (!c && !K) return y;
  let a = 0, b = 0;
  for (let pass = 0; pass < (loopStart ? 2 : 1); pass++) for (let i = pass ? loopStart : 0; i < L; i++) {
    let v = y[i];
    for (let k = 0, q = 0, z = 0; k < K; k++, q += 5, z += 4) { const o = Q[q] * v + Q[q + 1] * Z[z] + Q[q + 2] * Z[z + 1] - Q[q + 3] * Z[z + 2] - Q[q + 4] * Z[z + 3]; Z[z + 1] = Z[z]; Z[z] = v; Z[z + 3] = Z[z + 2]; Z[z + 2] = o; v = o; }
    if (c) { a += c * (v - a); b += c * (a - b); v = b; }
    if (pass || !loopStart || i < loopStart) y[i] = v; // the loop's first pass only settles the filters
  }
  return y;
}
// FM: operators [carrier ratio, modulator ratio, index at the attack, index held, index time constant (s),
// level, level decay dB/s (struck) or beat cycles over the loop (sustained), feedback, [ratio, index]].
// Same arithmetic as the reference engine, sample for sample; what changed is only what is computed once:
// a modulator shared by several operators (same ratio, feedback and stack) is run once, an operator whose
// index is zero throughout skips its modulator, and envelopes that cancel out (index held = attack) skip Math.exp.
function fm(d, midi) {
  const f = hz(midi), ease = Math.min(1, Math.sqrt(523 / f)), mods = new Map();
  if (!d.sus) {
    const k = (f / hz(60)) ** (d.dk ?? 0.4), n = Math.round(Math.min(d.len ?? 2.5, 55 / (Math.min(...d.ops.map((o) => o[6])) * k) + 0.1) * RATE), y = new Float32Array(n), dry = d.comb ? new Float32Array(n) : y;
    for (const [cr, mr, i0, is, tau, lv, ad, fb = 0, st, , , i2, atk = 0, isDry] of d.ops) {
      if (f * cr > 14000) continue; // a negative ratio is a fixed frequency in Hz (a pick's click does not follow the note)
      const out = isDry ? dry : y, [is2, tau2] = i2 ?? [is, 1], wc = TAU * (cr < 0 ? -cr : f * cr) / RATE, wm = TAU * (mr < 0 ? -mr : f * mr) / RATE, dec = Math.exp(-ad * k * Math.LN10 / 20 / RATE), fbe = fb * ease * 0.5, d2 = is - is2, d0 = i0 - is;
      let amp = lv;
      if (!i0 && !is && !is2) { // no modulation at all: wc * i + 0 * m is wc * i
        for (let i = 0; i < n; i++) { const t = i / RATE; out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(wc * i); amp *= dec; }
        continue;
      }
      // the modulator, shared by operators with the same one (it does not depend on the carrier unless it is stacked)
      const key = st ? null : wm + ',' + fbe; let M = key && mods.get(key);
      if (!M) {
        M = new Float64Array(n); let m1 = 0, m2 = 0;
        if (st) { const w2 = TAU * f * st[0] / RATE; for (let i = 0; i < n; i++) { const t = i / RATE, e = Math.exp(-t / tau), m = Math.sin(wm * i + fbe * (m1 + m2) + st[1] * (0.15 + 0.85 * e) * Math.sin(w2 * i)); m2 = m1; m1 = m; M[i] = m; } }
        else { for (let i = 0; i < n; i++) { const m = Math.sin(wm * i + fbe * (m1 + m2) + 0); m2 = m1; m1 = m; M[i] = m; } if (key) mods.set(key, M); }
      }
      // (is2 + (is - is2) * e2 + (i0 - is) * e) * m, leaving out the terms that are exactly zero
      if (d2 === 0 && d0 === 0) for (let i = 0; i < n; i++) { const t = i / RATE; out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(wc * i + (is2 + 0 + 0) * M[i]); amp *= dec; }
      else if (d2 === 0) for (let i = 0; i < n; i++) { const t = i / RATE; out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(wc * i + (is2 + 0 + d0 * Math.exp(-t / tau)) * M[i]); amp *= dec; }
      else for (let i = 0; i < n; i++) { const t = i / RATE; out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(wc * i + (is2 + d2 * Math.exp(-t / tau2) + d0 * Math.exp(-t / tau)) * M[i]); amp *= dec; }
    }
    if (d.trem) for (let i = 0; i < n; i++) y[i] *= 1 + d.trem[0] * Math.sin(TAU * d.trem[1] * i / RATE); // a vibraphone's motor: [depth, Hz]
    if (d.comb) { const D = d.comb * RATE / f, g = 1 / (2 * Math.sin(Math.PI * d.comb)); for (let i = n - 1; i >= 0; i--) { const x = i - D, j = Math.floor(x), fr = x - j; y[i] = (y[i] - (j >= 0 ? y[j] * (1 - fr) + y[j + 1] * fr : 0)) * g + dry[i]; } }
    return fade(tone12(d, f, y, 0));
  }
  // Sustained: `pre` samples of attack, then a loop of N. `vib` [cents, cycles in the loop, delay s, fade s],
  // `vibAmp`, `vibIdx`, `vibWob`, `drift` (cents), `scoop` [cents, s]; the attack's pitch is integrated back from the loop's first sample.
  const A = d.pre, L = A + N, cycles = Math.round(f * N / RATE), y = new Float32Array(L), [vc, vm, vdel = 0, vfade = 0] = d.vib, pv = cycles * vc * Math.LN2 / 1200 / vm;
  const reg = Math.max(0, Math.min(1, Math.log2(f / 261.626) / 3)), ph = new Float64Array(L), vcos = new Float32Array(L), rnd = rng(midi + 3);
  const dr = [1, 2, 3].map((m) => [m, (d.drift ?? 0) / Math.sqrt(0.9167) * cycles * Math.LN2 / 1200 / m / Math.sqrt(m), TAU * rnd()]);
  // vibrato and pitch deviation at every n from -A to N - 1 (each once; the reference evaluated them several times over)
  const wk = d.vibWob ?? 0, tv = TAU * vm, VIB = new Float64Array(L + 1), DEV = new Float64Array(L + 1);
  for (let n = -A; n <= 0 || n < N; n++) { const vb = pv * (1 + wk * Math.sin(TAU * n / N + 1.3)) * Math.sin(tv * n / N); let v = vb; for (let q = 0; q < 3; q++) v += dr[q][1] * Math.sin(TAU * dr[q][0] * n / N + dr[q][2]); VIB[n + A] = vb; DEV[n + A] = v; }
  for (let n = 0; n < N; n++) { ph[A + n] = DEV[A + n]; vcos[A + n] = Math.cos(tv * n / N); }
  const sc = d.scoop, scK = sc && TAU * f / RATE * sc[0] * Math.LN2 / 1200;
  for (let n = -1, acc = DEV[A]; n >= -A; n--) {
    const t = (n + A) / RATE, x = vdel || vfade ? Math.max(0, Math.min(1, (t - vdel) / Math.max(vfade, 1e-3))) : 1, e = 1 - (1 - x) ** 2, j = n + A;
    acc -= (VIB[j + 1] - VIB[j]) * e + (DEV[j + 1] - VIB[j + 1]) - (DEV[j] - VIB[j]) - (sc ? scK * Math.exp(-t / sc[1]) : 0);
    ph[j] = acc; vcos[j] = e * Math.cos(tv * n / N);
  }
  const vI = d.vibIdx ?? 0, BR = new Float64Array(L); for (let i = 0; i < L; i++) BR[i] = 1 + vI * vcos[i];
  d.ops.forEach(([cr, mr, i0, is, tau, lv, beat, fb = 0, st, par, ks = 0], j) => {
    const phj = d.align ? 0 : TAU * ((j * 0.618034 * (1 + (d.ps ?? 0))) % 1), kI = 1 - reg * ks, pars = (par ? (Array.isArray(par[0]) ? par : [par]) : []).map(([r, x, k = 0]) => [TAU * Math.round(r * cycles), r, x * (1 - reg * k)]), P = pars.length;
    const tc = TAU * (Math.round(cr * cycles) + beat);
    if (!i0 && !is && !P) { for (let n = -A; n < N; n++) { const i = n + A; y[i] += lv * Math.sin(tc * n / N + phj + cr * ph[i]); } return; } // index 0 throughout
    const key = mr + ',' + fb + ',' + (st ? st[0] + ',' + st[1] : ''); let M = mods.get(key);
    if (!M) {
      M = new Float64Array(L); mods.set(key, M); let m1 = 0, m2 = 0; const tm = TAU * Math.round(mr * cycles), fbe = fb * ease * 0.5;
      if (st) { const ts = TAU * Math.round(st[0] * cycles); for (let n = -A; n < N; n++) { const i = n + A, p = ph[i], m = Math.sin(tm * n / N + mr * p + fbe * (m1 + m2) + st[1] * Math.sin(ts * n / N + st[0] * p)); m2 = m1; m1 = m; M[i] = m; } }
      else for (let n = -A; n < N; n++) { const i = n + A, m = Math.sin(tm * n / N + mr * ph[i] + fbe * (m1 + m2) + 0); m2 = m1; m1 = m; M[i] = m; }
    }
    const d0 = i0 - is, tr = tau * RATE;
    for (let n = -A; n < 0; n++) { // the attack: the index from i0 to is
      const i = n + A, p = ph[i], u = i / A; let pm = 0; for (let q = 0; q < P; q++) { const s = pars[q]; pm += s[2] * Math.sin(s[0] * n / N + s[1] * p); }
      y[i] += lv * Math.sin(tc * n / N + phj + cr * p + BR[i] * ((is + d0 * Math.exp(-i / tr) * (1 - u ** 4)) * kI * M[i] + pm));
    }
    for (let n = 0; n < N; n++) {
      const i = n + A, p = ph[i]; let pm = 0; for (let q = 0; q < P; q++) { const s = pars[q]; pm += s[2] * Math.sin(s[0] * n / N + s[1] * p); }
      y[i] += lv * Math.sin(tc * n / N + phj + cr * p + BR[i] * ((is + 0) * kI * M[i] + pm));
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
  if (d.t === 'f') return d.sus ? { loopStart: d.pre, tune: exact, make: () => level(fm(d, midi), d.pre, d.pre + N, d.lvl) } : { loopStart: null, tune: 0, make: () => level(fm(d, midi), 0, 3200, d.lvl) };
  if (d.t === 'hh' || d.t === 'sn' || d.t === 'kd') return { loopStart: null, tune: 0, make: () => peak((d.t === 'hh' ? hat : d.t === 'sn' ? snare : boom)(d), d.peak) };
  throw new Error('Unknown definition');
}
