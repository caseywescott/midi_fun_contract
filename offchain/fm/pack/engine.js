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
  const c = d.lp || d.lpk ? 1 - Math.exp(-TAU * Math.min(14000, Math.max(d.lp ?? 0, (d.lpk ?? 0) * f + (d.lpo ?? 0))) / RATE) : 0, K = eq.length, Q = new Float64Array(eq.flat()), L = y.length;
  if (!c && !K) return y;
  // The cascade a filter at a time over the whole signal (each stage only needs the one before it, so this is the
  // reference's sample-at-a-time cascade, value for value): the signal is y, then, for a loop, y's loop again
  // (the first pass only settles the filters; the loop's samples are taken from the second).
  const ls = loopStart || L, X = new Float64Array(L + (loopStart ? L - ls : 0));
  for (let i = 0; i < L; i++) X[i] = y[i];
  for (let i = ls; i < L && loopStart; i++) X[L + i - ls] = y[i];
  const M = X.length;
  for (let k = 0, q = 0; k < K; k++, q += 5) {
    const b0 = Q[q], b1 = Q[q + 1], b2 = Q[q + 2], a1 = Q[q + 3], a2 = Q[q + 4]; let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
    for (let i = 0; i < M; i++) { const v = X[i], o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2; x2 = x1; x1 = v; y2 = y1; y1 = o; X[i] = o; }
  }
  if (c) { let a = 0, b = 0; for (let i = 0; i < M; i++) { a += c * (X[i] - a); b += c * (a - b); X[i] = b; } }
  for (let i = 0; i < ls; i++) y[i] = X[i];
  for (let i = ls; i < L; i++) y[i] = X[L + i - ls];
  return y;
}
// Sections and formants (engines.js sectionOps, verbatim): `section` players [detune cents, level, vibrato cents,
// vibrato cycles in the loop, phase, jitter cents, jitter cycles], each playing the template operators detuned with
// their own vibrato `ov` (and `rvib` [cents, [cycles]]); `form` {f, range, db, idx, rise, tau} adds formant
// carriers at the harmonics either side of each formant; `choir` is both (`singers`); `fmv` [index, attack ratio,
// tau] replaces the template with Schottstaedt's fm-violin (modulators at 1, 3 and 4 times the note).
function sectionOps(d, f, cycles) {
  const c = d.choir, form = d.form ?? c, players = d.section ?? c?.singers ?? [[0, 1, 0, 1, 0]], m = 69 + 12 * Math.log2(f / 440), ops = [];
  let F = [];
  if (form) {
    const two = Array.isArray(form.f[0]), u = two ? Math.max(0, Math.min(1, (m - form.range[0]) / (form.range[1] - form.range[0]))) : 0;
    F = two ? form.f[0].map((x, k) => x + (form.f[1][k] - x) * u) : [...form.f];
    if (c) F[0] = Math.max(F[0], 1.1 * f);
  }
  let tpl = d.ops;
  if (d.fmv) { const [k, ar = 2, tau = 0.15] = d.fmv, lf = Math.log(f), i1 = Math.min(Math.PI, 5 / lf) * k, i2 = Math.min(Math.PI, (8.5 - lf) / (3 + f / 1000)) * k, i3 = Math.min(Math.PI, 1 / Math.sqrt(f)) * k;
    tpl = [[1, 1, i1 * ar, i1, tau, 1, 0, d.fmvFb ?? 0, null, [[3, i2], [4, i3]], 0]]; tpl[0].ar = [i2 * ar, i3 * ar];
  }
  players.forEach(([cents, lv, vc, vr, vq, jc = 0, jr = 3], s) => {
    const b = cents * cycles * Math.LN2 / 1200, beat = (h) => Math.round(h * b);
    const ov = [[vc, vr, vq], [jc, jr, vq * 2.3 + 1], ...(d.rvib ? d.rvib[1].map((r, k) => [d.rvib[0], r, vq * (k + 1.7) + 0.9 * k + s]) : [])];
    for (const o of tpl) { const q = [o[0], o[1], o[2], o[3], o[4], o[5] * lv, beat(o[0]) + (o[6] ?? 0), o[7], o[8], o[9], o[10], ov]; if (o.ar) q.ar = o.ar; ops.push(q); }
    F.forEach((fk, k) => {
      const r = fk / f, h0 = Math.max(1, Math.floor(r)), w = Math.max(0, Math.min(1, r - h0)), a = lv * 10 ** (form.db[k] / 20), x = form.idx[k];
      for (const [h, g] of [[h0, Math.cos(w * Math.PI / 2)], [h0 + 1, Math.sin(w * Math.PI / 2)]]) if (g > 0.05 && h * f < 12000) ops.push([h, 1, x * (form.rise ?? 0.5), x, form.tau ?? 0.15, a * g, beat(h), 0, null, null, 0, ov]);
    });
  });
  return ops;
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
    // `bend` [cents, s]: the note starts that far flat and slides up; B is the phase lost, as a multiple of the
    // note's, added (times the ratio) to the operators that follow the note (a zero term otherwise: x + 0 is x)
    let B = null;
    if (d.bend) { B = new Float64Array(n); let acc = 0; for (let i = 0; i < n; i++) { B[i] = acc; acc += TAU * f / RATE * (2 ** (-d.bend[0] * Math.exp(-i / RATE / d.bend[1]) / 1200) - 1); } }
    for (const [cr, mr, i0, is, tau, lv, ad, fb = 0, st, , , i2, atk = 0, isDry] of d.ops) {
      if (f * cr > 14000) continue; // a negative ratio is a fixed frequency in Hz (a pick's click does not follow the note)
      const out = isDry ? dry : y, [is2, tau2] = i2 ?? [is, 1], wc = TAU * (cr < 0 ? -cr : f * cr) / RATE, wm = TAU * (mr < 0 ? -mr : f * mr) / RATE, dec = Math.exp(-ad * k * Math.LN10 / 20 / RATE), fbe = fb * ease * 0.5, d2 = is - is2, d0 = i0 - is, bc = B && cr > 0 ? cr : 0, bm = B && mr > 0 ? mr : 0;
      let amp = lv; const W = (i) => wc * i + (bc ? bc * B[i] : 0); // the carrier's phase
      if (!i0 && !is && !is2) { // no modulation at all: wc * i + 0 * m is wc * i
        for (let i = 0; i < n; i++) { const t = i / RATE; out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(W(i)); amp *= dec; }
        continue;
      }
      // the modulator, shared by operators with the same one (it does not depend on the carrier unless it is stacked)
      const key = st ? null : wm + ',' + fbe + ',' + bm; let M = key && mods.get(key);
      if (!M) {
        M = new Float64Array(n); let m1 = 0, m2 = 0;
        if (st) { const w2 = TAU * f * st[0] / RATE; for (let i = 0; i < n; i++) { const t = i / RATE, e = Math.exp(-t / tau), m = Math.sin(wm * i + (bm ? bm * B[i] : 0) + fbe * (m1 + m2) + st[1] * (0.15 + 0.85 * e) * Math.sin(w2 * i)); m2 = m1; m1 = m; M[i] = m; } }
        else { for (let i = 0; i < n; i++) { const m = Math.sin(wm * i + (bm ? bm * B[i] : 0) + fbe * (m1 + m2) + 0); m2 = m1; m1 = m; M[i] = m; } if (key) mods.set(key, M); }
      }
      // (is2 + (is - is2) * e2 + (i0 - is) * e) * m, leaving out the terms that are exactly zero
      if (d2 === 0 && d0 === 0) for (let i = 0; i < n; i++) { const t = i / RATE; out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(W(i) + (is2 + 0 + 0) * M[i]); amp *= dec; }
      else if (d2 === 0) for (let i = 0; i < n; i++) { const t = i / RATE; out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(W(i) + (is2 + 0 + d0 * Math.exp(-t / tau)) * M[i]); amp *= dec; }
      else for (let i = 0; i < n; i++) { const t = i / RATE; out[i] += amp * (atk && t < atk ? t / atk : 1) * Math.sin(W(i) + (is2 + d2 * Math.exp(-t / tau2) + d0 * Math.exp(-t / tau)) * M[i]); amp *= dec; }
    }
    if (d.trem) for (let i = 0; i < n; i++) y[i] *= 1 + d.trem[0] * Math.sin(TAU * d.trem[1] * i / RATE); // a vibraphone's motor: [depth, Hz]
    if (d.comb) { const D = d.comb * RATE / f, g = 1 / (2 * Math.sin(Math.PI * d.comb)); for (let i = n - 1; i >= 0; i--) { const x = i - D, j = Math.floor(x), fr = x - j; y[i] = (y[i] - (j >= 0 ? y[j] * (1 - fr) + y[j + 1] * fr : 0)) * g + dry[i]; } }
    return fade(tone12(d, f, y, 0));
  }
  // Sustained: `pre` samples of attack, then a loop of N. `vib` [cents, cycles in the loop, delay s, fade s],
  // `vibAmp`, `vibIdx`, `vibWob`, `drift` (cents), `scoop` [cents, s]; the attack's pitch is integrated back from the loop's first sample.
  const A = d.pre, L = A + N, cycles = Math.round(f * N / RATE), y = new Float32Array(L), [vc, vm, vdel = 0, vfade = 0] = d.vib, pv = cycles * vc * Math.LN2 / 1200 / vm;
  const reg = Math.max(0, Math.min(1, Math.log2(f / 261.626) / 3)), ph = new Float64Array(L), vcos = new Float32Array(L), ven = new Float32Array(L).fill(1), rnd = rng(midi + 3);
  const dr = [1, 2, 3].map((m) => [m, (d.drift ?? 0) / Math.sqrt(0.9167) * cycles * Math.LN2 / 1200 / m / Math.sqrt(m), TAU * rnd()]);
  // vibrato and pitch deviation at every n from -A to N - 1 (each once; the reference evaluated them several times over)
  const wk = d.vibWob ?? 0, tv = TAU * vm, VIB = new Float64Array(L + 1), DEV = new Float64Array(L + 1);
  const dq = dr[0][1] ? 3 : 0; // no vibrato or no drift: those terms are zero (a zero only ever adds to a phase)
  if (pv || dq) for (let n = -A; n <= 0 || n < N; n++) { const vb = pv ? pv * (1 + wk * Math.sin(TAU * n / N + 1.3)) * Math.sin(tv * n / N) : 0; let v = vb; for (let q = 0; q < dq; q++) v += dr[q][1] * Math.sin(TAU * dr[q][0] * n / N + dr[q][2]); VIB[n + A] = vb; DEV[n + A] = v; }
  for (let n = 0; n < N; n++) { ph[A + n] = DEV[A + n]; vcos[A + n] = Math.cos(tv * n / N); }
  const sc = d.scoop, scK = sc && TAU * f / RATE * sc[0] * Math.LN2 / 1200;
  for (let n = -1, acc = DEV[A]; n >= -A; n--) {
    const t = (n + A) / RATE, x = vdel || vfade ? Math.max(0, Math.min(1, (t - vdel) / Math.max(vfade, 1e-3))) : 1, e = 1 - (1 - x) ** 2, j = n + A;
    acc -= (VIB[j + 1] - VIB[j]) * e + (DEV[j + 1] - VIB[j + 1]) - (DEV[j] - VIB[j]) - (sc ? scK * Math.exp(-t / sc[1]) : 0);
    ph[j] = acc; vcos[j] = e * Math.cos(tv * n / N); ven[j] = e;
  }
  // `nmod` [depth, bandwidth Hz]: slow noise moving every operator's index (breath in the tone), periodic over the loop
  let nz = null;
  if (d.nmod) { const re = new Float64Array(N), im = new Float64Array(N), kmax = Math.round(d.nmod[1] * N / RATE); for (let k = 1; k <= kmax; k++) { const q = TAU * rnd(), g = 1 / (1 + (k / kmax) ** 2); re[k] = g * Math.cos(q); im[k] = -g * Math.sin(q); } fft(re, im); let e = 0; for (let k = 0; k < N; k++) e += re[k] * re[k]; const g = d.nmod[0] / Math.sqrt(e / N); nz = Float32Array.from(re, (v) => v * g); }
  const vI = d.vibIdx ?? 0, BR = new Float64Array(L), U4 = new Float64Array(A), EX = new Map(); for (let i = 0; i < L; i++) BR[i] = (1 + vI * vcos[i]) * (nz ? 1 + nz[((i - A) % N + N) % N] : 1);
  for (let i = 0; i < A; i++) { const u = i / A; U4[i] = 1 - u ** 4; }
  // an operator's own vibrato `ov` [[cents, cycles in the loop, phase]] (a section's players), arriving with the shared
  // vibrato's delay: its phase, once per player (the player's operators share their `ov`)
  const PHS = new Map(), phOf = (ov) => {
    if (!ov || !ov.length) return [ph, ''];
    let r = PHS.get(ov);
    if (!r) { const os = ov.map(([c, q, s]) => [cycles * c * Math.LN2 / 1200 / q, q, s]), P = new Float64Array(L); for (let n = -A; n < N; n++) { const i = n + A; let o = 0; for (const [a, q, s] of os) o += a * Math.sin(TAU * q * n / N + s); P[i] = ph[i] + o * ven[i]; } PHS.set(ov, r = [P, PHS.size + 1]); }
    return r;
  };
  (d.choir || d.section || d.form || d.fmv ? sectionOps(d, f, cycles) : d.ops).forEach((op, j) => {
    const [cr, mr, i0, is, tau, lv, beat, fb = 0, st, par, ks = 0, ov] = op, [ph, pid] = phOf(ov);
    // parallel modulators [round(ratio * cycles) * TAU, ratio, index, attack index (`ar`), index in the loop]: in the
    // attack x1 + (x - x1) * (1 - e), in the loop x1 + (x - x1) (x when there is no `ar`: then x1 is x and these are exact)
    const phj = d.align ? 0 : TAU * ((j * 0.618034 * (1 + (d.ps ?? 0))) % 1), kI = 1 - reg * ks, pars = (par ? (Array.isArray(par[0]) ? par : [par]) : []).map(([r, x, k = 0], q) => { x *= 1 - reg * k; const x1 = op.ar ? op.ar[q] : x; return [TAU * Math.round(r * cycles), r, x, x1, x1 + (x - x1)]; }), P = pars.length, AR = !!op.ar;
    const tc = TAU * (Math.round(cr * cycles) + beat);
    if (!i0 && !is && !P) { for (let n = -A; n < N; n++) { const i = n + A; y[i] += lv * Math.sin(tc * n / N + phj + cr * ph[i]); } return; } // index 0 throughout
    const key = pid + ',' + mr + ',' + fb + ',' + (st ? st[0] + ',' + st[1] : ''); let M = mods.get(key);
    if (!M) {
      M = new Float64Array(L); mods.set(key, M); let m1 = 0, m2 = 0; const tm = TAU * Math.round(mr * cycles), fbe = fb * ease * 0.5;
      if (st) { const ts = TAU * Math.round(st[0] * cycles); for (let n = -A; n < N; n++) { const i = n + A, p = ph[i], m = Math.sin(tm * n / N + mr * p + fbe * (m1 + m2) + st[1] * Math.sin(ts * n / N + st[0] * p)); m2 = m1; m1 = m; M[i] = m; } }
      else for (let n = -A; n < N; n++) { const i = n + A, m = Math.sin(tm * n / N + mr * ph[i] + fbe * (m1 + m2) + 0); m2 = m1; m1 = m; M[i] = m; }
    }
    const d0 = i0 - is, tr = tau * RATE;
    let E = (d0 || AR) && EX.get(tr); if ((d0 || AR) && !E) { E = new Float64Array(A); for (let i = 0; i < A; i++) E[i] = Math.exp(-i / tr); EX.set(tr, E); }
    for (let n = -A; n < 0; n++) { // the attack: the index from i0 to is
      const i = n + A, p = ph[i], ae = AR ? 1 - E[i] * U4[i] : 0; let pm = 0; for (let q = 0; q < P; q++) { const s = pars[q]; pm += (AR ? s[3] + (s[2] - s[3]) * ae : s[2]) * Math.sin(s[0] * n / N + s[1] * p); }
      y[i] += lv * Math.sin(tc * n / N + phj + cr * p + BR[i] * ((is + (d0 ? d0 * E[i] * U4[i] : 0)) * kI * M[i] + pm));
    }
    for (let n = 0; n < N; n++) {
      const i = n + A, p = ph[i]; let pm = 0; for (let q = 0; q < P; q++) { const s = pars[q]; pm += s[4] * Math.sin(s[0] * n / N + s[1] * p); }
      y[i] += lv * Math.sin(tc * n / N + phj + cr * p + BR[i] * ((is + 0) * kI * M[i] + pm));
    }
  });
  // air: noise bands [Hz, + this many times the note, bandwidth/centre, gain, lowest, highest centre, kind],
  // kind 0 white, 1 pink, 2 pink above the centre only; outside the FM. `pre`: before the tone control (bow
  // friction, coloured by the body); otherwise after it (a flute's breath). `reg` raises it up the register;
  // `puff` [Hz, bandwidth/centre, gain, + times the note, decay s] is a burst as the note starts.
  const air = () => {
    const re = new Float64Array(N), im = new Float64Array(N), bands = d.air.bands.map(([b, k, rq, g, lo = 0, hi = 14000, kind = 0]) => [Math.max(lo, Math.min(hi, b + k * f)), rq, g * g, kind]), ga = (d.airGain ?? d.air.gain) * (1 + reg * (d.air.reg ?? 0));
    const nb = bands.length; for (let k = 1; k < N / 2; k++) { const fr = k * RATE / N; let h = 0; for (let q = 0; q < nb; q++) { const [fc, rq, g2, kind] = bands[q]; h += g2 * (kind === 2 ? 1 / (1 + (fc / fr) ** 4) : 1 / (1 + ((fr / fc - fc / fr) / rq) ** 2)) * (kind ? 311.6 / fr : 1); } const c = Math.sqrt(2 / 72000 * RATE / N * h), q = TAU * rnd(); re[k] = c * Math.cos(q); im[k] = -c * Math.sin(q); }
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
