// TinyChip: a 50-preset chiptune pack for webaudio-tinysynth, built only from TinySynth's own hooks.
//
//   TinyChip.install(synth)   registers the chip waveforms, puts the presets in programs 0–49 and a
//                             chip drum kit on the drum map (keys 35–59). Select a preset with a
//                             normal MIDI program change (0xC0 | channel, program).
//   TinyChip.PRESETS          [{ program, name, category, p }]   TinyChip.DRUMS  { key: name }
//
// How it gets an 8-bit sound out of TinySynth: an oscillator whose wave name starts with "n" plays a
// looped sample buffer from synth.noiseBuf at playbackRate = note / 440 Hz. Each chip waveform is a
// one-second buffer holding exactly 440 cycles, sampled without band-limiting, so it loops seamlessly
// at any note's pitch and keeps the hard edges of a sound chip (12.5/25/50% pulse, NES 4-bit triangle,
// 4-bit saw, Game Boy wave shapes, NES LFSR noise). Envelopes, vibrato (an FM oscillator on the
// playback rate), arpeggios (a square FM oscillator), pitch blips and drops (TinySynth's p/q sweep)
// are all ordinary TinySynth timbre fields: g output, w wave, t/f frequency ratio/offset, v level,
// a/h/d/s/r envelope (d and r are time constants; a drum lasts 3.5 × its first operator's d),
// p/q pitch sweep to t·p over time constant q.
(function (root) {
  const cents = (c) => 2 ** (c / 1200) - 1;

  // ── waveforms ────────────────────────────────────────────────────
  const tri4 = (x) => { const s = Math.floor(x * 32); return ((s < 16 ? 15 - s : s - 16) / 7.5 - 1) * 0.6; };
  const saw4 = (x) => (Math.floor(x * 16) / 7.5 - 1) * 0.45;
  const pulse = (duty) => (x) => (x < duty ? 0.5 : -0.5);
  // Game Boy wave channel shapes, 32 steps of 4 bits
  const wav1 = (x) => (Math.round(7.5 + 7.5 * Math.sin(2 * Math.PI * Math.floor(x * 32) / 32)) / 7.5 - 1) * 0.5; // stepped sine
  const wav2 = (x) => { const p = 2 * Math.PI * Math.floor(x * 32) / 32; return (Math.round(7.5 + 5 * (Math.sin(p) + 0.5 * Math.sin(2 * p) + 0.3 * Math.sin(3 * p)) / 1.3) / 7.5 - 1) * 0.5; }; // organ-ish
  function lfsr(len, tap) {
    const bits = []; let r = 1;
    for (let i = 0; i < len; i++) { const fb = (r & 1) ^ ((r >> tap) & 1); r = (r >> 1) | (fb << 14); bits.push(r & 1 ? 0.5 : -0.5); }
    return bits;
  }
  const SHORT = lfsr(93, 6), LONG = lfsr(32767, 1);

  function registerWaves(synth) {
    const ac = synth.getAudioContext(), sr = ac.sampleRate;
    const make = (fill) => { const b = ac.createBuffer(1, sr, sr), d = b.getChannelData(0); for (let i = 0; i < sr; i++) d[i] = fill(i); return b; };
    const cyc = (shape) => make((i) => shape(((i * 440) / sr) % 1)); // 440 cycles per second: pitch follows the note
    Object.assign(synth.noiseBuf, {
      nP12: cyc(pulse(0.125)), nP25: cyc(pulse(0.25)), nP50: cyc(pulse(0.5)),
      nTRI: cyc(tri4), nSAW: cyc(saw4), nWV1: cyc(wav1), nWV2: cyc(wav2),
      nMTP: cyc((x) => SHORT[Math.floor(x * 93)]),     // short-mode LFSR as a pitched metallic tone
      nNOI: make((i) => LONG[i % 32767]),             // long-mode LFSR noise (snares, crashes)
      nMET: make((i) => SHORT[i % 93]),               // short-mode LFSR noise (hats, rides)
    });
  }

  // ── preset builders ──────────────────────────────────────────────
  const vib = (rate, c, delay) => ({ g: 1, w: 'triangle', t: 0, f: rate, v: cents(c), a: delay, h: 0, d: 0.01, s: 1, r: 0.05 });
  const lead = (w, o = {}) => [
    { w, v: o.v ?? 0.42, a: o.a ?? 0.003, h: o.h ?? 0.02, d: o.d ?? 0.1, s: o.s ?? 1, r: o.r ?? 0.03, t: o.t ?? 1 },
    ...(o.vib === false ? [] : [vib(o.rate ?? 6, o.c ?? 25, o.delay ?? 0.18)]),
  ];
  const pluck = (w, o = {}) => [{ w, v: o.v ?? 0.5, a: 0.002, h: 0, d: o.d ?? 0.12, s: 0, r: 0.03, t: o.t ?? 1 }];
  const swell = (w, o = {}) => [
    { w, v: o.v ?? 0.34, a: o.a ?? 0.25, h: 0.05, d: 0.5, s: 1, r: o.r ?? 0.25, t: o.t ?? 1 },
    vib(o.rate ?? 4, o.c ?? 12, 0.3),
  ];
  const bass = (w, o = {}) => [{ w, v: o.v ?? 0.5, a: 0.002, h: 0.02, d: o.d ?? 0.2, s: o.s ?? 1, r: 0.03, t: o.t ?? 0.5, p: o.p ?? 1, q: o.q ?? 1 }];
  // Two-step arpeggio: a square FM oscillator alternates the pitch between the note and note × ratio.
  const arp = (w, ratio, o = {}) => [
    { w, v: o.v ?? 0.4, a: 0.003, h: 0.02, d: 0.15, s: o.s ?? 0.85, r: 0.04, t: (1 + ratio) / 2 },
    { g: 1, w: 'square', t: 0, f: o.rate ?? 15, v: (ratio - 1) / (ratio + 1), a: 0, h: 0, d: 0.01, s: 1, r: 0.05 },
  ];
  const sweep = (w, from, o = {}) => [{ w, v: o.v ?? 0.42, a: 0.002, h: 0, d: o.d ?? 0.2, s: o.s ?? 0.7, r: 0.04, t: from, p: 1 / from, q: o.q ?? 0.012 }];
  const fm = (carrier, ratio, index, o = {}) => [
    { w: 'sine', v: o.v ?? 0.45, a: o.a ?? 0.003, h: 0.01, d: o.d ?? 0.6, s: o.s ?? 0, r: o.r ?? 0.15, t: 1 },
    { g: 1, w: carrier, t: ratio, v: index, a: o.ma ?? 0, h: 0, d: o.md ?? 0.4, s: o.ms ?? 0.15, r: 0.1 },
  ];
  const detune = (w, c, o = {}) => [
    { w, v: o.v ?? 0.3, a: o.a ?? 0.003, h: 0.02, d: 0.1, s: 1, r: o.r ?? 0.04 },
    { w, v: o.v ?? 0.3, a: o.a ?? 0.003, h: 0.02, d: 0.1, s: 1, r: o.r ?? 0.04, t: 1 + cents(c) },
  ];

  const P = [];
  const add = (category, name, p) => P.push({ program: P.length, category, name, p });

  // Leads (12)
  add('Lead', 'Triangle Lead (vibrato)', lead('nTRI', { v: 0.55, c: 30, delay: 0.2 }));
  add('Lead', 'Pulse 12.5% Lead', lead('nP12', { d: 0.1, s: 0.8 }));
  add('Lead', 'Pulse 25% Lead', lead('nP25', { s: 0.85, c: 20, delay: 0.15 }));
  add('Lead', 'Square Lead', lead('nP50', { v: 0.36 }));
  add('Lead', '4-bit Saw Lead', lead('nSAW', { v: 0.6, a: 0.02, s: 0.8, c: 18, delay: 0.2 }));
  add('Lead', 'Square Lead (dry)', lead('nP50', { v: 0.36, vib: false }));
  add('Lead', 'Pulse 25% Lead (dry)', lead('nP25', { vib: false }));
  add('Lead', 'Soft Pulse 12.5%', lead('nP12', { d: 0.25, s: 0.55, c: 15 }));
  add('Lead', 'Fast Vibrato Lead', lead('nP25', { rate: 9, c: 40, delay: 0.06 }));
  add('Lead', 'Wide Delayed Vibrato', lead('nP12', { rate: 5, c: 55, delay: 0.35 }));
  add('Lead', 'Detuned Duo (25%)', detune('nP25', 12));
  add('Lead', 'Octave Stack Lead', [...lead('nP50', { v: 0.3, vib: false }), { w: 'nP25', v: 0.16, a: 0.003, h: 0.02, d: 0.1, s: 1, r: 0.03, t: 2 }]);
  // Plucks & keys (8)
  add('Pluck', 'Pulse 25% Pluck', pluck('nP25', { d: 0.14 }));
  add('Pluck', 'Pulse 12.5% Pluck', pluck('nP12', { d: 0.12 }));
  add('Pluck', 'Square Pluck', pluck('nP50', { v: 0.42, d: 0.1 }));
  add('Pluck', 'Triangle Pluck', pluck('nTRI', { v: 0.65, d: 0.18 }));
  add('Pluck', '4-bit Saw Pluck', pluck('nSAW', { v: 0.6, d: 0.13 }));
  add('Pluck', 'Chip Harp', [...pluck('nP25', { d: 0.22, v: 0.4 }), { w: 'nP12', v: 0.18, a: 0.002, h: 0, d: 0.12, s: 0, r: 0.03, t: 2 }]);
  add('Pluck', 'Chip Piano', [{ w: 'nP50', v: 0.42, a: 0.002, h: 0.01, d: 0.35, s: 0.18, r: 0.08 }]);
  add('Pluck', 'Muted Pluck', pluck('nP12', { d: 0.05, v: 0.55 }));
  // Bass (8)
  add('Bass', 'Triangle Bass (NES)', bass('nTRI', { v: 0.7 }));
  add('Bass', 'Pulse Bass', bass('nP25', { v: 0.42, d: 0.25, s: 0.8 }));
  add('Bass', 'Square Bass', bass('nP50', { v: 0.36 }));
  add('Bass', '4-bit Saw Bass (drop)', bass('nSAW', { v: 0.55, d: 0.3, s: 0.6, p: 0.944, q: 0.04 }));
  add('Bass', 'Punch Triangle Bass', [{ w: 'nTRI', v: 0.7, a: 0.002, h: 0.01, d: 0.25, s: 0.85, r: 0.03, t: 1, p: 0.5, q: 0.008 }]);
  add('Bass', 'Sub Octave Bass', [...bass('nTRI', { v: 0.6 }), { w: 'nP50', v: 0.14, a: 0.002, h: 0.02, d: 0.2, s: 1, r: 0.03, t: 0.25 }]);
  add('Bass', 'Pluck Bass', bass('nP25', { v: 0.45, d: 0.12, s: 0 }));
  add('Bass', 'Wave Bass (GB)', bass('nWV1', { v: 0.7 }));
  // Pads & swells (6)
  add('Pad', 'Pulse Swell', swell('nP25'));
  add('Pad', 'Square Swell', swell('nP50', { v: 0.3 }));
  add('Pad', '4-bit Saw Swell', swell('nSAW', { v: 0.6, a: 0.15 }));
  add('Pad', 'Detuned Square Pad', detune('nP50', 14, { v: 0.22, a: 0.3, r: 0.3 }));
  add('Pad', 'Wave Pad (GB)', swell('nWV2', { v: 0.7, a: 0.15 }));
  add('Pad', 'Triangle Pad', swell('nTRI', { v: 0.6, a: 0.3, c: 15 }));
  // Arps & effects (8)
  add('Arp/FX', 'Octave Arp', arp('nP50', 2, { v: 0.34 }));
  add('Arp/FX', 'Fifth Arp', arp('nP25', 1.5));
  add('Arp/FX', 'Major Third Arp', arp('nP25', 2 ** (4 / 12), { rate: 18 }));
  add('Arp/FX', 'Minor Third Arp', arp('nP12', 2 ** (3 / 12), { rate: 18 }));
  add('Arp/FX', 'Pulse Blip', sweep('nP12', 2, { d: 0.15, s: 0.5 }));
  add('Arp/FX', 'Square Blip', sweep('nP50', 2, { v: 0.36, d: 0.12, s: 0.4 }));
  add('Arp/FX', 'Laser Drop', sweep('nP25', 4, { q: 0.06, s: 0.3 }));
  add('Arp/FX', 'Pitch Rise', sweep('nP50', 0.5, { v: 0.36, q: 0.04, s: 0.8 }));
  // Game Boy wave channel (3)
  add('Wave', 'GB Wave Lead', lead('nWV1', { v: 0.65, c: 22 }));
  add('Wave', 'GB Organ Wave', lead('nWV2', { v: 0.6, vib: false }));
  add('Wave', 'GB Wave Pluck', pluck('nWV1', { v: 0.8, d: 0.2 }));
  // FM chip, Genesis / OPL flavour (3)
  add('FM', 'FM Bell', fm('sine', 3.5, 6, { d: 0.9, md: 0.6, ms: 0.1 }));
  add('FM', 'FM Electric Piano', fm('sine', 1, 2.5, { d: 0.7, s: 0.15, md: 0.3, ms: 0.2 }));
  add('FM', 'FM Brass', fm('sine', 1, 3, { a: 0.04, d: 0.3, s: 0.8, ma: 0.06, md: 0.3, ms: 0.6 }));
  // Noise (2)
  add('Noise', 'Metallic Tone', lead('nMTP', { v: 0.42, d: 0.15, s: 0.5, vib: false }));
  add('Noise', 'Noise Hit', [{ w: 'nNOI', v: 0.45, a: 0.002, h: 0, d: 0.06, s: 0, r: 0.03, t: 0, f: 440 }]);

  // ── drum kit (GM keys) ──────────────────────────────────────────
  const kick = (f) => [{ w: 'nTRI', t: 0, f, v: 0.95, a: 0.002, h: 0, d: 0.06, s: 0, r: 0.03, p: 0.28, q: 0.03 }];
  const tom = (f) => [{ w: 'nTRI', t: 0, f, v: 0.75, a: 0.002, h: 0, d: 0.08, s: 0, r: 0.03, p: 0.6, q: 0.05 }];
  const snare = (bright, len) => [
    { w: 'nNOI', t: 0, f: 440 * bright, v: 0.5, a: 0.002, h: 0, d: len, s: 0, r: 0.03 },
    { w: 'nP50', t: 0, f: 200, v: 0.28, a: 0.002, h: 0, d: 0.025, s: 0, r: 0.03, p: 0.55, q: 0.03 },
  ];
  const metal = (rate, len, v = 0.26) => [{ w: 'nMET', t: 0, f: 440 * rate, v, a: 0.001, h: 0, d: len, s: 0, r: 0.02 }];
  const DRUMS = {
    35: ['Kick 2', kick(140)], 36: ['Kick', kick(160)], 37: ['Side Stick', metal(4, 0.012, 0.3)], 38: ['Snare', snare(0.6, 0.05)],
    39: ['Clap', snare(1, 0.035)], 40: ['Snare 2', snare(0.8, 0.045)], 41: ['Low Tom 2', tom(90)], 42: ['Closed Hat', metal(14, 0.014)],
    43: ['Low Tom', tom(105)], 44: ['Pedal Hat', metal(13, 0.02)], 45: ['Mid Tom 2', tom(125)], 46: ['Open Hat', metal(14, 0.06)],
    47: ['Mid Tom', tom(145)], 48: ['High Tom 2', tom(170)], 49: ['Crash', [{ w: 'nNOI', t: 0, f: 880, v: 0.3, a: 0.002, h: 0, d: 0.25, s: 0, r: 0.05 }]],
    50: ['High Tom', tom(200)], 51: ['Ride', metal(11, 0.12, 0.2)], 57: ['Crash 2', [{ w: 'nNOI', t: 0, f: 700, v: 0.3, a: 0.002, h: 0, d: 0.28, s: 0, r: 0.05 }]],
    59: ['Ride 2', metal(10, 0.14, 0.2)],
  };

  function install(synth) {
    registerWaves(synth);
    for (const pr of P) {
      synth.setTimbre(0, pr.program, pr.p.map((o) => ({ ...o })));
      synth.program[pr.program].name = pr.name;
    }
    for (const [key, [name, p]] of Object.entries(DRUMS)) {
      synth.setTimbre(1, +key, p.map((o) => ({ ...o })));
      synth.drummap[+key - 35].name = name;
    }
    return synth;
  }

  root.TinyChip = { install, PRESETS: P, DRUMS: Object.fromEntries(Object.entries(DRUMS).map(([k, [n]]) => [k, n])), WAVES: ['nP12', 'nP25', 'nP50', 'nTRI', 'nSAW', 'nWV1', 'nWV2', 'nMTP', 'nNOI', 'nMET'] };
})(typeof window !== 'undefined' ? window : globalThis);
