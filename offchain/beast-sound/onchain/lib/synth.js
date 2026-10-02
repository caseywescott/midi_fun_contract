// Synth layer: chiptune instruments defined as data, plus the chip drum kit.
//
// An instrument is { play(kit, dest, t, dur, freq, vel), gain }. Build one from a definition:
//   synth.instrument({ wave: 'tri' | 'p12' | 'p25' | 'p50' | 'saw' | 'noise', octave, gain,
//                      env: { attack, decay, sustain, release },   // frames at 60 fps
//                      vib: { rate, cents, delay }, arp: { cents: [...], frames }, blip, drop })
import { chip, chipDrum } from '../../../../web/beast_sound/chip.js';

export function instrument(def) {
  const { gain = 1.2, ...opts } = def;
  return chip('custom', 'custom', gain, opts);
}

/** Ready-made voices. triangleLead is the Beast default. */
export const presets = {
  triangleLead: { wave: 'tri', gain: 1.3, env: { sustain: 1, release: 2 }, vib: { rate: 6, cents: 30, delay: 0.2 } },
  triangleBass: { wave: 'tri', gain: 1.3, octave: -1, env: { sustain: 1, release: 1 } },
  pulseLead: { wave: 'p25', gain: 1.2, env: { decay: 4, sustain: 0.85, release: 3 }, vib: { rate: 5.5, cents: 20, delay: 0.15 } },
  thinPulse: { wave: 'p12', gain: 1.2, env: { decay: 6, sustain: 0.8, release: 3 }, vib: { rate: 6, cents: 25, delay: 0.18 } },
  square: { wave: 'p50', gain: 1.0, env: { sustain: 1, release: 2 } },
  sawLead: { wave: 'saw', gain: 1.8, env: { attack: 2, decay: 6, sustain: 0.75, release: 4 }, vib: { rate: 5, cents: 18, delay: 0.2 } },
};

/** kind: 'kick' | 'snare' | 'hat' | 'openhat'. kit is { ac } (an AudioContext holder). */
export const drum = chipDrum;
