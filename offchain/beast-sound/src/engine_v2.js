// Beast Sound engine v2: invertible canon + V2 ornaments, in plain JavaScript.
//
// Line-for-line port of the Cairo reference:
//   src/composition/beast_engine_v2.cairo           (renderer, options, ornament policy)
//   src/composition/melodic_canon.cairo             (walk_leader_entries_ic_hashed, candidates_at,
//                                                    all_pairs_clash_free, exact_imitation)
//   src/composition/aesthetic_profile.cairo         (profile 25 vertical rules)
//   src/composition/canon_entry_rules.cairo         (pair_constraints_from_entries)
//   src/composition/invertible_counterpoint.cairo   (all_pairs_octave_invertible)
//   src/composition/ornamentation_v2/*.cairo        (engine, ornaments, validation, selection,
//                                                    pitch, profiles, canon adapter)
// Only the paths engine v2 reaches are ported: profile 25, diatonic lattice, seeded selection,
// canon-first workflow, no tiles. Same inputs => same notes and score hash as Cairo; checked by
// test/golden.test.mjs. Every place Cairo would panic throws.

const UNIT = 4; // V2 sub-ticks per structural note
const TICKS_PER_SUBTICK = 120; // 480 per structural note
const TICKS_PER_NOTE = 480;
const ENGINE_V2 = 2;
const HARMONY_FN_MINOR_TONIC = 128;
const ORNAMENT_KIND_COUNT = 36;
const DEGREE_SENTINEL = -999;
const V2_VELOCITY = 90;

export const DEFAULT_V2_OPTIONS = Object.freeze({
  same_melody_each_section: true, // D1
  stretto_entries: true, // D2
  voices_follow_params: true, // D3
  suffix_ornament_policy: true, // D5
  minor_harmony: true, // D6
});

export const ORNAMENT_NAMES = [
  'none', 'passing ↑', 'passing ↓', 'upper neighbor', 'lower neighbor', 'double neighbor (upper first)',
  'double neighbor (lower first)', 'anticipation', 'suspension 4–3', 'suspension 7–6', 'suspension 9–8',
  'suspension 6–5', 'suspension 2–3 (bass)', 'retardation', 'appoggiatura (upper)', 'appoggiatura (lower)',
  'escape (upper)', 'escape (lower)', 'échappée (upper)', 'échappée (lower)', 'cambiata', 'upper mordent',
  'lower mordent', 'turn (upper first)', 'turn (lower first)', 'trill (upper)', 'trill (lower)',
  'acciaccatura (upper)', 'acciaccatura (lower)', 'chromatic approach (above)', 'chromatic approach (below)',
  'enclosure (upper first)', 'enclosure (lower first)', 'arpeggio ↑', 'arpeggio ↓', 'pedal',
];

const absI = (x) => (x < 0 ? -x : x);

// ── profile 25: Renaissance, invertible at the octave (aesthetic_profile.cairo) ──
const P25 = { id: 25, octave: 7, table: [0, 4, 1, 4, 4, 1, 4], maxTier: 1 };
const verticalClass = (a, b) => absI(a - b) % 7;
const verticalOk = (a, b) => P25.table[verticalClass(a, b)] <= P25.maxTier;
const isPerfectVertical = (a, b) => { const c = verticalClass(a, b); return c === 0 || c === 4; };
const FULL_STEPS = Array.from({ length: 15 }, (_, i) => i - 7);
const allowedLeaderSteps = (t) => FULL_STEPS.filter((m) => verticalOk(t, m));
function allowedStepsMultivoice(offsets) {
  let acc = FULL_STEPS.slice();
  for (let i = 0; i + 1 < offsets.length; i++) {
    const allowed = allowedLeaderSteps(offsets[i + 1] - offsets[i]);
    acc = acc.filter((v) => allowed.includes(v));
  }
  return acc;
}

// ── melodic_canon.cairo: the v2 walk ──
function pairConstraintsFromEntries(offsets, entries) {
  const out = [];
  for (let i = 0; i < offsets.length; i++) {
    for (let j = i + 1; j < offsets.length; j++) {
      const w = entries[j] - entries[i];
      if (w < 0) throw new Error('entries must ascend');
      if (w > 0) out.push({ d: offsets[j] - offsets[i], w });
    }
  }
  return out;
}
// melodic_canon.cairo: ic_constraints_all_lags — every lag 1..maxLag, every voice pair.
function constraintsAllLags(offsets, maxLag) {
  const out = [];
  for (let lag = 1; lag <= maxLag; lag++) {
    for (let i = 0; i < offsets.length; i++) for (let j = i + 1; j < offsets.length; j++) out.push({ d: offsets[j] - offsets[i], w: (j - i) * lag });
  }
  return out;
}
// Canon at the sixth below and third above (beast_engine_v2.cairo: v2_offsets, V2_MAX_LAG).
const V2_OFFSETS = [0, -5, 2];
const V2_MAX_LAG = 4;

function windowSum(steps, m, w) {
  let s = m;
  for (let t = 0; t + 1 < w; t++) s += steps[steps.length - 1 - t];
  return s;
}
function candidatesAt(constraints, primaryD, degrees, steps, prefer, lo, hi) {
  const cur = degrees[degrees.length - 1];
  const prim = [], any = [], valid = [];
  const pos = steps.length + 1;
  for (const m of FULL_STEPS) {
    // (a) pairwise vertical rules over every window that closes here
    let ok = true;
    for (const pc of constraints) {
      if (pos >= pc.w && !verticalOk(pc.d, windowSum(steps, m, pc.w))) { ok = false; break; }
    }
    if (!ok) continue;
    // (a.1) invertible counterpoint: no diatonic fifth with any follower
    for (const pc of constraints) {
      if (pos >= pc.w && absI(windowSum(steps, m, pc.w) - pc.d) % 7 === 4) { ok = false; break; }
    }
    if (!ok) continue;
    // (b) parallel perfects (profile 25 forbids an immediate repeat into a perfect)
    if (steps.length > 0 && isPerfectVertical(primaryD, m) && m === steps[steps.length - 1]) continue;
    const next = cur + m;
    valid.push(m);
    if (next >= lo && next <= hi) {
      any.push(m);
      if (prefer.includes(m)) prim.push(m);
    }
  }
  if (prim.length === 1 && prim[0] === 0 && any.length > 0) return any;
  if (prim.length > 0) return prim;
  if (any.length > 0) return any;
  return valid;
}
function cadenceTarget(p, len, primaryD, hasUnit) {
  if (!hasUnit || len < 4 || p + 3 < len) return null;
  return (primaryD < 0 ? -1 : 1) * (len - 1 - p);
}
function pickToward(cands, cur, target) {
  let best = cands[0], bestDist = absI(cur + best - target);
  for (let i = 1; i < cands.length; i++) {
    const d = absI(cur + cands[i] - target);
    if (d < bestDist) { best = cands[i]; bestDist = d; }
  }
  return best;
}

// ── ornamentation_v2/profiles.cairo ──
const STYLES = {
  common_practice: { density: 35, chromaticism: 10, passing_bias: 80, neighbor_bias: 60, suspension_bias: 80, trill_bias: 30, turn_bias: 30, grace_note_bias: 30, chromatic_approach_bias: 20, arpeggiation_bias: 40, pedal_bias: 30, jazz_enclosure_bias: 0, trill_subdivisions: 4, trill_count: 0 },
  baroque: { density: 65, chromaticism: 15, passing_bias: 50, neighbor_bias: 50, suspension_bias: 60, trill_bias: 80, turn_bias: 80, grace_note_bias: 70, chromatic_approach_bias: 20, arpeggiation_bias: 40, pedal_bias: 30, jazz_enclosure_bias: 0, trill_subdivisions: 4, trill_count: 0 },
  modal_canon: { density: 45, chromaticism: 5, passing_bias: 70, neighbor_bias: 80, suspension_bias: 40, trill_bias: 20, turn_bias: 20, grace_note_bias: 20, chromatic_approach_bias: 10, arpeggiation_bias: 50, pedal_bias: 60, jazz_enclosure_bias: 10, trill_subdivisions: 4, trill_count: 0 },
};
export const styleForDensity = (d) => (d >= 5 ? 'baroque' : d >= 3 ? 'modal_canon' : 'common_practice');

// ── ornamentation_v2/selection.cairo: LCG mod 65536 ──
const lcgNext = (state) => (5 * (state === 0 ? 1 : state) + 3) % 65536;
function baseWeight(kind, st) {
  if (kind === 1 || kind === 2) return st.passing_bias;
  if (kind === 3 || kind === 4) return st.neighbor_bias;
  if (kind >= 8 && kind <= 12) return st.suspension_bias;
  if (kind === 25 || kind === 26) return st.trill_bias;
  if (kind === 23 || kind === 24) return st.turn_bias;
  if (kind === 27 || kind === 28) return st.grace_note_bias;
  if (kind === 29 || kind === 30) return st.chromatic_approach_bias;
  if (kind === 33 || kind === 34) return st.arpeggiation_bias;
  if (kind === 35) return st.pedal_bias;
  if (kind === 31 || kind === 32) return st.jazz_enclosure_bias;
  return st.density;
}
function weightRule(kind, beatStrength, st) {
  let w = baseWeight(kind, st);
  if (beatStrength > 75 && [14, 15, 8, 9, 10].includes(kind)) w = Math.floor((w * 3) / 2);
  if (kind >= 29 && kind <= 32 && st.chromaticism < 20) w = Math.floor(w / 10);
  return w === 0 ? 1 : w;
}
function weightedPick(kinds, weights, seed) {
  if (kinds.length === 0) return [0, lcgNext(seed)];
  const total = weights.reduce((a, b) => a + b, 0);
  const raw = lcgNext(seed);
  if (total === 0) return [kinds[raw % kinds.length], raw];
  const target = raw % total;
  let acc = 0;
  for (let i = 0; i < kinds.length; i++) {
    acc += i < weights.length ? weights[i] : 1;
    if (target < acc) return [kinds[i], raw];
  }
  return [kinds[0], raw];
}

export function createEngineV2(engine) {
  const I = engine.internals;
  const { H, enc } = I;
  const SCALES = [[0, 2, 4, 5, 7, 9, 11], [0, 2, 3, 5, 7, 9, 10], [0, 1, 3, 5, 7, 8, 10], [0, 2, 4, 6, 7, 9, 11], [0, 2, 4, 5, 7, 9, 10], [0, 2, 3, 5, 7, 8, 10]];
  const realize = (deg, tonic, mode) => I.realize(deg, tonic, mode);

  // walk_leader_entries_ic_hashed
  const walkLeader = (seed, offsets, entries, len) => walkLeaderConstraints(seed, offsets, pairConstraintsFromEntries(offsets, entries), len);
  // walk_leader_constraints_ic_hashed
  function walkLeaderConstraints(seed, offsets, constraints, len) {
    const prefer = allowedStepsMultivoice(offsets).filter((m) => absI(m) <= 4);
    const primaryD = offsets.length > 1 ? offsets[1] : 0;
    const hasUnit = prefer.includes(1) || prefer.includes(-1);
    const degrees = [0], steps = [];
    let prior = H(seed, 'LEADER_PRIOR_V3');
    for (let p = 1; p < len; p++) {
      const cands = candidatesAt(constraints, primaryD, degrees, steps, prefer, -7, 7);
      if (cands.length === 0) throw new Error('no valid ic leader step');
      const cur = degrees[degrees.length - 1];
      const raw = Number(H(seed, 'LEADER_WALK_V3', p, prior) % 0x100000000n);
      const t = cadenceTarget(p, len, primaryD, hasUnit);
      const m = t === null ? cands[raw % cands.length] : pickToward(cands, cur, t);
      degrees.push(cur + m);
      steps.push(m);
      prior = H(prior, enc(m));
    }
    return { degrees, steps };
  }

  function forEachSoundingPair(degs, voices, fn) {
    let total = degs.length;
    for (const v of voices) total = Math.max(total, degs.length + v.entry);
    for (let t = 0; t < total; t++) {
      for (let a = 0; a < voices.length; a++) {
        for (let b = a + 1; b < voices.length; b++) {
          const va = voices[a], vb = voices[b];
          if (t >= va.entry && t - va.entry < degs.length && t >= vb.entry && t - vb.entry < degs.length) {
            if (!fn(degs[t - va.entry] + va.offset, degs[t - vb.entry] + vb.offset)) return false;
          }
        }
      }
    }
    return true;
  }
  const allPairsClashFree = (degs, voices) => forEachSoundingPair(degs, voices, verticalOk);
  const allPairsOctaveInvertible = (degs, voices) => forEachSoundingPair(degs, voices, (a, b) => absI(a - b) % 7 !== 4);

  // ── ornamentation_v2/pitch.cairo ──
  const midiToPitch = (midi, degree) => ({ pc: midi % 12, midi, degree });
  const modeScalePcs = (mode, keyPc) => SCALES[mode % 6].map((s) => (keyPc + s) % 12);
  const intervalAboveBass = (v, b) => (v >= b ? v - b : v + 12 - b);
  function scaleDegreeForPc(pc, keyPc, mode) {
    const sc = SCALES[mode % 6];
    for (let i = 0; i < sc.length; i++) if ((keyPc + sc[i]) % 12 === pc) return i;
    return DEGREE_SENTINEL;
  }
  function midiFromPcInTonicOctave(tonic, pc) {
    const keyPc = tonic % 12;
    return tonic - keyPc + (pc >= keyPc ? pc - keyPc : pc + 12 - keyPc);
  }
  function commonTonePc(prev, cur, next) {
    for (const pc of prev) if (cur.includes(pc) && next.includes(pc)) return pc;
    return prev.length > 0 ? prev[0] : 0;
  }
  const chromaticApproachMidi = (m, above) => (above ? (m === 0 ? 0 : m - 1) : (m >= 127 ? 127 : m + 1));

  // ── ornamentation_v2/ornaments.cairo ──
  const ev = (pitch, start, duration, role, voice) => ({ pitch, start, duration, velocity: V2_VELOCITY, role, voice });
  const atDeg = (deg, tonic, mode) => midiToPitch(realize(deg, tonic, mode), deg);
  const reqPrev = (k) => k === 1 || k === 2 || k === 5 || k === 6 || (k >= 8 && k <= 13) || k === 35;
  const reqNext = (k) => k === 1 || k === 2 || k === 7 || (k >= 16 && k <= 20);

  function canApply(kind, ctx, anchorDeg, prevDeg, nextDeg, dur, chord, bassPc) {
    if (reqPrev(kind) && !ctx.hasPrev) return false;
    if (reqNext(kind) && !ctx.hasNext) return false;
    if (dur < 2) return false;
    if (kind === 1 || kind === 2) {
      if (!ctx.hasPrev || !ctx.hasNext) return false;
      const dist = absI(nextDeg - prevDeg);
      return dist === 2 || dist === 3;
    }
    if (kind === 3 || kind === 4) return dur >= 3;
    if (kind === 5 || kind === 6) return dur >= 4;
    if (kind === 7) return ctx.hasNext && chord.length > 0;
    if (kind >= 8 && kind <= 11) {
      if (!ctx.hasPrevH || !ctx.hasCurH) return false;
      const heldPc = realize(prevDeg, ctx.keyPc + 60, ctx.mode) % 12;
      const ivl = intervalAboveBass(heldPc, bassPc);
      if (kind === 8) return ivl === 4;
      if (kind === 9) return ivl === 7;
      if (kind === 10) return ivl === 9 || ivl === 2;
      return ivl === 6;
    }
    if (kind === 12 || kind === 13) return ctx.hasPrevH && ctx.hasCurH;
    if (kind === 14 || kind === 15) return dur >= 2;
    if (kind >= 16 && kind <= 19) return ctx.hasNext;
    if (kind === 20) return dur >= 5;
    if (kind >= 21 && kind <= 26) return dur >= 3;
    if (kind >= 27 && kind <= 30) return true;
    if (kind === 31 || kind === 32) return dur >= 3;
    if (kind === 33 || kind === 34) return chord.length >= 2;
    if (kind === 35) return ctx.hasPrevH && ctx.hasNextH;
    return false;
  }

  function generate(kind, ctx, a, prevDeg, nextDeg, start, dur, tonic, chord, prevChord, nextChord) {
    const m = ctx.mode, v = ctx.voice, P = (deg) => atDeg(deg, tonic, m);
    const D = (n) => Math.floor(dur / n);
    if (kind === 1 || kind === 2) {
      if (absI(nextDeg - prevDeg) === 2) {
        const mid = prevDeg + (nextDeg > prevDeg ? 1 : -1), d = D(2);
        return [ev(P(mid), start, d, 1, v), ev(P(a), start + d, dur - d, 0, v)];
      }
      const dir = nextDeg > prevDeg ? 1 : -1, d = D(3);
      return [ev(P(prevDeg + dir), start, d, 1, v), ev(P(prevDeg + dir * 2), start + d, d, 1, v), ev(P(a), start + 2 * d, dur - 2 * d, 0, v)];
    }
    if (kind === 3 || kind === 4) {
      const d = D(3);
      return [ev(P(a), start, d, 0, v), ev(P(a + (kind === 3 ? 1 : -1)), start + d, d, 2, v), ev(P(a), start + 2 * d, dur - 2 * d, 0, v)];
    }
    if (kind === 5 || kind === 6) {
      const d = D(4), first = kind === 5 ? a + 1 : a - 1, second = kind === 5 ? a - 1 : a + 1;
      return [ev(P(a), start, d, 0, v), ev(P(first), start + d, d, 3, v), ev(P(second), start + 2 * d, d, 3, v), ev(P(a), start + 3 * d, dur - 3 * d, 0, v)];
    }
    if (kind >= 8 && kind <= 12) {
      const d = D(3), res = kind === 12 ? a + 1 : prevDeg - 1;
      return [ev(P(prevDeg), start, d, 0, v), ev(P(prevDeg), start + d, d, 4, v), ev(P(res), start + 2 * d, dur - 2 * d, 0, v)];
    }
    if (kind === 13) {
      const d = D(3);
      return [ev(P(prevDeg), start, d, 0, v), ev(P(prevDeg), start + d, d, 5, v), ev(P(prevDeg + 1), start + 2 * d, dur - 2 * d, 0, v)];
    }
    if (kind === 7) {
      const d = D(2);
      return [ev(P(nextDeg), start, d, 6, v), ev(P(a), start + d, dur - d, 0, v)];
    }
    if (kind === 14 || kind === 15) {
      const d = D(2);
      return [ev(P(a + (kind === 14 ? 2 : -2)), start, d, 7, v), ev(P(a), start + d, dur - d, 0, v)];
    }
    if (kind === 16 || kind === 17) {
      const d = D(3);
      return [ev(P(a), start, d, 0, v), ev(P(a + (kind === 16 ? 1 : -1)), start + d, d, 8, v), ev(P(nextDeg), start + 2 * d, dur - 2 * d, 0, v)];
    }
    if (kind === 18 || kind === 19) {
      const d = D(3);
      return [ev(P(a), start, d, 0, v), ev(P(a + (kind === 18 ? 2 : -2)), start + d, d, 9, v), ev(P(nextDeg), start + 2 * d, dur - 2 * d, 0, v)];
    }
    if (kind === 20) {
      const d = D(5), notes = [a, a - 1, a - 3, a - 2, a - 1];
      return notes.map((deg, i) => ev(P(deg), start + i * d, i === 4 ? dur - 4 * d : d, i === 0 || i === 4 ? 0 : 10, v));
    }
    if (kind === 21 || kind === 22) {
      const d = D(3);
      return [ev(P(a), start, d, 0, v), ev(P(a + (kind === 21 ? 1 : -1)), start + d, d, 11, v), ev(P(a), start + 2 * d, dur - 2 * d, 0, v)];
    }
    if (kind === 23 || kind === 24) {
      const d = D(4), x = kind === 23 ? a + 1 : a - 1, y = kind === 23 ? a - 1 : a + 1;
      return [ev(P(x), start, d, 12, v), ev(P(a), start + d, d, 0, v), ev(P(y), start + 2 * d, d, 12, v), ev(P(a), start + 3 * d, dur - 3 * d, 0, v)];
    }
    if (kind === 25 || kind === 26) {
      const aux = a + (kind === 25 ? 1 : -1);
      const subs = ctx.trillSubdivisions, count = ctx.trillCount;
      const n = subs < 2 ? 2 : subs > dur ? dur : subs;
      const d = D(n);
      const active = count === 0 || count >= n ? n : count < 2 ? 2 : count;
      const out = [];
      for (let i = 0; i < active; i++) {
        const thisDur = active === n && i === active - 1 ? dur - (n - 1) * d : d;
        out.push(ev(P(i % 2 === 0 ? a : aux), start + i * d, thisDur, 13, v));
      }
      if (active < n) out.push(ev(P(a), start + active * d, dur - active * d, 0, v));
      return out;
    }
    if (kind === 27 || kind === 28) {
      const g = dur > 1 ? 1 : dur;
      return [ev(P(a + (kind === 27 ? 1 : -1)), start, g, 14, v), ev(P(a), start + g, dur - g, 0, v)];
    }
    if (kind === 29 || kind === 30) {
      const anchorMidi = realize(a, tonic, m), d = D(2);
      return [ev(midiToPitch(chromaticApproachMidi(anchorMidi, kind === 29), DEGREE_SENTINEL), start, d, 15, v), ev(midiToPitch(anchorMidi, a), start + d, dur - d, 0, v)];
    }
    if (kind === 31 || kind === 32) {
      const d = D(3), first = kind === 31 ? a + 1 : a - 1, second = kind === 31 ? a - 1 : a + 1;
      return [ev(P(first), start, d, 16, v), ev(P(second), start + d, d, 16, v), ev(P(a), start + 2 * d, dur - 2 * d, 0, v)];
    }
    if (kind === 33 || kind === 34) {
      const n = chord.length;
      if (n === 0) return [];
      const d = D(n), out = [];
      for (let i = 0; i < n; i++) {
        const pc = chord[kind === 33 ? i : n - 1 - i];
        const deg = scaleDegreeForPc(pc, tonic % 12, m);
        out.push(ev(midiToPitch(midiFromPcInTonicOctave(tonic, pc), deg), start + i * d, i === n - 1 ? dur - (n - 1) * d : d, 0, v));
      }
      return out;
    }
    if (kind === 35) {
      return [ev(midiToPitch(midiFromPcInTonicOctave(tonic, commonTonePc(prevChord, chord, nextChord)), a), start, dur, 18, v)];
    }
    return [ev(P(a), start, dur, 0, v)];
  }

  // ── ornamentation_v2/validation.cairo (strict_canon off, no tiles) ──
  function validateAll(events, start, dur, scalePcs, chord, bassPc, kind) {
    if (events.length === 0) return false;
    let sum = 0;
    for (let i = 0; i < events.length; i++) {
      const e = events[i];
      if (e.duration === 0) return false;
      if (!scalePcs.includes(e.pitch.pc)) return false;
      if (i > 0 && absI(events[i - 1].pitch.midi - e.pitch.midi) > 12) return false;
      sum += e.duration;
    }
    if (sum !== dur) return false;
    if (kind >= 8 && kind <= 12) {
      if (events.length < 3) return false;
      const held = events[1], res = events[2];
      if (kind === 12) { if (!(res.pitch.midi > held.pitch.midi)) return false; } else {
        const ivl = intervalAboveBass(held.pitch.pc, bassPc);
        if (![4, 6, 7, 9, 2].includes(ivl)) return false;
        if (!(res.pitch.midi < held.pitch.midi && chord.includes(res.pitch.pc))) return false;
      }
    } else if (kind === 13) {
      if (events.length < 3 || !(events[2].pitch.midi > events[1].pitch.midi)) return false;
    }
    const boundary = kind === 7 ? 1 : (kind >= 8 && kind <= 13) || kind === 35 ? 2 : 0;
    const first = events[0], last = events[events.length - 1];
    const endsInside = last.start + last.duration <= start + dur;
    return boundary === 0 ? first.start === start && endsInside : first.start >= start && endsInside;
  }

  function safeGenerate(kind, ctx, a, prevDeg, nextDeg, start, dur, tonic, chord, bassPc, prevChord, nextChord, scalePcs) {
    const events = generate(kind, ctx, a, prevDeg, nextDeg, start, dur, tonic, chord, prevChord, nextChord);
    if (validateAll(events, start, dur, scalePcs, chord, bassPc, kind)) return [events, lcgNext(ctx.seed), kind];
    for (const fb of [3, 1]) {
      if (canApply(fb, ctx, a, prevDeg, nextDeg, dur, chord, bassPc)) {
        const out = generate(fb, ctx, a, prevDeg, nextDeg, start, dur, tonic, chord, prevChord, nextChord);
        if (validateAll(out, start, dur, scalePcs, chord, bassPc, fb)) return [out, lcgNext(ctx.seed), fb];
      }
    }
    return [[ev(atDeg(a, tonic, ctx.mode), start, dur, 0, ctx.voice)], lcgNext(ctx.seed), 0];
  }

  function harmonyAt(harmony, time) {
    for (const h of harmony) {
      if (time >= h.start && time < h.start + h.duration) {
        const third = h.function_label === HARMONY_FN_MINOR_TONIC ? 3 : 4;
        return [[h.root_pc, (h.root_pc + third) % 12, (h.root_pc + 7) % 12], h.bass_pc, true];
      }
    }
    return [[], 0, false];
  }

  function ornamentPhrase(phrase, harmony, seed0, style, enabled, degrees, tonic, mode) {
    const scalePcs = modeScalePcs(mode, tonic % 12);
    const out = [];
    let seed = seed0 === 0 ? 7 : seed0;
    for (let i = 0; i < phrase.length; i++) {
      const anchor = phrase[i];
      const a = i < degrees.length ? degrees[i] : 0;
      const prevDeg = i > 0 && i - 1 < degrees.length ? degrees[i - 1] : a;
      const nextDeg = i + 1 < degrees.length ? degrees[i + 1] : a;
      const [chord, bassPc, hasH] = harmonyAt(harmony, anchor.start);
      const [prevChord, , hasPrevH] = i > 0 ? harmonyAt(harmony, phrase[i - 1].start) : [[], 0, false];
      const [nextChord, , hasNextH] = i + 1 < phrase.length ? harmonyAt(harmony, phrase[i + 1].start) : [[], 0, false];
      const ctx = {
        voice: anchor.voice, seed, mode, keyPc: tonic % 12, hasPrev: i > 0, hasNext: i + 1 < phrase.length,
        hasCurH: hasH, hasPrevH, hasNextH, trillSubdivisions: style.trill_subdivisions, trillCount: style.trill_count,
      };
      const cands = enabled.filter((k) => canApply(k, ctx, a, prevDeg, nextDeg, anchor.duration, chord, bassPc));
      if (cands.length === 0) { out.push(anchor); seed = lcgNext(seed); continue; }
      const weights = cands.map((k) => weightRule(k, 80, style));
      const [kind, next] = weightedPick(cands, weights, seed);
      seed = next;
      ctx.seed = seed;
      const [generated, finalSeed, applied] = safeGenerate(kind, ctx, a, prevDeg, nextDeg, anchor.start, anchor.duration, tonic, chord, bassPc, prevChord, nextChord, scalePcs);
      seed = finalSeed;
      for (const g of generated) out.push({ ...g, kind: applied });
    }
    return { events: out, seed };
  }

  function ornamentCanon(canon, harmony, seed0, style, enabled) {
    let seed = seed0 === 0 ? 7 : seed0;
    const all = [];
    for (const voice of canon.voices) {
      const degs = canon.degrees.map((d) => d + voice.offset);
      const phrase = degs.map((deg, i) => ({ pitch: midiToPitch(realize(deg, canon.tonic, canon.mode), deg), start: (i + voice.entry) * UNIT, duration: UNIT, velocity: V2_VELOCITY, role: 0, voice: voice.voice_id }));
      const r = ornamentPhrase(phrase, harmony, seed, style, enabled, degs, canon.tonic, canon.mode);
      seed = r.seed;
      all.push(...r.events);
    }
    return all;
  }

  // ── beast_engine_v2.cairo ──
  function ornamentPolicy(beast) {
    if (beast.prefix === 0) {
      const fam = I.typeTierFamily(beast.beast_type, beast.tier);
      return { profile_id: fam.profile_id, density_cap: 1, allow_chromatic_approach: false, allow_suspension: beast.tier <= 3, allow_trill: false };
    }
    return I.prefix2Policy(beast.suffix - 1);
  }
  function enabledOrnaments(policy, usePolicy) {
    const out = [];
    for (let k = 1; k < ORNAMENT_KIND_COUNT; k++) {
      const blocked = usePolicy && (((k >= 8 && k <= 13) && !policy.allow_suspension) || ((k === 25 || k === 26) && !policy.allow_trill) || ((k >= 29 && k <= 32) && !policy.allow_chromatic_approach));
      if (!blocked) out.push(k);
    }
    return out;
  }
  // beast_engine_v2.cairo: v2_phrase_length (24 notes keeps melodies distinct across a tier)
  const icLength = (tier) => (tier <= 2 ? 36 : tier === 3 ? 28 : 24);
  const ornamentSeed = (ornamentSeed, s) => 1 + (Number(H(ornamentSeed, 'V2_ORN', s) % 0x100000000n) % 65535);

  function eventsHash(events) {
    const words = events.map((e) => (BigInt(e.time) << 64n) + (BigInt(e.duration) << 32n) + (BigInt(e.pitch) << 16n) + (BigInt(e.velocity) << 8n) + BigInt(e.voice_id));
    return H('BEAST_EVENTS_V2', ...words);
  }

  function buildFormV2(p, soundSeed, policy, opts) {
    const seeds = I.deriveSeeds(soundSeed);
    const mode = I.canonicalToMelodic(p.mode_id);
    const len = icLength(p.tier);
    const nv = opts.voices_follow_params ? Math.min(Math.max(p.voice_count, 1), 3) : 3;
    const lag = opts.stretto_entries ? p.stretto_lag : 1;
    const offsets = V2_OFFSETS.slice(0, nv);
    const melodyConstraints = constraintsAllLags(V2_OFFSETS, V2_MAX_LAG);
    const entries = offsets.map((_, v) => v * lag);
    const voices = offsets.map((offset, v) => ({ voice_id: v, offset, entry: entries[v] }));
    const maxEntry = (nv - 1) * lag;
    const cycleSubticks = (len + maxEntry) * UNIT;
    const cycleTicks = (len + maxEntry) * TICKS_PER_NOTE;
    const wantCs = p.use_countersubject || (opts.voices_follow_params && p.voice_count >= 4);
    const enabled = enabledOrnaments(policy, opts.suffix_ornament_policy);
    const style = STYLES[styleForDensity(p.ornament_density)];
    const totalSections = p.section_count + (p.use_inversion ? 1 : 0);
    const leaderSeed = (s) => (opts.same_melody_each_section ? H(seeds.canon_seed, 'V2_LEADER') : H(seeds.canon_seed, 'V2_LEADER', s));

    const motif = walkLeaderConstraints(leaderSeed(0), V2_OFFSETS, melodyConstraints, len);
    const motifHash = I.themeHash(motif.degrees);
    const events = [], written = [], sections = [], kinds = new Map();
    for (let s = 0; s < totalSections; s++) {
      const inversionPass = p.use_inversion && s === p.section_count;
      const base = inversionPass ? p.section_count - 1 : s;
      const shift = I.sectionTonicShift(p, base);
      const tonic = I.transposedTonic(p.tonic_keynum, shift);
      const { degrees } = opts.same_melody_each_section || base === 0 ? motif : walkLeaderConstraints(leaderSeed(base), V2_OFFSETS, melodyConstraints, len);
      if (!allPairsClashFree(degrees, voices)) throw new Error('ic canon clash');
      if (!allPairsOctaveInvertible(degrees, voices)) throw new Error('canon not IC');
      const harmony = [{ root_pc: tonic % 12, bass_pc: tonic % 12, start: 0, duration: cycleSubticks, function_label: opts.minor_harmony ? HARMONY_FN_MINOR_TONIC : 0 }];
      const orn = ornamentCanon({ degrees, voices, tonic, mode }, harmony, ornamentSeed(seeds.ornament_seed, s), style, enabled);
      const start = s * cycleTicks;
      const sectionEvents = [];
      for (const o of orn) {
        const pitch = inversionPass && o.voice === 1 && o.pitch.midi <= 115 ? o.pitch.midi + 12 : o.pitch.midi;
        sectionEvents.push({ time: start + o.start * TICKS_PER_SUBTICK, duration: o.duration * TICKS_PER_SUBTICK, pitch, velocity: o.velocity, voice_id: o.voice, section: s, role: 'canon', ornament: o.kind });
        if (o.kind) kinds.set(o.kind, (kinds.get(o.kind) || 0) + 1);
      }
      if (wantCs && !inversionPass) {
        const cs = I.generateCountersubject(degrees, H(seeds.motif_seed, 'V2_CS', base));
        cs.forEach((d, i) => sectionEvents.push({ time: start + i * TICKS_PER_NOTE, duration: TICKS_PER_NOTE, pitch: realize(d, tonic, mode), velocity: 90, voice_id: nv, section: s, role: 'countersubject', ornament: 0 }));
      }
      sections.push({ id: s, start, tonic, shift, inversionPass });
      written.push(...sectionEvents);
      events.push(...I.articulate(sectionEvents, p.articulation_profile, p.velocity_ceiling));
    }
    const lastEnd = [0, 0, 0, 0, 0];
    for (const e of events) {
      if (e.voice_id >= 5) throw new Error('v2 voice id');
      if (e.time < lastEnd[e.voice_id]) throw new Error('v2 voice overlap');
      lastEnd[e.voice_id] = e.time + e.duration;
    }
    const scoreHash = H('BEAST_SCORE_V2', I.paramsHash(p), motifHash, eventsHash(events), ENGINE_V2);
    return { events, written, score_hash: scoreHash, sections, section_ticks: cycleTicks, theme: { degrees: motif.degrees, theme_hash: motifHash }, seeds, ornamentKinds: kinds, voiceCount: nv, entryLag: lag, style: styleForDensity(p.ornament_density), enabled };
  }

  function renderV2(beast, live, opts = DEFAULT_V2_OPTIONS) {
    const params = I.mapV3(beast, live);
    const seed = I.soundSeed(beast.id, beast.prefix, beast.suffix);
    const form = buildFormV2(params, seed, ornamentPolicy(beast), { ...DEFAULT_V2_OPTIONS, ...opts });
    return { beast, live, params, seed, form, params_hash: I.paramsHash(params), state_hash: engine.musicStateHash(beast, live), engineVersion: 2 };
  }

  // ── BSN2: compact stream for engine v2 scores ──
  // header: version 8 | tempo_us 24 | grid_ticks 12 | articulation 3 | base_velocity 7
  //         | velocity_ceiling 7 | run_count 8                                  (69 bits)
  // trailer: length in grid units 16 (the form's length, for the MIDI file's End of Track)
  // run: voice 4 | start (grid units) 16 | note_count 10                        (30 bits)
  // note: key 7 | written duration in grid units − 1 (3 bits, 1..8)            (10 bits)
  // Runs are the written (pre-articulation) notes in emission order; a run whose voice is not
  // above the previous run's voice starts a new section, where the articulation pattern restarts.
  const GRID = TICKS_PER_SUBTICK;
  function encodeBsn2(result) {
    const w = result.form.written, p = result.params;
    const runs = [];
    w.forEach((e, i) => {
      if (e.time % GRID || e.duration % GRID || e.duration < GRID || e.duration > 8 * GRID) throw new Error('bsn2: off grid');
      if (e.velocity !== 90) throw new Error('bsn2: unexpected velocity');
      const q = w[i - 1];
      if (!q || q.voice_id !== e.voice_id || q.time + q.duration !== e.time || q.section !== e.section) runs.push([]);
      runs[runs.length - 1].push(e);
    });
    const bits = [];
    const push = (v, n) => { if (v < 0 || v >= 2 ** n) throw new Error('bsn2: field overflow'); for (let i = n - 1; i >= 0; i--) bits.push(Math.floor(v / 2 ** i) % 2); };
    push(2, 8); push(p.tempo_us, 24); push(GRID, 12); push(p.articulation_profile, 3); push(90, 7); push(p.velocity_ceiling, 7); push(runs.length, 8);
    for (const r of runs) {
      push(r[0].voice_id, 4); push(r[0].time / GRID, 16); push(r.length, 10);
      for (const e of r) { push(e.pitch, 7); push(e.duration / GRID - 1, 3); }
    }
    push(engine.formLength(result.form) / GRID, 16);
    while (bits.length % 8) bits.push(0);
    const out = new Uint8Array(bits.length / 8);
    for (let i = 0; i < out.length; i++) for (let b = 0; b < 8; b++) out[i] = (out[i] << 1) | bits[i * 8 + b];
    return out;
  }
  function decodeBsn2(input) {
    const bytes = input instanceof Uint8Array ? input : engine.feltsToBytes(input);
    let pos = 0;
    const read = (n) => { let v = 0; for (let i = 0; i < n; i++, pos++) v = v * 2 + ((bytes[pos >> 3] >> (7 - (pos & 7))) & 1); return v; };
    if (read(8) !== 2) throw new Error('not a BSN2 stream');
    const tempo_us = read(24), grid = read(12), articulation = read(3), base = read(7), ceiling = read(7), runCount = read(8);
    const sections = [];
    let prevVoice = Infinity;
    for (let r = 0; r < runCount; r++) {
      const voice = read(4), start = read(16), count = read(10);
      if (voice <= prevVoice) sections.push([]);
      prevVoice = voice;
      let t = start * grid;
      for (let k = 0; k < count; k++) {
        const pitch = read(7), duration = (read(3) + 1) * grid;
        sections[sections.length - 1].push({ time: t, duration, pitch, velocity: base, voice_id: voice });
        t += duration;
      }
    }
    const events = sections.flatMap((sec) => I.articulate(sec, articulation, ceiling).map(({ art, ...e }) => e));
    const length_ticks = bytes.length * 8 - pos >= 16 ? read(16) * grid : 0;
    return { tempo_us, events, length_ticks };
  }
  const bsn2ToMidi = (input) => { const d = decodeBsn2(input); return engine.eventsToMidi(d.events, d.tempo_us, d.length_ticks); };

  return { renderV2, walkLeader, walkLeaderConstraints, constraintsAllLags, ornamentPolicy, enabledOrnaments, eventsHash, encodeBsn2, decodeBsn2, bsn2ToMidi };
}
