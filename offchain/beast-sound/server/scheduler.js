// Looping lookahead scheduler for the Beast Sound player (pure: no DOM, no WebAudio).
//
// Notes and drums are handed out in small windows ahead of the audio clock. Each pass of the loop is
// rounded up to whole 4-beat bars so the drum pattern stays in place, times are absolute ticks since
// play started (pass * loopTicks + tick), and the hi-hat variation is rolled again every pass.

export const TICKS_PER_BEAT = 480;
export const BAR_TICKS = 4 * TICKS_PER_BEAT;

/** Kick on beat 1, snare on beat 3, hi-hat on every eighth with random variation. */
export function drumPass(loopTicks, random = Math.random) {
  const out = [];
  for (let time = 0; time < loopTicks; time += TICKS_PER_BEAT / 2) {
    const onBeat = time % TICKS_PER_BEAT === 0, beat = time / TICKS_PER_BEAT;
    if (onBeat && beat % 4 === 0) out.push({ time, kind: 'kick', level: 0.32 });
    if (onBeat && beat % 4 === 2) out.push({ time, kind: 'snare', level: 0.16 });
    // accented on the beat, level varies ±30%, about 1 in 8 off-beats opens up
    const open = !onBeat && random() < 0.125;
    const level = (onBeat ? 0.075 : 0.05) * (0.7 + random() * 0.6);
    out.push({ time, kind: open ? 'openhat' : 'hat', level });
  }
  return out;
}

/**
 * @param notes  [[time, duration, pitch, velocity, voice], ...] in ticks
 * @param opts   { tick: seconds per tick, length: the song's length in ticks (optional; a closing rest
 *                counts), drums: bool, loop: bool (default true), onNote(note, t), onDrum(drum, t), random }
 * @returns { start(now), pump(horizon), position(now), loopTicks, passes(), endTime() }
 */
export function createLoopScheduler(notes, { tick, length = 0, drums, loop = true, onNote, onDrum, random = Math.random }) {
  const ticks = Math.max(length, ...notes.map((n) => n[0] + n[1]));
  const loopTicks = Math.ceil(ticks / BAR_TICKS) * BAR_TICKS;
  const order = notes.map((_, i) => i).sort((i, j) => notes[i][0] - notes[j][0] || i - j);
  let t0 = 0, pass = 0, next = 0, nextDrum = 0;
  let drumList = drums ? drumPass(loopTicks, random) : [];
  return {
    loopTicks,
    start(now, lead = 0.2) { t0 = now + lead; },
    // Schedule everything that starts before `horizon` (audio-clock seconds).
    pump(horizon) {
      for (;;) {
        const offset = pass * loopTicks;
        while (next < order.length) {
          const n = notes[order[next]], t = t0 + (offset + n[0]) * tick;
          if (t > horizon) break;
          onNote(n, t);
          next++;
        }
        while (nextDrum < drumList.length) {
          const d = drumList[nextDrum], t = t0 + (offset + d.time) * tick;
          if (t > horizon) break;
          onDrum(d, t);
          nextDrum++;
        }
        if (next < order.length || nextDrum < drumList.length) return;
        if (!loop) return; // one pass only: everything is scheduled
        if (t0 + (offset + loopTicks) * tick > horizon) return;
        pass++; next = 0; nextDrum = 0;
        if (drums) drumList = drumPass(loopTicks, random);
      }
    },
    position(now) { return Math.max(0, (now - t0) / tick) % loopTicks; },
    passes() { return pass; },
    /** Audio-clock time the first pass ends (rounded to whole bars). */
    endTime() { return t0 + loopTicks * tick; },
  };
}
