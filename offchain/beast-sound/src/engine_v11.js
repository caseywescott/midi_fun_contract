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
          const before = placed.find((r) => r.voice === q.voice && r.time < time && r.time + r.duration >= prevSame.time + prevSame.duration - 1 && r.time <= prevSame.time);
          if (before && IC(prevSame.pitch, before.pitch) === ic && prevSame.pitch !== pitch) score += 8;
        }
      }
      if (prevSame && Math.abs(pitch - prevSame.pitch) > 9) score += 3;    // no wild leaps
      if (!best || score < best.score) best = { pitch, score, adj };
    }
    return best;
  }

  function buildSection(p, theme, slots, s, offset, csSeed) {
    const tonic = I.transposedTonic(p.tonic_keynum, I.sectionTonicShift(p, s));
    const mode = I.canonicalToMelodic(p.mode_id);
    const out = [];
    const realize = (d) => I.realize(d, tonic, mode);
    for (let v = 0; v < p.voice_count; v++) {
      const entry = v === 0 ? 0 : v * p.stretto_lag * TU, off = [0, -4, 3][v] ?? -8;
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
    }
    return out;
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

  function render(beast, live) {
    const r = engine.render(beast, live), p = r.params, f = r.form;
    const theme = { ...f.theme, degrees: cadenceTheme(f.theme.degrees) };
    const slots = themeRhythm(p, theme.degrees, f.seeds.motif_seed);
    const csSeed = I.H(p.name_variant_id, p.species_id);
    let events = [];
    for (let s = 0; s < p.section_count; s++) events.push(...buildSection(p, theme, slots, s, s * f.section_ticks, csSeed));
    events = shape(events, p).sort((a, b) => a.time - b.time || a.voice_id - b.voice_id);
    return { ...r, form: { ...f, theme, events }, v11: { cells: [...new Set(slots.map((x) => x.group))].length } };
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
    const lead = events.filter((e) => e.voice_id === 0 && e.section === 0);
    const tonicPc = lead.length ? lead[0].pitch % 12 : 0;
    return {
      notes: events.length, voices: voices.length, durations: durations.size,
      clashPct: pairs ? +(100 * clashes / pairs).toFixed(1) : 0, clashOnBeatPct: pairs ? +(100 * clashesOnBeat / pairs).toFixed(1) : 0,
      octavePct: pairs ? +(100 * octaves / pairs).toFixed(1) : 0, parallels, moves,
      cadence: lead.length ? lead[lead.length - 1].pitch % 12 === tonicPc : false,
    };
  }

  return { render, metrics, CELLS, FAMILY };
}
