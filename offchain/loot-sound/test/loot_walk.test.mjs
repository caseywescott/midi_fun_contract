// The walking bass in the editions: a note on every beat, the root on every downbeat, a step into the
// next bar's root, and no other part changes.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';
import * as E from '../src/loot_editions.js';

function notesOf(body) {
  const out = [], on = new Map();
  let i = 0, t = 0, status = 0;
  while (i < body.length) {
    let d = 0; for (;;) { const b = body[i++]; d = (d << 7) | (b & 127); if (!(b & 128)) break; }
    t += d;
    if (body[i] === 0xff) { i += 3 + body[i + 2]; continue; }
    if (body[i] & 128) status = body[i++];
    const hi = status & 0xf0;
    if (hi === 0xc0) { i += 1; continue; }
    const a = body[i++], b = body[i++];
    if (hi === 0x90 && b > 0) { assert.ok(!on.has(a), `pitch ${a} struck again at ${t}`); on.set(a, [t, b]); }
    else if (hi === 0x80 || hi === 0x90) { const s = on.get(a); assert.ok(s); out.push([s[0], t - s[0], a, s[1]]); on.delete(a); }
  }
  assert.equal(on.size, 0);
  return out.sort((x, y) => x[0] - y[0] || x[2] - y[2]);
}
const METERS = [[4, 4], [3, 4], [6, 8], [2, 4]];

test('walkBass: root on the downbeat, a step into the next root, a chord tone on the strong beat, no gaps', () => {
  let seed = 12345;
  const rnd = (n) => { seed = (Math.imul(seed, 1103515245) + 12345) >>> 0; return (seed >>> 8) % n; };
  for (const [num, den] of METERS) for (let k = 0; k < 400; k++) {
    const roots = Array.from({ length: 8 }, () => rnd(7));
    if (k % 3 === 0) for (let b = 0; b < 8; b += 2) roots[b + 1] = roots[b]; // two bars a chord
    const next = k % 5 === 0 ? null : rnd(7), bar = num * (1920 / den);
    const ns = E.walkBass(roots.slice(), next, num, den, k);
    let t = 0;
    for (const n of ns) { assert.equal(n.t, t, 'a gap or an overlap'); t += n.len; }
    assert.equal(t, 8 * bar);
    for (let b = 0; b < 8; b++) {
      const mine = ns.filter((n) => n.bar === b), to = b < 7 ? roots[b + 1] : next;
      assert.equal(mine[0].t, b * bar);
      const pair = num === 2 && roots[b ^ 1] === roots[b] && !(next === null && b >= 6);
      if (!pair || b % 2 === 0) assert.equal(mine[0].d, roots[b], 'the downbeat is not the root');
      if (to === null) { assert.equal(mine.length, 1); continue; }
      const last = mine[mine.length - 1];
      if (!pair || b % 2 === 1) assert.equal(Math.abs(last.d - to), 1, `${num}/${den} bar ${b}: ${last.d} does not step into ${to}`);
      for (const n of mine) if (n.t % bar === (den === 8 ? 720 : num === 4 ? 960 : -1)) assert.ok([0, 2, 4].includes((((n.d - roots[b]) % 7) + 7) % 7), 'the strong beat is not a chord tone');
    }
  }
});

test('every WALKS line starts on the root and ends a step from the next root', () => {
  assert.equal(E.WALKS.length, 13);
  E.WALKS.forEach((v, i) => { for (const w of v) { assert.equal(w.length, 4); assert.equal(w[0], 0); assert.equal(Math.abs(w[3] - (i - 6)), 1); assert.ok([0, 2, 4].includes(((w[2] % 7) + 7) % 7)); for (let j = 1; j < 4; j++) assert.ok(Math.abs(w[j] - w[j - 1]) <= 4 && w[j] !== w[j - 1]); } });
});

test('a walking track: one bass note a beat, and only the bass differs from the figure', () => {
  let walking = 0, total = 0;
  for (const sp of SPECIES.filter((_, i) => i % 3 === 0)) for (let e = 1; e <= 24; e++) for (const seed of [1n, 77n, 0xdeadbeefcafen]) {
    const S = STYLES[E.editionGenome(e).style], bar = S.num * (1920 / S.den);
    const d = E.editionTrack(sp, false, e, seed);
    if (d.info.bass !== 'none') { total++; if (d.info.walking) walking++; }
    // without the intro some purchases have: this test reads the tunes by their place in time
    const a = E.editionTrack(sp, false, e, seed, null, false, true, false), b = E.editionTrack(sp, false, e, seed, null, false, false, false);
    assert.ok(a.info.walking && !b.info.walking && a.info.bass.includes('walking in') && !b.info.bass.includes('walking'));
    const W = a.info.walkTunes;
    assert.ok(W.length >= 1 && W.length <= 2 && W.every((x) => x >= 2), 'the walk is not in the second half');
    const ia = a.info.channels.indexOf(3);
    assert.ok(ia >= 0, 'a forced walk has no bass');
    const all = notesOf(a.bodies[ia + 1]), jb = b.info.channels.indexOf(3), fig = jb < 0 ? null : notesOf(b.bodies[jb + 1]);
    const inWalk = (t) => W.includes(Math.floor(t / (8 * bar)));
    const bass = all.filter((n) => inWalk(n[0]));
    // outside the walk the figure plays as it would have
    if (fig) assert.deepEqual(all.filter((n) => !inWalk(n[0])), fig.filter((n) => !inWalk(n[0])));
    const per = S.den === 8 ? 4 : S.num, ends = W.includes(3) ? 1 : 0;
    assert.equal(bass.length, (8 * W.length - ends) * per + ends, `${S.key}: ${bass.length} bass notes`);
    for (const [, len, p] of bass) assert.ok(len > 0 && p >= 24 && p <= 67, `bass pitch ${p}`);
    for (let i = 1; i < bass.length; i++) assert.ok(Math.abs(bass[i][2] - bass[i - 1][2]) <= 12, `${S.key}: a leap of ${bass[i][2] - bass[i - 1][2]}`);
    // the other parts are the same notes
    a.info.channels.forEach((ch, i) => { if (ch === 3) return; const j = b.info.channels.indexOf(ch); assert.ok(j >= 0); assert.deepEqual(a.bodies[i + 1], b.bodies[j + 1], `channel ${ch} changed`); });
  }
  assert.ok(walking > total * 0.5 && walking < total * 0.7, `${walking} of ${total} walk`); // three in five
});

test('weekly drift trades the walk for the figure on some weeks', () => {
  let flips = 0, n = 0, spans = new Set();
  for (const sp of SPECIES.slice(0, 10)) for (let p = 1n; p <= 20n; p++) {
    const base = E.editionTrack(sp, false, 3, p);
    for (let w = 0; w < 16; w++) {
      const x = E.editionTrack(sp, false, 3, p, { rhythm: null, rotate: BigInt(w * 16384 + 5 + w * 7 * 65536), dayKnob: 0, delta: 0, day: 30 });
      if (base.info.bass === 'none' || x.info.bass === 'none') continue;
      n++; if (x.info.walking !== base.info.walking) flips++;
      if (x.info.walking) spans.add(x.info.walkTunes.join());
    }
  }
  assert.ok(flips * 6 > n && flips * 3 < n, `${flips} of ${n} weeks`);
  assert.equal(spans.size, 3);
});
