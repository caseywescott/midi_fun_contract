// TinyChip: a 100-preset chiptune pack for webaudio-tinysynth, built only from TinySynth's own hooks.
//
//   TinyChip.install(synth, { programBase = 0, drums = true })
//                             registers the chip waveforms, puts the presets in programs
//                             programBase … programBase + 99 and (unless drums: false) a chip drum
//                             kit on the drum map (keys 35–59). With programBase 0 a normal MIDI
//                             program change selects a preset; above 127 the General MIDI set stays.
//   TinyChip.attach(synth, { bare, channels, events })
//                             the hook the onchain TinySynth page player calls (see README.md): bare
//                             Beast scores get the chip lead and the chip drum kit; any MIDI file can
//                             select the chip bank on a channel with Bank Select MSB = 1 (CC 0 = 1).
//   TinyChip.PRESETS          [{ program, name, category, inspired?, p }]   TinyChip.DRUMS  { key: name }
//
// Programs 0–49 are generic chip voices. Programs 50–99 are styled after the sound chips and game
// soundtracks of the 8- and 16-bit era (NES and its Famicom expansion chips, Game Boy, C64 SID,
// Atari 2600 TIA, AY/PSG arcade and home computers, Genesis FM, PC Engine). They are original
// approximations made from the chips' waveforms and techniques, not samples.
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
  // Atari 2600 TIA polynomial patterns (poly4: 15 steps, poly5: 31 steps) and its div-31 buzz
  const poly = (bits, taps, len) => { const out = []; let r = (1 << bits) - 1; for (let i = 0; i < len; i++) { const b = ((r >> taps[0]) ^ (r >> taps[1])) & 1; r = ((r << 1) | b) & ((1 << bits) - 1); out.push(r & 1 ? 0.5 : -0.5); } return out; };
  const POLY4 = poly(4, [3, 2], 15), POLY5 = poly(5, [4, 2], 31);
  const step = (table) => (x) => table[Math.floor(x * table.length)];
  const vrc6saw = (x) => (Math.floor(x * 7) / 3 - 1) * 0.5;                    // VRC6: 7-step accumulator saw
  const fdsWave = (x) => { const p = 2 * Math.PI * Math.floor(x * 64) / 64; return Math.round(31.5 + 24 * Math.sin(p) + 7 * Math.sin(3 * p)) / 31.5 - 1; }; // FDS 64×6-bit
  const n163 = (x) => { const k = Math.floor(x * 32); return ((k < 16 ? k : 31 - k) * 0.6 + (k % 8 < 4 ? 4 : 0)) / 7.5 - 1; }; // Namco 163 brassy 4-bit
  const sidCombined = (x) => { const tri = Math.floor((x < 0.5 ? x * 2 : 2 - x * 2) * 255), saw = Math.floor(x * 255); return ((tri & saw) / 127.5 - 1) * 0.6; }; // SID tri & saw
  const pce1 = (x) => { const k = Math.floor(x * 32); return (Math.round(15.5 + 15.5 * Math.sin(2 * Math.PI * k / 32) * (k < 16 ? 1 : 0.4)) / 15.5 - 1) * 0.5; }; // PC Engine 5-bit
  const pce2 = (x) => { const k = Math.floor(x * 32); return ((k * 3) % 32 / 15.5 - 1) * 0.45; };

  function registerWaves(synth) {
    const ac = synth.getAudioContext(), sr = ac.sampleRate;
    const make = (fill) => { const b = ac.createBuffer(1, sr, sr), d = b.getChannelData(0); for (let i = 0; i < sr; i++) d[i] = fill(i); return b; };
    const cyc = (shape) => make((i) => shape(((i * 440) / sr) % 1)); // 440 cycles per second: pitch follows the note
    Object.assign(synth.noiseBuf, {
      nP12: cyc(pulse(0.125)), nP25: cyc(pulse(0.25)), nP50: cyc(pulse(0.5)),
      nTRI: cyc(tri4), nSAW: cyc(saw4), nWV1: cyc(wav1), nWV2: cyc(wav2),
      nMTP: cyc((x) => SHORT[Math.floor(x * 93)]),     // short-mode LFSR as a pitched metallic tone
      nP06: cyc(pulse(0.0625)), nP37: cyc(pulse(0.375)),
      nVRS: cyc(vrc6saw), nFDS: cyc((x) => fdsWave(x) * 0.5), nN16: cyc((x) => n163(x) * 0.5), nSID: cyc(sidCombined),
      nTI4: cyc(step(POLY4)), nTI5: cyc(step(POLY5)), nTIB: cyc((x) => (x < 13 / 31 ? 0.5 : -0.5)),
      nPC1: cyc(pce1), nPC2: cyc(pce2),
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

  // Pulse-width movement (C64 style): two pulse widths a few cents apart phase against each other.
  const pwm = (wa, wb, c, o = {}) => [
    { w: wa, v: o.v ?? 0.3, a: o.a ?? 0.003, h: 0.02, d: o.d ?? 0.1, s: o.s ?? 1, r: o.r ?? 0.04, t: o.t ?? 1 },
    { w: wb, v: o.v ?? 0.3, a: o.a ?? 0.003, h: 0.02, d: o.d ?? 0.1, s: o.s ?? 1, r: o.r ?? 0.04, t: (o.t ?? 1) * (1 + cents(c)) },
    ...(o.vib ? [vib(o.vib[0], o.vib[1], o.vib[2])] : []),
  ];
  // Amplitude modulation of operator 0 (g: 11): tremolo at slow rates, buzz/ring at audio rates.
  const am = (w, modWave, o = {}) => [
    { w, v: o.v ?? 0.4, a: o.a ?? 0.003, h: 0.02, d: o.d ?? 0.15, s: o.s ?? 1, r: o.r ?? 0.04, t: o.t ?? 1 },
    { g: 11, w: modWave, t: o.mt ?? 0, f: o.mf ?? 0, v: o.mv ?? 0.1, a: 0, h: 0, d: 0.01, s: 1, r: 0.05 },
  ];
  const siren = (w, rate, semis, o = {}) => [
    { w, v: o.v ?? 0.45, a: 0.01, h: 0.02, d: 0.1, s: 1, r: 0.05 },
    { g: 1, w: 'triangle', t: 0, f: rate, v: 2 ** (semis / 12) - 1, a: 0, h: 0, d: 0.01, s: 1, r: 0.05 },
  ];

  const P = [];
  const add = (category, name, p, inspired) => P.push({ program: P.length, category, name, p, ...(inspired ? { inspired } : {}) });

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

  // ── 50–99: styled after classic sound chips and soundtracks ───────
  // NES 2A03 (12)
  add('NES', 'Robot Hero Lead', lead('nP50', { v: 0.36, rate: 8, c: 35, delay: 0.08 }), 'Mega Man 2 (NES)');
  add('NES', 'Vampire Hunter Lead', detune('nP25', 8, { v: 0.3, a: 0.012 }), 'Castlevania (NES)');
  add('NES', 'Plumber Lead', lead('nP50', { v: 0.36, d: 0.2, s: 0.6, vib: false }), 'Super Mario Bros. (NES)');
  add('NES', 'Hero Fanfare', [...lead('nP12', { v: 0.32, c: 18, delay: 0.22 }), { w: 'nP25', v: 0.18, a: 0.01, h: 0.02, d: 0.2, s: 0.9, r: 0.04, t: 0.5 }], 'The Legend of Zelda (NES)');
  add('NES', 'Bounty Hunter Pad', [...swell('nTRI', { v: 0.45, a: 0.3, c: 8 }), { w: 'nP12', v: 0.12, a: 0.4, h: 0.05, d: 0.5, s: 1, r: 0.3, t: 2.003 }], 'Metroid (NES)');
  add('NES', 'Coin Blip', [{ w: 'nP50', v: 0.36, a: 0.002, h: 0.02, d: 0.25, s: 0.4, r: 0.05, t: 1, p: 2 ** (5 / 12), q: 0.03 }], 'Super Mario Bros. coin (NES)');
  add('NES', 'Jump Sweep', sweep('nP25', 0.6, { q: 0.05, s: 0.5 }), 'Super Mario Bros. jump (NES)');
  add('NES', 'Power-Up Arp', arp('nP50', 2, { v: 0.34, rate: 30 }), 'NES power-up jingles');
  add('NES', 'Triangle Kick Bass', [{ w: 'nTRI', v: 0.75, a: 0.002, h: 0.01, d: 0.3, s: 0.8, r: 0.03, t: 2, p: 0.5, q: 0.006 }], 'NES triangle bass lines'); // starts an octave up, snaps to the note
  add('NES', 'Ninja Lead', lead('nP12', { v: 0.4, a: 0.001, d: 0.08, s: 0.85, rate: 6.5, c: 45, delay: 0.3 }), 'Ninja Gaiden (NES)');
  add('NES', 'Echo Pulse', [...lead('nP25', { v: 0.36, vib: false }), { w: 'nP25', v: 0.14, a: 0.12, h: 0.02, d: 0.3, s: 0.6, r: 0.15, t: 1.002 }], 'NES two-channel echo (DuckTales)');
  add('NES', 'Sunsoft Saw Bass', bass('nSAW', { v: 0.6, d: 0.25, s: 0.75, p: 0.97, q: 0.05 }), 'Sunsoft bass (Batman, NES)');
  // Famicom expansion chips (6)
  add('Famicom+', 'VRC6 Saw Lead', lead('nVRS', { v: 0.55, rate: 5.5, c: 22, delay: 0.2 }), 'Konami VRC6 (Akumajou Densetsu)');
  add('Famicom+', 'VRC6 Thin Pulse', lead('nP06', { v: 0.5, c: 18 }), 'Konami VRC6 (Esper Dream 2)');
  add('Famicom+', 'FDS Wavetable Lead', [...lead('nFDS', { v: 0.55, vib: false }), vib(5, 35, 0.12)], 'Famicom Disk System (Zelda no Densetsu)');
  add('Famicom+', 'N163 Brass Wave', lead('nN16', { v: 0.6, a: 0.015, c: 15 }), 'Namco 163 (King of Kings)');
  add('Famicom+', '5B Buzz Square', am('nP50', 'sawtooth', { v: 0.36, mt: 1, mv: 0.12 }), 'Sunsoft 5B (Gimmick!)');
  add('Famicom+', 'MMC5 Pulse Duet', [{ w: 'nP25', v: 0.26, a: 0.003, h: 0.02, d: 0.1, s: 1, r: 0.04 }, { w: 'nP50', v: 0.2, a: 0.003, h: 0.02, d: 0.1, s: 1, r: 0.04, t: 1.004 }], 'Nintendo MMC5 (Just Breed)');
  // Game Boy DMG (8)
  add('Game Boy', 'Pocket Monster Lead', lead('nP25', { v: 0.42, d: 0.15, s: 0.7, c: 15, delay: 0.25 }), 'Pokémon Red/Blue (GB)');
  add('Game Boy', 'Falling Blocks Lead', lead('nP50', { v: 0.36, d: 0.12, s: 0.55, vib: false }), 'Tetris (GB)');
  add('Game Boy', 'Island Wave Lead', lead('nWV1', { v: 0.65, rate: 5, c: 25, delay: 0.3 }), "Link's Awakening (GB)");
  add('Game Boy', 'Wave Bass Pluck', bass('nWV2', { v: 0.7, d: 0.15, s: 0.3 }), 'Game Boy wave-channel bass');
  add('Game Boy', 'Noise Channel Lead', lead('nMTP', { v: 0.38, d: 0.1, s: 0.6, vib: false, t: 0.5 }), 'Game Boy noise-channel melodies');
  add('Game Boy', 'Duty Sweep Lead', pwm('nP12', 'nP25', 6, { v: 0.26, vib: [5.5, 15, 0.25] }), 'Game Boy duty cycling');
  add('Game Boy', 'Puffball Pluck', [...pluck('nP25', { v: 0.45, d: 0.16 }), { w: 'nP12', v: 0.18, a: 0.002, h: 0, d: 0.08, s: 0, r: 0.03, t: 2 }], "Kirby's Dream Land (GB)");
  add('Game Boy', 'Echo Wave Pad', [...swell('nWV1', { v: 0.45, a: 0.2 }), { w: 'nWV1', v: 0.2, a: 0.35, h: 0.05, d: 0.5, s: 1, r: 0.4, t: 1.004 }], 'Game Boy wave-channel pads');
  // Commodore 64 SID (8)
  add('C64 SID', 'PWM Lead', pwm('nP25', 'nP37', 4, { v: 0.28, vib: [6, 20, 0.2] }), 'C64 SID pulse-width leads (Rob Hubbard)');
  add('C64 SID', 'Combined Wave Lead', lead('nSID', { v: 0.55, c: 25 }), 'C64 SID combined waveforms');
  add('C64 SID', 'Ring Mod Bell', am('sine', 'square', { v: 0.26, d: 0.4, s: 0.15, r: 0.2, mt: 2.5, mv: 0.2 }), 'C64 SID ring modulation');
  add('C64 SID', 'Driving Bass', [...bass('nSAW', { v: 0.45, d: 0.12, s: 0.6 }), { w: 'nP50', v: 0.18, a: 0.002, h: 0.01, d: 0.1, s: 0.5, r: 0.03, t: 0.25 }], 'Monty on the Run (C64)');
  add('C64 SID', 'Chord Arp (fast)', arp('nP25', 2 ** (7 / 12), { rate: 50, v: 0.38 }), 'C64 fast chord arpeggios');
  add('C64 SID', 'Saw Brass', lead('nSAW', { v: 0.6, a: 0.05, d: 0.2, s: 0.85, c: 12, delay: 0.3 }), 'C64 SID brass');
  add('C64 SID', 'Hard Sync Lead', [{ w: 'nP50', v: 0.26, a: 0.003, h: 0.02, d: 0.1, s: 1, r: 0.04 }, { w: 'nSAW', v: 0.3, a: 0.003, h: 0.02, d: 0.1, s: 1, r: 0.04, t: 2 }, vib(6, 15, 0.2)], 'C64 SID sync-style leads');
  add('C64 SID', 'Noise Wind', [{ w: 'nNOI', v: 0.3, a: 0.3, h: 0.05, d: 0.5, s: 1, r: 0.4, t: 0.25 }], 'C64 SID noise effects');
  // Atari 2600 TIA (4)
  add('Atari 2600', 'TIA Buzz Lead', lead('nTI5', { v: 0.42, vib: false }), 'Atari 2600 TIA poly5');
  add('Atari 2600', 'TIA Poly Bass', bass('nTI4', { v: 0.45 }), 'Atari 2600 TIA poly4');
  add('Atari 2600', 'TIA Div-31 Drone', swell('nTIB', { v: 0.36, a: 0.1, c: 5 }), 'Atari 2600 TIA div-31');
  add('Atari 2600', 'TIA Laser Shot', sweep('nTI4', 4, { q: 0.08, s: 0.2, v: 0.45 }), 'Atari 2600 shots');
  // AY / PSG arcade and home computers (5)
  add('AY / PSG', 'AY Buzzer Bass', am('nP50', 'sawtooth', { v: 0.36, t: 0.5, mt: 0.5, mv: 0.2 }), 'AY-3-8910 envelope buzzer (ZX Spectrum, MSX)');
  add('AY / PSG', 'MSX Square Lead', lead('nP50', { v: 0.36, rate: 5, c: 12, delay: 0.25 }), 'MSX PSG (Konami)');
  add('AY / PSG', 'PSG Square Pad', swell('nP50', { v: 0.28, a: 0.2 }), 'Sega Master System PSG');
  add('AY / PSG', 'Arcade Siren', siren('nTRI', 3, 4, { v: 0.6 }), 'Arcade siren (Pac-Man)');
  add('AY / PSG', 'Arcade Shot', sweep('nP25', 3, { q: 0.03, s: 0.15 }), 'Arcade shooters (Galaga)');
  // Genesis / Mega Drive YM2612 FM (5)
  add('Genesis FM', 'FM Slap Bass', [{ w: 'sine', v: 0.5, a: 0.002, h: 0.01, d: 0.3, s: 0.5, r: 0.06, t: 0.5 }, { g: 1, w: 'sine', t: 0.5, v: 4, a: 0, h: 0, d: 0.08, s: 0.3, r: 0.05 }], 'Genesis slap bass (Streets of Rage)');
  add('Genesis FM', 'FM Brass Stab', fm('sine', 1, 4, { a: 0.01, d: 0.2, s: 0.5, md: 0.15, ms: 0.4 }), 'Genesis FM brass');
  add('Genesis FM', 'FM Organ', [{ w: 'sine', v: 0.35, a: 0.005, h: 0.02, d: 0.1, s: 1, r: 0.05 }, { g: 1, w: 'sine', t: 2, v: 0.8, a: 0, h: 0, d: 0.1, s: 1, r: 0.05 }, { w: 'sine', v: 0.15, a: 0.005, h: 0.02, d: 0.1, s: 1, r: 0.05, t: 2 }], 'Genesis FM organ');
  add('Genesis FM', 'FM Speed Lead', [...fm('sine', 2, 2, { d: 0.3, s: 0.8, md: 0.2, ms: 0.5 }), vib(6, 20, 0.15)], 'Sonic the Hedgehog (Genesis)');
  add('Genesis FM', 'FM Marimba', fm('sine', 4, 3, { d: 0.25, s: 0, md: 0.05, ms: 0 }), 'Genesis FM mallets');
  // PC Engine / TurboGrafx-16 (2)
  add('PC Engine', 'PCE Wavetable Lead', lead('nPC1', { v: 0.6, c: 20 }), 'PC Engine wavetable (Bonk)');
  add('PC Engine', 'PCE Wavetable Pluck', pluck('nPC2', { v: 0.6, d: 0.15 }), 'PC Engine wavetable');

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

  // Loudness matching: one gain per preset (programs 0–99), applied to the operators you hear (g: 0
  // outputs) and to amplitude modulators (g > 10, whose depth is relative to the output level). FM
  // operators (g 1–10) set timbre and pitch, so they are left alone. Generated by
  // onchain/tinychip-loudness.mjs: K-weighted RMS (the weighting of ITU-R BS.1770 / LUFS) of a 5-note
  // phrase per preset, through tinysynth's own output chain, matched to the pack's median.
  const LOUDNESS = [0.835, 1.21, 0.939, 0.872, 1.084, 0.872, 0.851, 1.273, 0.851, 1.069, 0.845, 0.937, 1.543, 2.088, 1.908, 1.344, 2.135, 1.417, 0.976, 3.116, 0.627, 0.941, 0.876, 1.209, 0.668, 0.701, 1.639, 0.644, 1.191, 1.165, 0.943, 1.577, 1.088, 1.234, 0.964, 0.94, 0.951, 1.182, 1.455, 1.373, 1.172, 0.964, 0.715, 1.273, 1.066, 0.508, 0.656, 0.645, 1.17, 1.6, 0.872, 0.837, 1.053, 1.115, 2.124, 1.09, 1.119, 0.966, 0.649, 1.227, 0.883, 1.062, 0.85, 1.136, 1.057, 1.161, 0.861, 0.909, 1.004, 1.166, 0.715, 1.657, 1.346, 0.969, 1.488, 1.137, 0.701, 1.167, 0.615, 1.393, 0.99, 1.042, 0.995, 1.426, 0.6, 0.676, 0.845, 0.866, 0.809, 0.872, 1.175, 0.745, 1.352, 0.586, 0.659, 0.617, 0.472, 0.811, 1.111, 1.806];

  // tinysynth's operator defaults (its setTimbre fills these; slots above 127 are set directly)
  const DEFAULTS = { g: 0, w: 'sine', t: 1, f: 0, v: 0.5, a: 0, h: 0.01, d: 0.01, s: 0, r: 0.05, p: 1, q: 1, k: 0 };

  function install(synth, { gains = LOUDNESS, programBase = 0, drums = true } = {}) {
    registerWaves(synth);
    for (const pr of P) {
      const k = gains[pr.program] ?? 1;
      const ops = pr.p.map((o) => ((o.g ?? 0) === 0 || o.g > 10 ? { ...DEFAULTS, ...o, v: o.v * k } : { ...DEFAULTS, ...o }));
      const n = programBase + pr.program;
      if (n <= 127) { synth.setTimbre(0, n, ops); synth.program[n].name = pr.name; }
      else synth.program[n] = { name: pr.name, p: ops };
    }
    if (drums) {
      for (const [key, [name, p]] of Object.entries(DRUMS)) {
        synth.setTimbre(1, +key, p.map((o) => ({ ...o })));
        synth.drummap[+key - 35].name = name;
      }
    }
    return synth;
  }

  // ── hook for the onchain TinySynth page player ───────────────────
  // Program slots above General MIDI (the player keeps 128 for its own lead), so a MIDI file's GM
  // instruments are untouched unless it asks for the chip bank.
  const PROGRAM_BASE = 129, LEAD = 0; // TinyChip program 0: Triangle Lead (vibrato)
  const ORCHESTRATION = 'tinychip-1';

  /**
   * Called by the player after it loads the MIDI. `events` are tinysynth song events ({ t, m });
   * `channels` the channels with notes; `bare` whether the score sets no instruments and no drums.
   * Bare scores: every note channel plays the chip lead and the accompaniment uses the chip kit.
   * Other scores: channels that send Bank Select MSB = 1 (0xB0 | ch, 0, 1) play TinyChip presets for
   * their program numbers 0–99; channel 10 with that bank plays the chip kit. Returns a summary,
   * or null (and installs nothing) when the score neither is bare nor asks for the chip bank.
   */
  function attach(synth, { bare, channels, events }) {
    const bank = new Set();
    for (const { m } of events) if ((m[0] & 0xf0) === 0xb0 && m[1] === 0 && m[2] === 1) bank.add(m[0] & 0x0f);
    if (!bare && bank.size === 0) return null;
    const chipDrums = bare || bank.has(9);
    install(synth, { programBase: PROGRAM_BASE, drums: chipDrums });
    if (bare) {
      for (const ch of channels) synth.setProgram(ch, PROGRAM_BASE + LEAD);
    } else {
      for (const ch of bank) if (ch !== 9) synth.setProgram(ch, PROGRAM_BASE);
      // remap this channel's program changes into the chip bank (covers playback and locate)
      for (const e of events) {
        const ch = e.m[0] & 0x0f;
        if ((e.m[0] & 0xf0) === 0xc0 && bank.has(ch) && ch !== 9 && e.m[1] < P.length) e.m = [e.m[0], PROGRAM_BASE + e.m[1]];
      }
    }
    return { orchestration: ORCHESTRATION, presets: P.length, chipChannels: bare ? [...channels] : [...bank].filter((c) => c !== 9), chipDrums };
  }

  root.TinyChip = { install, attach, PROGRAM_BASE, ORCHESTRATION, PRESETS: P, LOUDNESS, DRUMS: Object.fromEntries(Object.entries(DRUMS).map(([k, [n]]) => [k, n])), WAVES: ['nP06', 'nP12', 'nP25', 'nP37', 'nP50', 'nTRI', 'nSAW', 'nVRS', 'nWV1', 'nWV2', 'nFDS', 'nN16', 'nSID', 'nTI4', 'nTI5', 'nTIB', 'nPC1', 'nPC2', 'nMTP', 'nNOI', 'nMET'] };
})(typeof window !== 'undefined' ? window : globalThis);
