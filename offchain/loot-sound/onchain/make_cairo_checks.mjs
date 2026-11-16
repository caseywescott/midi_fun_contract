// Writes loot/loot_composer/src/checks_data.cairo: the Sound Checks' openings, drills and closes
// (src/loot_checks.js) as op lists that checks.cairo plays. Each op is packed in a u64 (low bits first):
//   a (7) deg kind (3) velocity (7) length or key (12) time (12) part (3) species condition (3)
//   draw condition (2) op (2)
// op: 0 put, 1 hit, 2 the colour drill
// draw condition: 0 always, 1 when the piece's draw is odd, 2 when it is even, 3 when its bit 2 is set
// species condition: 0 always, 1-3 the family (0-2), 4-6 the motif's rhythm (id % 3: 0-2)
// degree: 0 a - 64; 1 the fifth (4) or a - 64 where the tonic's fifth is diminished; 2 the tonic's fifth
//   or octave (c.fifth); 3 the cadence root below the tonic + a - 64; 4 motif degree a / 16 plus
//   a % 16 - 8; 5 trill degree a / 8 (up a step where it lands on a diminished fifth) plus a % 8 - 4.
//   6 the canon's tail note a / 16 (0, 1: the motif's last note stepped home once, twice) plus
//   a % 16 - 8; 7 a % 16 - 8 less motif degree a / 16.
// Checked by the Sound Checks parity fixture (scripts/checks_parity.mjs).   node onchain/make_cairo_checks.mjs
import { writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const BAR = 1920, SEG = 3840;
const out = fileURLToPath(new URL('../../../loot/loot_composer/src/checks_data.cairo', import.meta.url));
const enc = ({ op, cond = 0, sc = 0, part = 0, t = 0, len = 0, vel = 0, dk = 0, a = 0 }) => {
  for (const [v, max] of [[op, 4], [cond, 4], [sc, 8], [part, 8], [t, 4096], [len, 4096], [vel, 128], [dk, 8], [a, 128]]) if (!(v >= 0 && v < max && Number.isInteger(v))) throw new Error('field ' + v);
  return (((((((op * 4 + cond) * 8 + sc) * 8 + part) * 4096 + t) * 4096 + len) * 128 + vel) * 8 + dk) * 128 + a;
};
const MOTIF_RHYTHM = [[240, 240, 240, 240, 480, 480], [360, 120, 360, 120, 480, 480], [120, 360, 120, 360, 480, 480]];
let cond = 0, sc = 0, ops = [];
const lit = (d) => ({ dk: 0, a: d + 64 }), f4 = (d) => ({ dk: 1, a: d + 64 }), FIFTH = { dk: 2, a: 0 }, kc = (o) => ({ dk: 3, a: o + 64 });
const mo = (i, o = 0) => ({ dk: 4, a: i * 16 + o + 8 }), tr = (d0, x) => ({ dk: 5, a: d0 * 8 + x + 4 });
const tail = (i, o = 0) => ({ dk: 6, a: i * 16 + o + 8 }), negmo = (i, o) => ({ dk: 7, a: i * 16 + o + 8 });
const deg = (d) => (typeof d === 'number' ? lit(d) : d);
const put = (part, t, len, d, vel) => ops.push(enc({ op: 0, cond, sc, part, t, len, vel, ...deg(d) }));
const hit = (t, key, vel) => ops.push(enc({ op: 1, cond, sc, t, len: key, vel }));
// the motif in its rhythm: one copy per rhythm
const motif = (part, t, neg, add, vel) => {
  MOTIF_RHYTHM.forEach((mr, r) => { sc = 4 + r; let at = t; mr.forEach((l, k) => { put(part, at, l - 20, neg ? negmo(k, add) : mo(k, add), vel); at += l; }); });
  sc = 0;
};
const roll = (part, t, len, vel) => [0, 2, 4, 7].forEach((d, k) => put(part, t + k * 60, len - k * 60, d, vel));
const special = (op) => ops.push(enc({ op, cond }));
const variants = (fn) => { cond = 1; fn(1); cond = 2; fn(0); cond = 0; };

const pieces = [];
const piece = (fn) => { ops = []; fn(); pieces.push(ops); };
// openings
piece(() => {
  put(4, 0, SEG - 20, 0, 70); put(3, 480, SEG - 500, FIFTH, 60);
  put(0, 960, 70, 2, 70); put(0, 1040, 70, 3, 74); put(0, 1120, 780, 4, 88);
  [5, 4, 3, 4].forEach((d, k) => put(0, 1920 + k * 120, 110, d, 80));
  put(0, 2400, 460, 4, 88); put(0, 2880, 460, 2, 84); put(0, 3360, 460, 0, 92); put(1, 3360, 460, 0, 70);
});
piece(() => {
  [70, 70, 90, 90].forEach((v, k) => hit(k * 480, 42, v)); hit(1680, 45, 84); hit(1800, 43, 92);
  hit(BAR, 36, 104); hit(BAR, 49, 84);
  roll(2, BAR, 1500, 86); put(4, BAR, 1880, 0, 84);
  put(0, BAR + 960, 460, f4(2), 72); put(0, BAR + 1440, 460, 7, 80);
});
piece(() => { motif(0, 0, false, 0, 92); motif(1, BAR, false, 0, 62); });
// drills
piece(() => variants((odd) => {
  motif(0, 0, false, 0, 92);
  if (odd) motif(1, BAR, true, 4, 84); else motif(1, BAR, false, 2, 84);
  put(4, 0, BAR - 20, 0, 76); put(4, BAR, BAR - 20, 0, 76);
}));
piece(() => {
  variants((down) => {
    for (let k = 0; k < 7; k++) { put(2, 2 * k * 240, 220, down ? 7 - k : k, 84); put(2, (2 * k + 1) * 240, 220, down ? 5 - k : k + 2, 76); }
    put(2, 3360, 460, down ? 0 : 7, 92);
    put(4, 0, BAR - 20, 0, 76); put(4, BAR, BAR - 20, 7, 72);
  });
  cond = 3; for (let k = 0; k < 8; k++) hit(k * 480, 42, k % 2 ? 46 : 58); cond = 0;
});
piece(() => special(2));
piece(() => {
  [0, 2, 4, 7, 9, 11, 14, 11, 9, 7, 4, 2, 0, 2, 4, 7].forEach((d, i) => put(2, i * 120, 100, d, i % 4 ? 72 : 88));
  [0, 2, 4, 7, 4, 2, 0, 2].forEach((o, i) => put(2, BAR + i * 120, 100, kc(o), i % 4 ? 72 : 88));
  roll(2, BAR + 960, 900, 90);
  put(4, 0, BAR - 20, 0, 80); put(4, BAR, 940, kc(0), 80); put(4, BAR + 960, 940, 0, 84);
  cond = 1; for (const at of [480, 1440]) [lit(0), lit(2), f4(7)].forEach((d) => put(3, at, 200, d, 66)); cond = 0;
});
piece(() => variants((odd) => {
  const line = [mo(0), mo(1), mo(2), mo(3), mo(4), mo(5), tail(0), tail(1)], up = odd ? 2 : 0;
  line.forEach((d, k) => {
    put(0, k * 240, 220, d, 88); put(1, 480 + k * 240, 220, d, 78); put(0, BAR + k * 240, 220, { dk: d.dk, a: d.a + up }, 88);
    if (k < 6) put(1, BAR + 480 + k * 240, 220, { dk: d.dk, a: d.a + up }, 78);
  });
  put(4, 0, BAR - 20, 0, 72); put(4, BAR, BAR - 20, 0, 72);
}));
piece(() => variants((odd) => {
  [lit(0), lit(7), f4(2), lit(9), lit(7), lit(14), lit(2), lit(0)].forEach((d, k) => put(0, k * 480, 440, d, odd ? 108 - 8 * k : 52 + 8 * k));
  for (let k = 0; k < 4; k++) { [lit(0), lit(2), f4(7)].forEach((d) => put(3, BAR + 240 + k * 480, 120, d, 60)); hit(BAR + k * 480, 36, 84); }
}));
piece(() => {
  // the family's groove, its first half again
  const GROOVE = [
    [[0, 36, 100], [480, 42, 60], [720, 42, 50], [960, 38, 84], [1440, 42, 60], [1680, 42, 50]],
    [[0, 36, 100], [240, 42, 56], [480, 38, 84], [720, 36, 80], [960, 36, 96], [1200, 42, 56], [1440, 38, 88], [1680, 42, 56]],
    [[0, 36, 108], [480, 41, 84], [960, 36, 100], [1200, 36, 84], [1440, 43, 88]],
  ];
  GROOVE.forEach((g, type) => { sc = 1 + type; for (const [off, key, vel] of g) { hit(off, key, vel); if (off < 960) hit(BAR + off, key, vel); } });
  // the bass in the motif's rhythm on the root and the fifth
  MOTIF_RHYTHM.forEach((mr, r) => { sc = 4 + r; let at = 0; mr.forEach((l, k) => { put(4, at, l - 20, k % 2 ? f4(0) : lit(0), 84); at += l; }); });
  sc = 0;
  [45, 45, 43, 43, 41, 41, 38, 38].forEach((key, k) => hit(BAR + 960 + k * 120, key, 76 + 5 * k));
  put(4, BAR, 940, 0, 84);
});
piece(() => variants((odd) => {
  const ds = odd ? [7, 4, 2, 0] : [0, 2, 4, 7], fig = [[0, 1], [1, 0, -1], [0, 1, 0, 1, 0, 1], []];
  ds.forEach((d0, k) => {
    const t0 = k * 960;
    if (k === 3) { put(0, t0, 70, tr(d0, 1), 78); put(0, t0 + 80, 860, tr(d0, 0), 92); }
    else { fig[k].forEach((x, i) => put(0, t0 + i * 60, 55, tr(d0, x), i ? 78 : 88)); put(0, t0 + fig[k].length * 60, 940 - fig[k].length * 60, tr(d0, 0), 88); }
    [lit(0), f4(7), lit(2), f4(7)].forEach((x, i) => put(3, t0 + i * 240, 220, x, 60));
  });
}));
piece(() => {
  variants((odd) => {
    const at = odd ? [7, 4, 2, 0] : [0, 2, 4, 7];
    [0, 2, 1, 3].forEach((part, k) => [0, 1, 2, 3].forEach((i) => put(part, k * 960 + i * 240, i === 3 ? 460 : 220, mo(i, at[k]), 86)));
  });
  put(4, 0, SEG - 20, 0, 66);
});
// closes
piece(() => {
  put(4, 0, 940, kc(0), 84); hit(0, 36, 96); hit(480, 36, 88);
  [-1, 0, 1, 2, 3, 4, 5, 6].forEach((d, i) => { put(0, 960 + i * 120, 110, d, 70 + 5 * i); hit(960 + i * 120, 38, 60 + 7 * i); });
  put(0, BAR, 1400, 7, 104); put(1, BAR, 1400, f4(2), 96); roll(2, BAR, 1400, 96); put(3, BAR, 1400, 2, 90); put(4, BAR, 1400, 0, 100);
  hit(BAR, 36, 110); hit(BAR, 49, 96);
});
piece(() => {
  for (let k = 0; k < 8; k++) { put(0, k * 240, 220, 7 - k, 84 - 2 * k); if (k < 7) put(2, k * 240, 220, 5 - k, 70 - 2 * k); }
  put(4, 0, BAR - 20, 0, 70);
  put(0, BAR, 1700, 0, 80); put(1, BAR, 1700, 0, 70); roll(2, BAR, 1700, 76); put(4, BAR, 1700, 0, 76); hit(BAR, 36, 80);
});
piece(() => {
  for (let k = 0; k < 3; k++) { for (const part of [0, 1, 2, 3, 4]) put(part, k * 480, 400, mo(k), 96); hit(k * 480, 36, 96); }
  hit(1440, 38, 80); hit(1680, 38, 96);
  for (const part of [0, 1, 3, 4]) put(part, BAR, 1400, 0, 104); roll(2, BAR, 1400, 100);
  hit(BAR, 36, 110); hit(BAR, 49, 96);
});

const flat = pieces.flat(), at = [];
let n = 0; for (const p of pieces) { at.push(n); n += p.length; } at.push(n);
// each op as two u32s, low then high, packed 7 u32s to a felt252 (item i at bit 32 * (i % 7))
const words = flat.flatMap((x) => { if (!Number.isSafeInteger(x) || x < 0) throw new Error('op'); return [x % 2 ** 32, Math.floor(x / 2 ** 32)]; });
const packed = [];
for (let i = 0; i < words.length; i += 7) packed.push('0x' + words.slice(i, i + 7).reduce((v, w, j) => v + (BigInt(w) << BigInt(32 * j)), 0n).toString(16));
const src = `//! The Sound Checks' openings (pieces 0-2), drills (3-11) and closes (12-14) as op lists, packed (see
//! offchain/loot-sound/onchain/make_cairo_checks.mjs, which generated this file: do not edit).

/// Op y is u32s 2y (low) and 2y + 1 (high), 7 u32s to a felt (common::at32).
pub const OPS: [felt252; ${packed.length}] = [${packed.join(', ')}];
/// Where piece p starts in OPS (and ends: the next).
pub const PIECE_AT: [u32; ${at.length}] = [${at.join(', ')}];
`;
writeFileSync(out, src);
console.log('wrote', out, flat.length, 'ops');
