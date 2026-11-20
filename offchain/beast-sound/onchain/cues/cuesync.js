// CueSync: Beast art that moves with the music's structure, layered on BeatSync.
//
// BeatSync (onchain/beatsync) steps an animated GIF one frame per eighth note from the audio clock.
// CueSync adds what the tempo alone cannot show, from the cues of onchain/cues/cues.js:
//
//   theme entries   a pulse (scale + brightness + a glow in the entering voice's colour)
//   sections        the backdrop takes the section's key area; a soft sweep on the downbeat
//   climax          a bigger hit: punch, palette flash (hue rotation), a flash of light
//   cadences        the creature settles (bows, dims, desaturates); its frames slow to quarter notes,
//                   and on the final cadence they slow further and hold until the loop comes round
//   velocity        per-voice energy envelopes from every note-on, a gentle breathing of the art
//   downbeats       a small nudge on every bar line
//
// It never touches BeatSync's code: BeatSync takes a `synth` function, and CueSync hands it a clock
// (frameSynth) that is the real tinysynth in 'tempo' mode and a warped one in 'music' mode (the same
// audible tick, run faster at the climax, slower at cadences, stopped at the end). Everything is a
// pure function of the audible tick except the decaying envelopes, so seeking and looping are exact.
//
//   const cs = CueSync.attach({ stage, art, cues, synth: () => synth, onCue, mode: 'music' })
//   BeatSync.attach({ img, svg, synth: cs.frameSynth })      // frames on CueSync's clock
//   cs.setMode('tempo' | 'music'); cs.tick (audible tick or null); cs.energy (per channel 0-1); cs.detach()
(function (root) {
  const VOICE_COLORS = ['#ffcf4a', '#5ad1ff', '#ff7ab6', '#8dff6a', '#c49bff', '#ffa25a', '#6affd8', '#ff6a6a', '#b0b0ff', '#9aa0a6'];

  // the tick being heard now: tinysynth's scheduled tick minus its look-ahead and the output latency
  function audibleTick(s) {
    if (!s || !s.playing || !s.actx || !s.tick2Time) return null;
    const loop = s.loopEnd || s.maxTick;
    const t = s.playTick - (s.playTime - s.actx.currentTime + (s.actx.outputLatency || 0)) / s.tick2Time;
    return loop > 0 ? ((t % loop) + loop) % loop : Math.max(0, t);
  }

  // Frame-clock rate segments [start, rate] over one loop: 2 through the climax bar (frames on 16ths),
  // 0.5 through each cadence (quarters), and at the final cadence 0.5 for half the way to the loop
  // point, then 0 (the creature holds its pose).
  function warpOf(cues) {
    const L = cues.length, bar = cues.bar, ranges = []; // [start, end, rate]; a later range wins
    const sectionEnd = (t) => { const s = cues.sections.find((x) => t >= x.start && t < x.end); return s ? s.end : L; };
    for (const c of cues.cues) {
      if (c.type === 'cadence' && !c.final) ranges.push([c.tick, sectionEnd(c.tick), 0.5]);
      if (c.type === 'cadence' && c.final) { const mid = c.tick + Math.floor((L - c.tick) / 2); ranges.push([c.tick, mid, 0.5], [mid, L, 0]); }
    }
    for (const c of cues.cues) if (c.type === 'climax') ranges.push([c.tick, Math.min(L, c.tick + bar), 2]);
    const rate = (t) => { let r = 1; for (const [a, b, x] of ranges) if (t >= a && t < b) r = x; return r; };
    const points = [...new Set([0, L, ...ranges.flatMap(([a, b]) => [a, b])])].filter((t) => t >= 0 && t <= L).sort((x, y) => x - y);
    const table = []; // [tick, warped tick there, rate from there]
    let acc = 0;
    points.forEach((p, i) => { table.push([p, acc, rate(p)]); if (i + 1 < points.length) acc += (points[i + 1] - p) * rate(p); });
    return (t) => {
      let k = 0;
      while (k + 1 < table.length && table[k + 1][0] <= t) k++;
      const [a, w, r] = table[k];
      return w + (t - a) * r;
    };
  }

  const lowerBound = (arr, t) => { let lo = 0, hi = arr.length; while (lo < hi) { const m = (lo + hi) >> 1; if (arr[m] < t) lo = m + 1; else hi = m; } return lo; };

  function attach({ stage, art, cues, synth, onCue = () => {}, mode = 'music', reduceMotion = false }) {
    const L = cues.length, bar = cues.bar;
    const list = cues.cues, ticks = list.map((c) => c.tick);
    const notes = cues.notes, noteTicks = notes.map((n) => n[0]);
    const warp = warpOf(cues);
    const sectionAt = (t) => cues.sections.find((s) => t >= s.start && t < s.end) || cues.sections[0];
    const cadenceRegions = list.filter((c) => c.type === 'cadence').map((c) => [c.tick, c.final ? L : (sectionAt(c.tick) || { end: L }).end, c.final]);
    const state = { mode, tick: null, last: null, energy: {}, pulse: 0, pulseColor: VOICE_COLORS[0], hit: 0, sweep: 0, nudge: 0, settle: 0, t0: performance.now() };
    // frames for BeatSync: the real synth (tempo) or the warped audible tick (music)
    const warped = { playing: 1, actx: { currentTime: 0 }, tick2Time: 1, playTime: 0, playTick: 0, loopEnd: 0, maxTick: 1e12, song: { timebase: 4 * cues.ppq } };
    const frameSynth = () => {
      const s = synth();
      if (state.mode !== 'music') return s;
      const t = audibleTick(s);
      if (t == null) return s;
      warped.playTick = warp(t);
      warped.song.timebase = (s.song && s.song.timebase) || 4 * cues.ppq;
      return warped;
    };

    const fire = (from, to) => { // cues and notes with from < tick <= to (no wrap)
      for (let i = lowerBound(ticks, from + 1e-6); i < list.length && ticks[i] <= to; i++) trigger(list[i]);
      for (let i = lowerBound(noteTicks, from + 1e-6); i < notes.length && noteTicks[i] <= to; i++) {
        const [, ch, vel] = notes[i];
        state.energy[ch] = Math.max(state.energy[ch] || 0, vel / 127);
      }
    };
    function trigger(c) {
      if (state.mode === 'music') {
        if (c.type === 'entry') {
          const amp = c.role === 'countersubject' ? 0.55 : c.voice === 0 ? 1 : 0.75;
          if (amp >= state.pulse * 0.8) state.pulseColor = VOICE_COLORS[c.voice % VOICE_COLORS.length];
          state.pulse = Math.max(state.pulse, amp);
        } else if (c.type === 'climax') state.hit = 1;
        else if (c.type === 'section') state.sweep = 1;
        else if (c.type === 'bar') state.nudge = 1;
      }
      onCue(c);
    }

    let raf = 0, prev = performance.now();
    function frame(now) {
      const dt = Math.min(0.1, (now - prev) / 1000); prev = now;
      const s = synth(), t = audibleTick(s);
      if (t == null) { state.last = null; state.tick = null; }
      else {
        // per frame the tick moves a little; a jump of a bar or more is a seek: start over there
        if (state.last == null) fire(t - 1, t);
        else if (t >= state.last) { if (t - state.last < bar) fire(state.last, t); }
        else if (L - state.last + t < bar) { fire(state.last, L); fire(-1, t); } // the loop came round
        state.last = t; state.tick = t;
      }
      // envelopes
      const decay = (x, tau) => x * Math.exp(-dt / tau);
      for (const ch in state.energy) state.energy[ch] = decay(state.energy[ch], 0.22);
      state.pulse = decay(state.pulse, 0.32); state.hit = decay(state.hit, 0.75); state.sweep = decay(state.sweep, 0.6); state.nudge = decay(state.nudge, 0.12);
      const inCad = t != null && cadenceRegions.find(([a, b]) => t >= a && t < b);
      const target = state.mode === 'music' && inCad ? (inCad[2] ? 1 : 0.6) : 0;
      state.settle += (target - state.settle) * (1 - Math.exp(-dt / 0.35));
      paint(t);
      raf = requestAnimationFrame(frame);
    }

    function paint(t) {
      if (state.mode !== 'music' || t == null) {
        art.style.transform = ''; art.style.filter = '';
        stage.style.setProperty('--flash', 0); stage.style.setProperty('--sweep', 0);
        if (t == null || state.mode !== 'music') stage.style.removeProperty('--key-hue');
        return;
      }
      const m = reduceMotion ? 0.35 : 1;
      let e = 0, n = 0;
      for (const ch in state.energy) if (+ch !== 9) { e += state.energy[ch]; n++; }
      const energy = n ? e / n : 0;
      const sec = sectionAt(t);
      const scale = 1 + m * (0.07 * state.pulse + 0.13 * state.hit + 0.012 * state.nudge + 0.025 * energy - 0.05 * state.settle);
      const lift = m * (-6 * state.hit + 7 * state.settle);
      const tilt = m * 3 * state.hit * Math.sin(performance.now() / 45);
      art.style.transform = `translateY(${lift.toFixed(2)}px) rotate(${tilt.toFixed(2)}deg) scale(${scale.toFixed(4)})`;
      const glow = Math.max(state.pulse, state.hit);
      art.style.filter = `brightness(${(1 + 0.35 * state.pulse + 0.5 * state.hit - 0.22 * state.settle).toFixed(3)}) saturate(${(1 + 0.8 * state.hit - 0.45 * state.settle).toFixed(3)}) hue-rotate(${Math.round(170 * state.hit)}deg)`
        + (glow > 0.03 ? ` drop-shadow(0 0 ${Math.round(4 + 22 * glow)}px ${state.hit > state.pulse ? '#fff' : state.pulseColor})` : '');
      stage.style.setProperty('--key-hue', String(sec ? (sec.index * 97 + 210) % 360 : 210));
      stage.style.setProperty('--flash', (0.55 * state.hit).toFixed(3));
      stage.style.setProperty('--sweep', state.sweep.toFixed(3));
      stage.style.setProperty('--settle', state.settle.toFixed(3));
    }

    raf = requestAnimationFrame(frame);
    return {
      frameSynth,
      VOICE_COLORS,
      get tick() { return state.tick; },
      get energy() { return state.energy; },
      get mode() { return state.mode; },
      setMode(next) { state.mode = next; state.pulse = state.hit = state.sweep = state.settle = 0; },
      warp,
      detach() { cancelAnimationFrame(raf); art.style.transform = ''; art.style.filter = ''; },
    };
  }

  root.CueSync = { attach, audibleTick, warpOf, VOICE_COLORS };
})(typeof window !== 'undefined' ? window : globalThis);
