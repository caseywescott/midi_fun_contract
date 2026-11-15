// A sustained tone rebuilt from a description of one recorded note, in the browser, when the page loads:
// harmonic levels, noise per octave band, and how far the pitch wanders. One voice whose pitch, level
// and balance of harmonics wander slowly, plus the noise; everything is periodic over the buffer, so it loops with no seam. Prototype for listening.
export const RATE = 32000, N = 65536, EDGES = [0, 250, 500, 1000, 2000, 4000, 8000, 16000];
export const ALPHA = [...Array(95)].map((_, i) => String.fromCharCode(i + 32)).filter((c) => !'"\\<'.includes(c)).join('');
export const rng = (a) => () => { a = a + 0x6d2b79f5 | 0; let t = Math.imul(a ^ a >>> 15, 1 | a); t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t; return ((t ^ t >>> 14) >>> 0) / 4294967296; };
export function fft(re, im) {
  const n = re.length;
  for (let i = 1, j = 0; i < n; i++) { let bit = n >> 1; for (; j & bit; bit >>= 1) j ^= bit; j ^= bit; if (i < j) { let t = re[i]; re[i] = re[j]; re[j] = t; t = im[i]; im[i] = im[j]; im[j] = t; } }
  for (let len = 2; len <= n; len <<= 1) {
    const ang = -2 * Math.PI / len, wr = Math.cos(ang), wi = Math.sin(ang);
    for (let i = 0; i < n; i += len) { let cr = 1, ci = 0; for (let k = 0; k < len / 2; k++) { const p = i + k, q = p + len / 2, xr = re[q] * cr - im[q] * ci, xi = re[q] * ci + im[q] * cr; re[q] = re[p] - xr; im[q] = im[p] - xi; re[p] += xr; im[p] += xi; const t = cr * wr - ci * wi; ci = cr * wi + ci * wr; cr = t; } }
  }
}
/** `cycles` periods in the buffer; `amps` and `noise` are ALPHA text, one character a decibel below the
 *  strongest harmonic (noise: below the harmonics' total power); `cents` the pitch wander (rms). */
export function tone({ cycles, amps, noise, cents, voices = 1, vib }, seed) {
  const rnd = rng(seed), out = new Float32Array(N), TAB = 4096, TAU = 2 * Math.PI;
  const a = [...amps].map((c) => { const q = ALPHA.indexOf(c); return q > 79 ? 0 : 10 ** (-q / 20); });
  let power = 0; for (const v of a) power += v * v / 2;
  power *= 1 + (voices - 1) * 0.5625;
  // `voices` players (a section): each its own phases, wander and a few cents of detuning (whole beat
  // cycles over the buffer, so it still loops), which keeps every harmonic moving against the others.
  // Per voice, two tables share the harmonics' phases and split each harmonic's level unevenly; a slow
  // drift between them moves every harmonic by its own amount while its average level stays as measured.
  const spread = Math.max(1, Math.round(cycles * 0.0029));
  for (let v = 0; v < voices; v++) {
    const A = new Float32Array(TAB + 1), B = new Float32Array(TAB + 1), cyc = cycles + [0, spread, -spread, 2 * spread][v % 4], vg = v ? 0.75 : 1;
    a.forEach((g, h) => { if (!g) return; const u = 0.15 + 0.7 * rnd(), ph = TAU * rnd(), w = TAU * (h + 1) / TAB; for (let i = 0; i < TAB; i++) { const x = g * Math.sin(w * i + ph); A[i] += x * u; B[i] += x * (1 - u); } });
    A[TAB] = A[0]; B[TAB] = B[0];
    // slow wander, 0.5 to 5 Hz: pitch (as phase), the drift between the tables, and level
    const pw = [], mw = [], lw = []; let norm = 0;
    for (let m = 1; m <= 10; m++) { const c = 1 / Math.sqrt(m); norm += c * c / 2; pw.push([m, c, TAU * rnd()]); }
    for (const x of pw) x[1] *= cents / Math.sqrt(norm) * cycles * Math.LN2 / 1200 / (TAU * x[0]);
    for (let m = 1; m <= 6; m++) mw.push([m, (voices > 1 ? 0.42 : 0.3) / Math.sqrt(m), TAU * rnd()]);
    for (let m = 1; m <= 4; m++) lw.push([m, 0.04 / Math.sqrt(m), TAU * rnd()]);
    // a player's vibrato [cents, cycles over the buffer, level swing]: pitch, level and brightness together
    if (vib) { const ph = TAU * rnd(); pw.push([vib[1], vib[0] * cycles * Math.LN2 / 1200 / (TAU * vib[1]), ph - Math.PI / 2]); lw.push([vib[1], vib[2], ph]); mw.push([vib[1], 0.2, ph]); }
    for (let n = 0; n < N; n++) {
      const t = TAU * n / N; let x = cyc * n / N, g = vg, d = 0;
      for (const [m, c, p] of pw) x += c * Math.sin(m * t + p);
      for (const [m, c, p] of mw) d += c * Math.sin(m * t + p);
      for (const [m, c, p] of lw) g += c * Math.sin(m * t + p);
      x = (x - Math.floor(x)) * TAB; const i = x | 0, f = x - i;
      out[n] += g * ((1 + d) * (A[i] + (A[i + 1] - A[i]) * f) + (1 - d) * (B[i] + (B[i + 1] - B[i]) * f));
    }
  }
  // noise: random phases, flat within each band, at its power against the harmonics
  const re = new Float64Array(N), im = new Float64Array(N);
  [...noise].forEach((ch, b) => {
    const lo = Math.max(1, Math.ceil(EDGES[b] * N / RATE)), hi = Math.min(N / 2, Math.ceil(EDGES[b + 1] * N / RATE)), c = Math.sqrt(2 * power * 10 ** (-ALPHA.indexOf(ch) / 10) / (hi - lo));
    for (let k = lo; k < hi; k++) { const p = TAU * rnd(); re[k] = c * Math.cos(p); im[k] = -c * Math.sin(p); }
  });
  fft(re, im);
  let s = 0; for (let n = 0; n < N; n++) { out[n] += re[n]; s += out[n] * out[n]; }
  const k = 0.1 * 32768 / Math.sqrt(s / N); for (let n = 0; n < N; n++) out[n] *= k; // -20 dBFS rms
  return out;
}
