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
//                Option { even: true }: sections are an even number of bars by shortening, never
//                stretching: the episode is 1 or 2 bars, whichever makes the section even, and bar
//                pairs are accented (the first bar of each pair stronger). { breath: true } (with
//                even): a single-voice Beast with a 3-bar theme holds its final tonic one bar more,
//                a 4-bar phrase, then a 2-bar episode (6 bars instead of 4).
//                Option { traj: true }: Beast data mapped to musical function by layer (identity,
//                current state, trajectory; see trajectory()): the episodes rise when kills
//                outnumber defeats and fall when defeats lead; later sections develop by the dominant
//                history (kills: tighter stretto, faster motion; defeats: inversion, calmer motion;
//                balanced: sequence); the second name prefix picks the ornament vocabulary (trills
//                or passing notes) while kills set the amount; level and health set voice spacing;
//                rank sets prominence (a ranking shuffle changes only this layer).
//                Kills and defeats are swapped at the input (loothero's listening note: the track
//                comes alive when defeats turn on the inversion, and that should belong to kills):
//                kills now drive inversion and the inverted development, defeats drive the number
//                of sections, stretto and ornament amount, and the bridges' direction follows
//                defeats vs kills.
//                Option { scale: 'wholetone' }: every pitch comes from the whole-tone scale on the
//                home tonic (six equal steps, no fifths) instead of the Beast's mode; a test for the
//                new Beasts.
//                Option { family }: the new Beasts' major-side family (no Beast so far plays a major
//                mode). Each pair shares a tonic, the elemental form alters a note or two:
//                  lydian    Lydian              only the scale (no other change)
//                  sprout    Lydian              tonic drone, voices entering twice as far apart
//                  mushroom  Lydian #5           the same, notes left ringing
//                  brownie   Mixolydian          jig skip (dotted pairs), detached, +5%
//                  fire      Phrygian dominant   jig skip, detached, +12%, bridges climb
//                  tortoise  major pentatonic    long calm notes, low register, -25%
//                  lava      acoustic scale      long calm notes, low register, -25%, bridges sink
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
  function keyPlan(p, flip = false) {
    const reach = REACH[p.tier] ?? 1, side = (p.weakness === 1 ? -1 : 1) * (flip ? -1 : 1);  // flat side for one type, sharp for the others
    return fifthsPlan(p.section_count, reach).map((f) => {
      const st = (((f * side * 7) % 12) + 12) % 12;          // fifths -> semitones above home
      const dg = (((f * side * 4) % 7) + 7) % 7;             // fifths -> scale degrees (a diatonic 5th is 4 steps)
      return { fifths: f * side, shift: st > 6 ? st - 12 : st, degrees: dg > 3 ? dg - 7 : dg }; // nearest register
    });
  }
  const sectionTonic = (p, plan, s) => I.transposedTonic(p.tonic_keynum, plan[s % plan.length].shift);

  // the scale pitches come from: the Beast's mode (v1's realize) or, for the whole-tone test, six equal steps
  const WHOLE_TONE = [0, 2, 4, 6, 8, 10];
  function wholeTone(deg, tonic) {
    const du = deg + 60;
    if (du < 0) throw new Error('wholeTone: degree below lattice');
    return tonic + 12 * Math.floor(du / 6) + WHOLE_TONE[du % 6] - 120;
  }
  let R = I.realize;    // set for the duration of a render

  // ── the new Beasts' family (major side): scale, rhythm feel, tempo, register, texture ──
  const FAMILIES = {
    lydian: { name: 'Lydian', mode: 'Lydian', scale: [0, 2, 4, 6, 7, 9, 11] },   // just the scale, nothing else changed
    sprout: { name: 'Sprout', mode: 'Lydian', scale: [0, 2, 4, 6, 7, 9, 11], drone: true, bloom: true },
    mushroom: { name: 'Mushroom', mode: 'Lydian ♯5', scale: [0, 2, 4, 6, 8, 9, 11], drone: true, bloom: true, ring: true },
    brownie: { name: 'Brownie', mode: 'Mixolydian', scale: [0, 2, 4, 5, 7, 9, 10], jig: true, detached: true, tempo: 1.05 },
    fire: { name: 'Fire broom', mode: 'Phrygian dominant', scale: [0, 1, 4, 5, 7, 8, 10], jig: true, detached: true, tempo: 1.12, direction: 1 },
    tortoise: { name: 'Tortoise', mode: 'major pentatonic', scale: [0, 2, 4, 7, 9], slow: true, low: true, tempo: 0.75 },
    lava: { name: 'Volcanic tortoise', mode: 'acoustic scale (Lydian dominant)', scale: [0, 2, 4, 6, 7, 9, 10], slow: true, low: true, tempo: 0.75, direction: -1 },
  };
  const scaleRealize = (S) => (deg, tonic) => {
    const L = S.length, du = deg + 10 * L;
    if (du < 0) throw new Error('scale: degree below lattice');
    return tonic + 12 * Math.floor(du / L) + S[du % L] - 120;
  };
  let FAM = null;       // set for the duration of a render

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

  function buildSection(p, theme, slots, s, offset, csSeed, sectionTicks, seed, plan, diatonic, tr) {
    // development: sections after the first follow the Beast's dominant history
    const dev = tr && s > 0 ? tr.development : null;
    const lag = dev === 'stretto' ? Math.max(1, p.stretto_lag - 1) : p.stretto_lag;
    if (dev === 'stretto') slots = slots.flatMap((sl) => (sl.duration >= 960 ? [{ ...sl, duration: sl.duration / 2 }, { ...sl, time: sl.time + sl.duration / 2, duration: sl.duration / 2, degree: sl.degree + 1 }] : [sl])); // faster: long notes split, the second a step up
    if (dev === 'inversion') {
      const d0 = slots[0].degree;
      slots = slots.filter((sl) => sl.src !== 'p' && sl.src !== 't').map((sl, i, arr) => ({ ...sl, degree: 2 * d0 - sl.degree, duration: (arr[i + 1] ? arr[i + 1].time : sl.time + sl.duration) - sl.time })); // mirrored, passing notes absorbed: calmer
      slots[slots.length - 1].degree = 0;                       // still cadences on the tonic
    }
    const offs = tr ? OFFSETS[tr.spacing] : OFFSETS.normal;
    // family register: tortoises sit low (the lead too unless the key is already low)
    const famLow = FAM && FAM.low ? -7 : 0, famLeadLow = FAM && FAM.low && p.tonic_keynum >= 55 ? -7 : 0;
    const next = s + 1 < p.section_count ? s + 1 : 0;
    const mode = I.canonicalToMelodic(p.mode_id);
    // modulating: each section has its own tonic. diatonic: one home tonic, the theme moved by scale degrees
    const home = I.transposedTonic(p.tonic_keynum, 0);
    const tonic = diatonic ? home : sectionTonic(p, plan, s);
    const shift = diatonic ? plan[s % plan.length].degrees : 0, nextShift = diatonic ? plan[next % plan.length].degrees : 0;
    const out = [], ends = [];
    const realize = (d) => R(d + shift, tonic, mode);
    // family drone: the tonic an octave below, a bar at a time, placed first so every voice hears it
    if (FAM && FAM.drone) {
      const dv = p.voice_count + (p.use_countersubject ? 1 : 0);
      for (let t = 0; t < sectionTicks; t += BAR) out.push({ time: offset + t, duration: BAR, pitch: R(-7 + shift, tonic, mode), velocity: 56, voice_id: dv, section: s, role: 'drone' });
    }
    // the half cadence's target: the next section's dominant chord (bass: its 5th), as pitch classes
    const domPcs = (isBass) => {
      if (diatonic) return (isBass ? [4] : [4, 6, 1]).map((k) => R(nextShift + k, home, mode) % 12);
      const nt = sectionTonic(p, plan, next);
      return (isBass ? [7] : [7, 11, 2]).map((k) => (nt + k) % 12);
    };
    for (let v = 0; v < p.voice_count; v++) {
      const entry = v === 0 ? 0 : v * lag * TU, off = offs[v] ?? offs[3];
      const fx = v === 0 ? famLeadLow : famLow;
      const map = (d) => (p.use_inversion && v === 1 ? 4 - d : d + off) + fx;
      ends.push({ v, map, off });
      let prev = null;
      for (const sl of slots) {
        const base = (p.use_inversion && v === 1 ? 4 - sl.degree : sl.degree + off) + fx;
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
    const dir = FAM && FAM.direction ? FAM.direction : tr ? (tr.direction || (s % 2 ? -1 : 1)) : (seed >>> 3) & 1 ? -1 : 1;
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
  function shape(events, p, sectionTicks, pairs, prominence = 0) {
    const ceil = p.velocity_ceiling || 127, groups = {};
    // family: mushroom notes ring on to the voice's next note (up to twice their length)
    if (FAM && FAM.ring) {
      const byVoice = {};
      for (const e of events) (byVoice[e.voice_id] ||= []).push(e);
      for (const list of Object.values(byVoice)) { list.sort((a, b) => a.time - b.time); list.forEach((e, i) => { if (e.role === 'drone') return; const next = list[i + 1], sectionEnd = (Math.floor(e.time / sectionTicks) + 1) * sectionTicks; e.duration = Math.min(e.duration * 2, next ? next.time - e.time : e.duration * 2, sectionEnd - e.time); }); }
    }
    for (const e of events) (groups[e.voice_id + ':' + e.section] ||= []).push(e);
    for (const g of Object.values(groups)) {
      const lo = Math.min(...g.map((e) => e.pitch)), hi = Math.max(...g.map((e) => e.pitch)), lead = g[0].voice_id === 0;
      for (const e of g) {
        if (e.role === 'drone') { e.velocity = Math.min(ceil, 56 + ((e.time % sectionTicks) === 0 ? 6 : 0)); delete e.slot; continue; }
        // prominence (rank): the lead stands further out from the other voices
        let v = (lead ? 80 + 4 * prominence : 70 - 2 * prominence) + Math.round(16 * (hi > lo ? (e.pitch - lo) / (hi - lo) : 0.5));
        if ((e.time % BAR) === 0) {
          // bar pairs: the first bar of each pair (counted from the section start) leans harder
          v += (pairs ? (Math.floor((e.time % sectionTicks) / BAR) % 2 === 0 ? 12 : 4) : 8) + (lead ? 2 * prominence : 0);
        }
        e.velocity = Math.max(1, Math.min(ceil, v));
        if (FAM && FAM.detached) e.duration = Math.max(60, Math.floor(e.duration * 0.65));
        else if (p.articulation_profile === 1) e.duration = Math.max(60, Math.floor(e.duration / 2));
        else if (p.articulation_profile === 5) e.duration = Math.max(60, Math.floor(e.duration * 3 / 4));
        delete e.slot;
      }
    }
    return events;
  }

  // override (prototypes: event tracks, drift, specials; absent = no change): { tr: fields replacing
  // the trajectory's, sections: section count, rhythmSeed: re-picks the rhythm cells, flipSide:
  // mirrors the key plan, tempo_us }
  function render(beast, live, { keys = 'modulate', even = false, breath = false, traj = false, scale = 'mode', family = null, override = null } = {}) {
    FAM = family && FAMILIES[family] ? FAMILIES[family] : null;
    R = FAM ? scaleRealize(FAM.scale) : scale === 'wholetone' ? wholeTone : I.realize;
    try { return renderWith(beast, live, { keys, even, breath, traj, scale, family: FAM ? family : null, override: override || {} }); } finally { R = I.realize; FAM = null; }
  }
  function renderWith(beast, live, { keys, even, breath, traj, scale, family, override }) {
    // traj: rank is current state only, so the structure is composed with a neutral rank (v1 lets the
    // crown and top ranks add ornament, accents and a voice); the real rank sets prominence alone
    const swapped = traj ? { ...live, adventurers_killed: live.scars, scars: live.adventurers_killed } : live; // kills <-> defeats
    const structural = traj ? { ...swapped, rank: Math.max(2, live.species_count || 2), species_count: live.species_count || 1 } : live;
    const r = engine.render(beast, structural), f = r.form;
    // family: its tempo, and voices entering twice as far apart for the blooming plant forms
    const p0 = FAM ? { ...r.params, tempo_us: Math.round(r.params.tempo_us / (FAM.tempo || 1)), stretto_lag: FAM.bloom ? r.params.stretto_lag * 2 : r.params.stretto_lag } : r.params;
    const p = override.sections || override.tempo_us ? { ...p0, ...(override.sections ? { section_count: override.sections } : {}), ...(override.tempo_us ? { tempo_us: override.tempo_us } : {}) } : p0;
    if (traj) r.live = { ...swapped };
    const theme = { ...f.theme, degrees: cadenceTheme(f.theme.degrees) };
    const tr = traj ? Object.assign(trajectory(r, live), override.tr || {}) : null;
    let slots = themeRhythm(p, theme.degrees, override.rhythmSeed ?? f.seeds.motif_seed);
    // ornament vocabulary (second name prefix): a trill (upper neighbour and back) replaces a passing note
    if (tr && tr.trill) slots = slots.flatMap((sl, i) => (sl.src === 'p' && sl.duration >= 240
      ? [{ ...sl, src: 't', duration: sl.duration / 2, degree: slots[i - 1].degree + 1 }, { ...sl, src: 't', time: sl.time + sl.duration / 2, duration: sl.duration / 2, degree: slots[i - 1].degree }]
      : [sl]));
    // family rhythm: the jig skip (a beat's quarter becomes a dotted pair, the short note a step up) or
    // calm long notes (passing notes absorbed into the note before)
    if (FAM && FAM.jig) slots = slots.flatMap((sl) => (sl.duration === TU && sl.time % (2 * TU) === 0 && sl.src !== 'T'
      ? [{ ...sl, duration: 320 }, { ...sl, src: 'p', time: sl.time + 320, duration: 160, degree: sl.degree + 1 }] : [sl]));
    if (FAM && FAM.slow) slots = slots.filter((sl) => sl.src !== 'p' && sl.src !== 't').map((sl, i, arr) => ({ ...sl, duration: (arr[i + 1] ? arr[i + 1].time : sl.time + sl.duration) - sl.time }));
    // breath: a lone 3-bar theme holds its final tonic one bar longer (a 4-bar phrase)
    const breathed = even && breath && p.voice_count === 1 && theme.degrees.length === 12;
    if (breathed) slots[slots.length - 1] = { ...slots[slots.length - 1], duration: slots[slots.length - 1].duration + BAR };
    // even: canon end + an episode of 1 or 2 bars, whichever is even (never longer than v1's 2)
    let ticks = f.section_ticks;
    if (even) {
      const themeEnd = Math.max(...slots.map((x) => x.time + x.duration));
      const canonEnd = themeEnd + (p.voice_count - 1) * p.stretto_lag * TU;
      const base = Math.ceil(canonEnd / BAR);
      ticks = ((base + 1) % 2 === 0 ? base + 1 : base + 2) * BAR;
    }
    const csSeed = I.H(p.name_variant_id, p.species_id);
    let events = [];
    const seed = Number(BigInt(f.seeds.motif_seed) % 4294967291n);
    const plan = keyPlan(p, !!override.flipSide);
    for (let s = 0; s < p.section_count; s++) events.push(...buildSection(p, theme, slots, s, s * ticks, csSeed, ticks, seed, plan, keys === 'mode', tr));
    events = shape(events, p, ticks, even, tr ? tr.prominence : 0).sort((a, b) => a.time - b.time || a.voice_id - b.voice_id);
    const sections = Array.from({ length: p.section_count }, (_, i) => ({ ...(f.sections[i] || f.sections[f.sections.length - 1]), start: i * ticks }));
    return { ...r, params: p, form: { ...f, theme, events, section_ticks: ticks, sections }, v11: { keyPlan: plan, keys, even, breathed, trajectory: tr, scale, family: family && { id: family, name: FAMILIES[family].name, mode: FAMILIES[family].mode } } };
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
        if (now[i].role === 'drone' || now[j].role === 'drone') continue;   // a pedal point rubs by design
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

  // ── trajectory: Beast data -> musical function ──
  //   direction    kills vs defeats             episodes rise (+1), fall (-1) or alternate (0)
  //   development  dominant history (buckets)   'stretto' | 'inversion' | 'sequence' for sections 2+
  //   spacing      level and health             'wide' | 'normal' | 'close'
  //   prominence   rank (crown 3, top 1% 2, top 5% 1, else 0)
  //   trill        second name prefix policy    trills instead of passing notes
  function trajectory(r, realLive) {
    const p = r.params, k = r.live.adventurers_killed, d = r.live.scars, b = r.beast;
    const real = realLive ? engine.musicState(realLive) : p._state;
    const st = { ...p._state, rank_tier: real.rank_tier, is_crown: real.is_crown };  // only the rank comes from the real stats
    const kb = st.kill_bucket, db = st.defeat_bucket;
    return {
      direction: k > d ? 1 : k < d ? -1 : 0,
      development: kb >= db + 2 ? 'stretto' : db >= 1 && db >= kb ? 'inversion' : 'sequence',
      spacing: b.level >= 100 || b.health >= 500 ? 'wide' : b.level < 20 && b.health < 120 ? 'close' : 'normal',
      prominence: st.is_crown ? 3 : st.rank_tier <= 1 ? 2 : st.rank_tier === 2 ? 1 : 0,
      trill: !!(p._ornament && p._ornament.allow_trill),
      ornamentDensity: p.ornament_density,
    };
  }
  const OFFSETS = { wide: [0, -4, 7, -11], normal: [0, -4, 3, -8], close: [0, -2, 2, -5] };

  // v1's section shifts, for comparison
  const v1KeyPlan = (p) => Array.from({ length: p.section_count }, (_, s) => ({ shift: I.sectionTonicShift(p, s) }));
  return { render, metrics, keyPlan, v1KeyPlan, trajectory, CELLS, FAMILY, REACH, FAMILIES };
}
