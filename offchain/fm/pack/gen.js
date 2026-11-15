// Per-zone settings the pack computes in the page instead of storing (each was most of its instrument's data).
// harpAt and clarinetAt are banks.mjs's formulas, verbatim; the build checks that they give exactly the
// numbers stored in the reference bank and stores the numbers instead if they ever do not.
export function harpAt(m) {
  const B = 2, f = 440 * 2 ** ((m - 69) / 12), r = (v) => +v.toFixed(4), c01 = (v) => Math.max(0, Math.min(1, v)), reg = c01((m - 24) / 79), bass = c01((60 - m) / 24);
  const tr = f < 700 ? 1 : Math.max(0.16, 0.16 ** (Math.log(f / 700) / Math.log(3135.9635 / 700))), t60 = 10.5 * (1.6 / 10.5) ** (Math.log(f / 32.7032) / Math.log(3135.9635 / 32.7032)), rise = 0.00282 * (1.12 - 0.4 * reg);
  return { ops: [
    [1, 1, r(B * 0.749 * tr), r(B * 0.211 * tr), 0.07, 1, r(60 / t60), 0, null, null, 0, [r(B * 0.0497 * tr), r(t60 * 0.09)], r(rise)],
    [2, 1, r(1.5 * 0.5425 * tr), r(1.5 * 0.0434 * tr), 0.026, r(1.5 * 0.196), r(60 / (0.43 * t60)), 0, null, null, 0, [0, r(t60 * 0.05)], r(rise * 0.75)],
    [r(2 ** (0.55 * (0.35 + 0.25 * reg) / 1200)), 2, r(0.018 + 0.15 * tr), r(0.018 + 0.036 * tr), 0.048, 0.156, r(40 / t60), 0, null, null, 0, [r(0.018 + 0.0018 * tr), r(t60 * 0.09)], r(0.018 + 0.018 * bass)],
    [3, 2.027, r(0.724 * tr), 0, 0.005, r(0.0196 * (1 - 0.55 * reg)), 2500, 0, null, null, 0, null, 0.0007, 1]] };
}
export function clarinetAt(m) {
  const c01 = (v) => Math.max(0, Math.min(1, v)), r = (v) => +v.toFixed(4), throat = (1 - c01(Math.abs(m - 67) / 3.5)) ** 2, clarion = c01((m - 67) / 6), alt = c01((m - 85) / 9);
  const k = (1 - 0.17 * throat) * (1 - 0.32 * alt), odd = 0.883 * k, start = 0.364 * k, evenLevel = (0.018 + 0.075 * throat + 0.22 * clarion + 0.055 * alt) * 0.66, norm = 1 / (1 + 0.4 * evenLevel);
  return { ops: [[1, 2, r(start), r(odd), 0.038, r(norm), 0, 0, null, [[4, r(0.0368 * (1 - 0.65 * alt))], [1, r((0.008 + 0.045 * throat + 0.075 * clarion) * 0.683)]]], [2, 2, r(0.32 * start), r(0.32 * odd), 0.038, r(evenLevel * norm), 0]],
    eq: [['p', 1150, 1.25, r(-1.8 * (1 - clarion))], ['p', 2957, 1.43, 0.5]],
    airGain: r(0.046 * (1 + 0.25 * throat)) };
}
// A bowed-string zone (banks.mjs stringAt) from its fitted numbers, each in thousandths: [feedback, plain
// fundamental's level, then per carrier: harmonic (not scaled), level, index]; a negative harmonic is followed by
// its attack index too, where 0.28 of the rounded index does not round to the stored one. The second player
// is derived as stringAt derives it.
export function stringZone(a) {
  const r = (v) => +v.toFixed(3), fb = a[0] / 1000, ops = [[1, 1, 0, 0, 0.1, a[1] / 1000, 0]];
  for (let i = 2; i < a.length; i += 3) { const c = a[i], lv = a[i + 1] / 1000, x = a[i + 2] / 1000; ops.push([Math.abs(c), 1, c < 0 ? a[i + 3] / 1000 : r(0.28 * x), x, 0.07, lv, 0, fb]); if (c < 0) i++; }
  return { ops: [...ops, ...ops.map((o, j) => { const q = [...o]; q[5] = r(o[5] * 0.2); q[6] = o[0]; q[4] = j ? 0.09 : 0.1; return q; })] };
}
export const GEN = { h: harpAt, c: clarinetAt };
