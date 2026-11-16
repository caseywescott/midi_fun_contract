// Per-zone settings the pack computes in the page instead of storing (most of the harp's data).
// harpAt is banks.mjs's formula, verbatim (clarinetAt and stringAt left with the clarinet and strings they made,
// replaced on 2026-11-16 by Chowning's clarinet and the fm-violin section, which have no zones); the build checks that they give exactly the
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
export const GEN = { h: harpAt };
