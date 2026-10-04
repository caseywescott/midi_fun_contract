// Engine v1.1 (prototype, JS only): engine v1's themes and form with three compositional fixes, for
// listening tests before anything moves to Cairo. v1 is untouched; this reuses its building blocks.
//
//   1. Cadence   the theme's last bar steps to the tonic and holds it.
//   2. Rhythm    the theme is built from 4-beat rhythm cells picked by the motif seed, from a family
//                chosen by the Beast's type; ornament_density decides how many cells carry passing
//                notes. The theme keeps its length, so canon entries and the form are unchanged.
//   3. Voices    every note is checked against every voice sounding with it: thirds and sixths are
//                preferred, clashes on the beat, unisons and parallel 5ths/8ves are avoided by
//                nudging the note a step or two (a free canon instead of a strict one).
//   4. Episodes  no silent bars: from the end of its theme until the next section, every voice plays
//                a sequence of the theme's opening bar (its rhythm and shape, a step lower or higher
//                each bar), then a half cadence onto the dominant of the next section's key (for the
//                last section, the first section's key, so the loop leads back in). Voice-checked.
//   5. Key plan  sections move around the circle of fifths instead of v1's fixed shifts (which
//                include a tritone): the Beast's tier sets how far they may roam (tier 5: one
//                fifth, I-V-IV; tier 1: four fifths, a third relation), its type picks the sharp or
//                flat side. With three or more sections the last is within a fifth of home, so the
//                loop returns smoothly; two-section Beasts alternate home with the dominant (tiers
//                3-5) or a third-related key (tiers 1-2). Never a tritone.
//                Option { keys: 'mode' }: the same plan as diatonic transposition instead: every
//                section stays in the home key and mode, and the theme starts on the planned scale
//                degree (V = degree 5 of the home scale, no new sharps or flats).
//   + Dynamics   each phrase rises toward its highest note; bar downbeats are accented.
//
//   const v11 = createEngineV11(engine);
//   v11.render(beast, live) -> { params, form: { events, sections, section_ticks }, ... }  (v1 shape)
//   v11.metrics(events)     -> rhythm, consonance and cadence numbers (also works on v1 events)
export function createEngineV11(engine) {
  const I = engine.internals, TU = 480, BAR = 4 * TU;

  // Rhythm cells for one 4-beat group: [start, duration, source]. source: a beat index 0-3 (that
  // beat's theme degree), 'p' (a passing or neighbour note toward the next slot), 'T' (the tonic).
  const CELLS = {
    plain: [[0, 480, 0], [480, 480, 1], [960, 480, 2], [1440, 480, 3]],
    long: [[0, 960, 0], [960, 480, 2], [1440, 480, 3]],
    dotted: [[0, 720, 0], [720, 240, 'p'], [960, 480, 2], [1440, 480, 3]],
    run: [[0, 240, 0], [240, 240, 'p'], [480, 480, 1], [960, 480, 2], [1440, 480, 3]],
    lilt: [[0, 480, 0], [480, 240, 1], [720, 240, 'p'], [960, 960, 2]],
    syncop: [[0, 480, 0], [480, 720, 1], [1200, 240, 'p'], [1440, 480, 3]],
    halves: [[0, 960, 0], [960, 960, 2]],
    cadence: [[0, 480, 0], [480, 480, 1], [960, 960, 'T']],
  };
  const PASSING = new Set(['dotted', 'run', 'lilt', 'syncop']);
  // families by beast_type (0 magic, 1 hunter, 2 brute): flowing, driving, heavy
  const FAMILY = [['plain', 'run', 'lilt', 'long'], ['plain', 'dotted', 'syncop', 'run'], ['plain', 'long', 'dotted', 'halves']];
  const mix = (h, x) => { h = Math.imul(h ^ x, 0x9e3779b1) >>> 0; return (h ^ (h >>> 15)) >>> 0; };

  function themeRhythm(p, degrees, motifSeed) {
    const groups = degrees.length / 4, fam = FAMILY[p.weakness % 3] ?? FAMILY[0];
    let h = Number(BigInt(motifSeed) % 4294967291n);
    const slots = [];
    for (let g = 0; g < groups; g++) {
      h = mix(h, g + 1);
      let name;
      if (g === groups - 1) name = 'cadence';
      else if (g === 0) name = fam[h % 2];                  // open plainly: plain or the family's second cell
      else {
        name = fam[h % fam.length];
        if (PASSING.has(name) && (h >>> 8) % 8 >= p.ornament_density + 2) name = 'plain'; // density gates passing notes
      }
      for (const [start, duration, src] of CELLS[name]) slots.push({ time: g * BAR + start, duration, src, group: g });
    }
    // pitches: beat sources take the theme degree; passing notes move toward the next slot; T is the tonic
    const deg = (s) => (s.src === 'T' ? 0 : typeof s.src === 'number' ? degrees[s.group * 4 + s.src] : null);
    slots.forEach((s) => { s.degree = deg(s); });
    slots.forEach((s, i) => {
      if (s.degree !== null) return;
      const a = slots[i - 1].degree, b = slots[i + 1] ? slots[i + 1].degree : 0, d = b - a;
      s.degree = Math.abs(d) >= 2 ? a + Math.sign(d) : d === 0 ? a + 1 : b; // passing, upper neighbour, anticipation
    });
    return slots;
  }

  // the theme's last bar steps to the tonic: [x, ±1, (tonic, long)]
  function cadenceTheme(degrees) {
    const d = degrees.slice(), n = d.length;
    d[n - 3] = d[n - 4] >= 0 ? 1 : -1;
    d[n - 2] = d[n - 3];
    d[n - 1] = 0;
    return d;
  }

  // ── key plan: circle-of-fifths offsets per section, distance from the tier ──
  const REACH = { 1: 4, 2: 3, 3: 2, 4: 1, 5: 1 };            // tier -> furthest key, in fifths from home
  function fifthsPlan(n, reach) {
    if (n <= 1) return [0];
    if (n === 2) return [0, reach >= 3 ? reach : 1];        // close Beasts visit the dominant; far ones a mediant
    if (n === 3) return reach >= 2 ? [0, reach, 1] : [0, 1, -1]; // out to the furthest key, back via the dominant
    const out = [0, 1, reach];
    while (out.length < n - 1) out.push(Math.max(1, out[out.length - 1] - 1)); // drift back toward home
    out.push(reach >= 2 ? 1 : -1);                         // last section a fifth from home: the loop returns
    return out;
  }
  function keyPlan(p) {
    const reach = REACH[p.tier] ?? 1, side = p.weakness === 1 ? -1 : 1;  // flat side for one type, sharp for the others
    return fifthsPlan(p.section_count, reach).map((f) => {
      const st = (((f * side * 7) % 12) + 12) % 12;          // fifths -> semitones above home
      const dg = (((f * side * 4) % 7) + 7) % 7;             // fifths -> scale degrees (a diatonic 5th is 4 steps)
      return { fifths: f * side, shift: st > 6 ? st - 12 : st, degrees: dg > 3 ? dg - 7 : dg }; // nearest register
    });
  }
  const sectionTonic = (p, plan, s) => I.transposedTonic(p.tonic_keynum, plan[s % plan.length].shift);

  const IC = (a, b) => Math.abs(a - b) % 12;
  const dissonant = (ic) => ic === 1 || ic === 2 || ic === 6 || ic === 10 || ic === 11;
  const perfect = (ic) => ic === 0 || ic === 7;
  function choosePitch(cands, time, duration, placed, prevSame) {
    let best = null;
    for (const [adj, pitch] of cands) {
      let score = Math.abs(adj) * 1.5;
      for (const q of placed) {
        if (q.time >= time + duration || q.time + q.duration <= time) continue;
        const ic = IC(pitch, q.pitch), strong = Math.max(time, q.time) % TU === 0;
        if (dissonant(ic)) score += strong ? 10 : 2;
        else if (ic === 0) score += pitch === q.pitch ? 6 : 4;  // unison worst, octave next: keeps the texture full
        else if (ic === 7) score += 0.5;
        // parallel 5ths / 8ves against the note this voice and that voice had before
        if (prevSame && perfect(ic)) {
          const before = placed.find((r) => r.voice_id === q.voice_id && r.time <= prevSame.time && r.time + r.duration > prevSame.time);
          if (before && IC(prevSame.pitch, before.pitch) === ic && prevSame.pitch !== pitch) score += 8;
        }
      }
      if (prevSame && Math.abs(pitch - prevSame.pitch) > 9) score += 3;    // no wild leaps
      if (!best || score < best.score) best = { pitch, score, adj };
    }
    return best;
  }

  function buildSection(p, theme, slots, s, offset, csSeed, sectionTicks, seed, plan, diatonic) {
    const next = s + 1 < p.section_count ? s + 1 : 0;
    const mode = I.canonicalToMelodic(p.mode_id);
    // modulating: each section has its own tonic. diatonic: one home tonic, the theme moved by scale degrees
    const home = I.transposedTonic(p.tonic_keynum, 0);
    const tonic = diatonic ? home : sectionTonic(p, plan, s);
    const shift = diatonic ? plan[s % plan.length].degrees : 0, nextShift = diatonic ? plan[next % plan.length].degrees : 0;
    const out = [], ends = [];
    const realize = (d) => I.realize(d + shift, tonic, mode);
    // the half cadence's target: the next section's dominant chord (bass: its 5th), as pitch classes
    const domPcs = (isBass) => {
      if (diatonic) return (isBass ? [4] : [4, 6, 1]).map((k) => I.realize(nextShift + k, home, mode) % 12);
      const nt = sectionTonic(p, plan, next);
      return (isBass ? [7] : [7, 11, 2]).map((k) => (nt + k) % 12);
    };
    for (let v = 0; v < p.voice_count; v++) {
      const entry = v === 0 ? 0 : v * p.stretto_lag * TU, off = [0, -4, 3][v] ?? -8;
      const map = (d) => (p.use_inversion && v === 1 ? 4 - d : d + off);
      ends.push({ v, map, off });
      let prev = null;
      for (const sl of slots) {
        const base = p.use_inversion && v === 1 ? 4 - sl.degree : sl.degree + off;
        const time = offset + entry + sl.time;
        let pitch;
        if (v === 0) pitch = realize(base);
        else {
          const cands = [0, 1, -1, 2, -2].map((a) => [a, realize(base + a)]);
          pitch = choosePitch(cands, time, sl.duration, out, prev).pitch;
        }
        const e = { time, duration: sl.duration, pitch, velocity: 90, voice_id: v, section: s, role: 'canon', slot: sl };
        out.push(e); prev = e;
      }
      ends[v].last = prev;
    }
    if (p.use_countersubject) {
      // v1's countersubject, in steady quarters against the rhythmic subject, also voice-checked
      const cs = I.generateCountersubject(theme.degrees, csSeed);
      let prev = null;
      cs.forEach((d, i) => {
        const time = offset + i * TU;
        const cands = [0, 1, -1, 2, -2].map((a) => [a, realize(d + a)]);
        const pitch = choosePitch(cands, time, TU, out, prev).pitch;
        const e = { time, duration: TU, pitch, velocity: 90, voice_id: p.voice_count, section: s, role: 'countersubject' };
        out.push(e); prev = e;
      });
      // its episode sequences its own first four notes, in quarters
      ends.push({ v: p.voice_count, map: (d) => d, last: prev, head: cs.slice(0, 4).map((d, i) => ({ time: i * TU, duration: TU, degree: d })) });
    }
    // episodes: every voice fills from the end of its line to the next section
    const sectionEnd = offset + sectionTicks;
    const dir = (seed >>> 3) & 1 ? -1 : 1;
    const bass = Math.min(...ends.map((x) => x.off ?? 99)) ;
    for (const x of ends) {
      const head = x.head || slots.filter((sl) => sl.group === 0);
      episode(out, x, head, dir, sectionEnd, offset, realize, domPcs(x.off === bass), s);
    }
    return out;
  }

  // From the end of a voice's line to the section end: fill to the barline stepping toward the
  // sequence, then sequence bars of the head motif, then a half cadence on the next key's dominant.
  function episode(out, x, head, dir, end, offset, realize, pcs, s) {
    let prev = x.last, t = prev.time + prev.duration;
    if (end - t < 240) return;
    const place = (time, duration, cands, role) => {
      const best = choosePitch(cands, time, duration, out, prev);
      const e = { time, duration, pitch: best.pitch, velocity: 90, voice_id: x.v, section: s, role };
      out.push(e); prev = e;
    };
    const near = (deg) => [0, 1, -1, 2, -2].map((a) => [a, realize(x.map(deg + a))]);
    // the degree this voice's line ended on (inverse of the realize step is not needed: start from the head)
    const headDeg = head.map((h) => h.degree);
    const nextBar = offset + Math.ceil((t - offset) / BAR) * BAR;
    const fullBars = Math.max(0, Math.floor((end - nextBar) / BAR));
    const seqBars = Math.max(0, fullBars - 1);
    // 1. up to the barline: quarters (or one shorter note) leading to the sequence's first note
    const target1 = headDeg[0] + dir;
    for (let k = 0; t < Math.min(nextBar, end) && fullBars > 0; k++) {
      const d = Math.min(TU - (t - offset) % TU || TU, nextBar - t);
      place(t, d, near(target1 - dir * Math.max(0, Math.ceil((nextBar - t) / TU) - 1)), 'episode');
      t += d;
    }
    // 2. sequence: the head motif, a step further each bar
    for (let k = 1; k <= seqBars; k++) {
      for (const h of head) place(t + h.time, h.duration, near(h.degree + dir * k), 'episode');
      t += BAR;
    }
    // 3. half cadence into the next section: two steps, then the next key's dominant chord tone, held
    const left = end - t;
    if (left <= 0) return;
    const dominant = (from) => {
      const c = [];
      for (let m = from - 9; m <= from + 9; m++) if (pcs.includes(((m % 12) + 12) % 12)) c.push([Math.abs(m - from) / 2, m]);
      return c.length ? c : [[0, from]];
    };
    if (left >= BAR) {
      place(t, TU, near(headDeg[0] + dir * (seqBars + 1)), 'cadence');
      place(t + TU, TU, near(headDeg[0] + dir * (seqBars + 1) - dir), 'cadence');
      place(t + 2 * TU, left - 2 * TU, dominant(prev.pitch), 'cadence');
    } else {
      place(t, left, dominant(prev.pitch), 'cadence');
    }
  }

  // phrase arc per voice and section, accents on bar downbeats, articulation by profile, under the ceiling
  function shape(events, p) {
    const ceil = p.velocity_ceiling || 127, groups = {};
    for (const e of events) (groups[e.voice_id + ':' + e.section] ||= []).push(e);
    for (const g of Object.values(groups)) {
      const lo = Math.min(...g.map((e) => e.pitch)), hi = Math.max(...g.map((e) => e.pitch)), lead = g[0].voice_id === 0;
      for (const e of g) {
        let v = (lead ? 80 : 70) + Math.round(16 * (hi > lo ? (e.pitch - lo) / (hi - lo) : 0.5));
        if ((e.time % BAR) === 0) v += 8;
        e.velocity = Math.max(1, Math.min(ceil, v));
        if (p.articulation_profile === 1) e.duration = Math.max(60, Math.floor(e.duration / 2));
        else if (p.articulation_profile === 5) e.duration = Math.max(60, Math.floor(e.duration * 3 / 4));
        delete e.slot;
      }
    }
    return events;
  }

  function render(beast, live, { keys = 'modulate' } = {}) {
    const r = engine.render(beast, live), p = r.params, f = r.form;
    const theme = { ...f.theme, degrees: cadenceTheme(f.theme.degrees) };
    const slots = themeRhythm(p, theme.degrees, f.seeds.motif_seed);
    const csSeed = I.H(p.name_variant_id, p.species_id);
    let events = [];
    const seed = Number(BigInt(f.seeds.motif_seed) % 4294967291n);
    const plan = keyPlan(p);
    for (let s = 0; s < p.section_count; s++) events.push(...buildSection(p, theme, slots, s, s * f.section_ticks, csSeed, f.section_ticks, seed, plan, keys === 'mode'));
    events = shape(events, p).sort((a, b) => a.time - b.time || a.voice_id - b.voice_id);
    return { ...r, form: { ...f, theme, events }, v11: { keyPlan: plan, keys } };
  }

  // numbers for the comparison: rhythm, consonance, texture, cadence
  function metrics(events, form) {
    const durations = new Set(events.map((e) => e.duration)), voices = [...new Set(events.map((e) => e.voice_id))];
    let pairs = 0, clashes = 0, clashesOnBeat = 0, octaves = 0, parallels = 0, moves = 0;
    const onsets = [...new Set(events.map((e) => e.time))].sort((a, b) => a - b);
    const sounding = (t) => events.filter((e) => e.time <= t && e.time + e.duration > t);
    let prevMap = null;
    for (const t of onsets) {
      const now = sounding(t), map = {};
      for (const e of now) map[e.voice_id] = e.pitch;
      for (let i = 0; i < now.length; i++) for (let j = i + 1; j < now.length; j++) {
        const ic = IC(now[i].pitch, now[j].pitch); pairs++;
        if (dissonant(ic)) { clashes++; if (t % TU === 0) clashesOnBeat++; }
        if (ic === 0) octaves++;
      }
      if (prevMap) {
        const ids = Object.keys(map).filter((k) => k in prevMap);
        for (let i = 0; i < ids.length; i++) for (let j = i + 1; j < ids.length; j++) {
          const a = ids[i], b = ids[j]; moves++;
          const i1 = IC(prevMap[a], prevMap[b]), i2 = IC(map[a], map[b]);
          if (perfect(i1) && i1 === i2 && prevMap[a] !== map[a] && prevMap[b] !== map[b]) parallels++;
        }
      }
      prevMap = map;
    }
    // silent time: share of the form (sections × section length) in rests of a beat or more
    const formEnd = form ? form.section_ticks * form.sections.length : Math.ceil(Math.max(...events.map((e) => e.time + e.duration)) / BAR) * BAR;
    const iv = events.map((e) => [e.time, e.time + e.duration]).sort((a, b) => a[0] - b[0]);
    // gaps of a beat or more with nothing sounding (shorter gaps are articulation, not silence)
    let silent = 0, cur = 0;
    for (const [a, b] of iv) { if (a - cur >= TU) silent += a - cur; cur = Math.max(cur, b); }
    if (formEnd - cur >= TU) silent += formEnd - cur;
    const lead = events.filter((e) => e.voice_id === 0 && e.section === 0);
    const tonicPc = lead.length ? lead[0].pitch % 12 : 0;
    return {
      notes: events.length, voices: voices.length, durations: durations.size,
      clashPct: pairs ? +(100 * clashes / pairs).toFixed(1) : 0, clashOnBeatPct: pairs ? +(100 * clashesOnBeat / pairs).toFixed(1) : 0,
      octavePct: pairs ? +(100 * octaves / pairs).toFixed(1) : 0, parallels, moves,
      cadence: lead.length ? lead.filter((e) => e.role !== 'episode' && e.role !== 'cadence').at(-1).pitch % 12 === tonicPc : false,
      silentPct: +(100 * silent / formEnd).toFixed(1),
    };
  }

  // v1's section shifts, for comparison
  const v1KeyPlan = (p) => Array.from({ length: p.section_count }, (_, s) => ({ shift: I.sectionTonicShift(p, s) }));
  return { render, metrics, keyPlan, v1KeyPlan, CELLS, FAMILY, REACH };
}
