// Self-contained Beast MIDI for a generic player (onchain-midi-player plays a file exactly as written:
// every play resets each channel to program 0 and adds nothing). On top of the score itself:
//
//   instruments  a program change on every voice at tick 0. What get_midi plays (beastSoundMidi):
//                the instruments by Beast (FAMILIES, beastInstruments); the plain writer's default
//                puts VOICE_PROGRAM (TinyChip's Triangle Lead) on every voice. Programs are TinyChip
//                bank numbers, so sound settings that install those presets as custom timbres in
//                the same slots are selected by the file directly.
//   pan          CC10 at tick 0, voices spread from left to right in voice order
//   drums        channel 10: kick, half-time snare and eighth-note hats phrased in bar pairs, and
//                a fill into every section that grows with the tier (A tier 5 two snares, B tier 4
//                a sixteenth-note snare run, C tier 3 a two-beat build, D tiers 1-2 a tom roll into
//                a cymbal on the next downbeat). Note-ons only: drum hits are one-shots.
//
// Every value is integer arithmetic so the Cairo writer (beast_v3_sound.cairo) can match it byte
// for byte. The tempo track's End-of-Track and the drum track's sit at the form's length.

/** The program every voice plays: TinyChip's Triangle Lead (bank 0) for now, until the preset set and its orchestration are chosen. */
export const VOICE_PROGRAM = 0;

/** { voice_id: { program, pan } } for a score's note events: every voice on VOICE_PROGRAM, panned left to right in voice order. */
export function voiceSetup(events) {
  const ids = [...new Set(events.map((e) => e.voice_id))].sort((a, b) => a - b), out = {};
  // pan: 64 + 64 x (-0.85 .. +0.85) across the voices in voice order, floored
  ids.forEach((id, i) => { out[id] = { program: VOICE_PROGRAM, pan: ids.length < 2 ? 64 : Math.floor((960 * (ids.length - 1) + 10880 * i) / (100 * (ids.length - 1))) }; });
  return out;
}

// fills, relative to the start of their region: [offset, key, velocity]
const FILLS = {
  A: { beats: 1, notes: [[0, 38, 88], [240, 38, 106]] },
  B: { beats: 1, notes: [[0, 38, 72], [120, 38, 84], [240, 38, 96], [360, 38, 108]] },
  C: { beats: 2, notes: [[0, 36, 100], [0, 38, 80], [240, 38, 88], [480, 38, 92], [600, 38, 100], [720, 38, 108], [840, 38, 116]] },
  D: { beats: 2, notes: [[0, 50, 84], [120, 50, 88], [240, 48, 92], [360, 48, 96], [480, 47, 100], [600, 45, 104], [720, 43, 108], [840, 41, 112], [840, 36, 110]] },
};
export const fillFor = (tier) => (tier >= 5 ? 'A' : tier === 4 ? 'B' : tier === 3 ? 'C' : 'D');

/**
 * Drum hits [time, key, velocity] in time order, for a form of `length` ticks in sections of `sec`.
 * `mega`: the mega groove (sixteenth-note hats, a kick on the and of 2 in a pair's first bar, a
 * crash on every section's downbeat); the tier fills stay.
 */
export function drumEvents(length, sec, tier, mega = false) {
  const f = FILLS[fillFor(tier)], region = f.beats * 480, out = [];
  const fillKick0 = f.notes.some(([o, k]) => o === 0 && k === 36);
  for (let u = 0; u < length; u += 120) {
    const rel = u % sec, fillStart = sec - region, inFill = rel >= fillStart;
    if (rel === 0 && (mega || fillFor(tier) === 'D')) out.push([u, 49, mega ? 96 : 76]);    // a cymbal on each section's downbeat
    if (inFill) for (const [o, k, v] of f.notes) if (o === rel - fillStart) out.push([u, k, v]);
    if (mega && u % 240 !== 0) { out.push([u, 42, inFill ? 32 : 44]); continue; }          // mega: sixteenth-note hats
    if (u % 240 !== 0) continue;
    const bar = Math.floor(rel / 1920), second = bar % 2 === 1, q = rel % 1920; // q: ticks into the bar
    if (q === 0) out.push([u, 36, second ? 104 : 122]);                                   // kick on 1, firmer on a pair's first bar
    if (!inFill && second && q === 1200) out.push([u, 36, 86]);                           // pickup on the and of 3
    if (mega && !inFill && !second && q === 720) out.push([u, 36, 92]);                   // mega: the and of 2
    if (inFill && q === 960 && !(fillKick0 && rel === fillStart)) out.push([u, 36, 100]); // beat 3 under a two-beat fill
    if (!inFill && q === 960) out.push([u, 38, second ? 88 : 94]);                        // snare on 3
    const open = !inFill && second && q === 1680;
    let hv = q === 0 ? 80 : u % 480 === 0 ? 70 : 52;
    if (inFill) hv -= 12;
    out.push(open ? [u, 46, 64] : [u, 42, hv]);                                           // hats; an open hat closes each pair
  }
  return out;
}

const vlq = (n) => { const b = [n & 0x7f]; while ((n >>= 7)) b.unshift((n & 0x7f) | 0x80); return b; };
const chunk = (type, data) => [...type].map((c) => c.charCodeAt(0)).concat([(data.length >>> 24) & 255, (data.length >>> 16) & 255, (data.length >>> 8) & 255, data.length & 255], data);

/**
 * notes [[time, duration, pitch, velocity, voice], ...], tempo_us, endTick (form length),
 * setup { voice: { program, pan } }, drums [[time, key, velocity], ...] -> SMF bytes (format 1).
 */
export function fullMidi(notes, tempo_us, endTick, setup, drums) {
  const tracks = [[0, 0xff, 0x51, 0x03, (tempo_us >> 16) & 255, (tempo_us >> 8) & 255, tempo_us & 255, ...vlq(endTick), 0xff, 0x2f, 0x00]];
  const voices = [...new Set(notes.map((n) => n[4]))].sort((a, b) => a - b);
  for (const v of voices) {
    const ch = v & 15, data = [0, 0xc0 | ch, setup[v].program, 0, 0xb0 | ch, 10, setup[v].pan];
    if (setup[v].vol !== undefined) data.push(0, 0xb0 | ch, 7, setup[v].vol); // channel volume (lab mixes only)
    const msgs = [];
    for (const [time, duration, pitch, velocity] of notes.filter((n) => n[4] === v)) {
      msgs.push([time, 0x90 | ch, pitch, velocity]);
      msgs.push([time + duration, 0x80 | ch, pitch, 64]);
    }
    msgs.sort((a, b) => a[0] - b[0] || (a[1] & 0xf0) - (b[1] & 0xf0));
    let t = 0;
    for (const m of msgs) { data.push(...vlq(m[0] - t), m[1], m[2], m[3]); t = m[0]; }
    data.push(0, 0xff, 0x2f, 0x00);
    tracks.push(data);
  }
  if (drums.length) {
    // one status byte, then running status: delta, key, velocity
    const data = []; let t = 0;
    drums.forEach(([time, key, vel], i) => { data.push(...vlq(time - t)); if (i === 0) data.push(0x99); data.push(key, vel); t = time; });
    data.push(...vlq(Math.max(0, endTick - t)), 0xff, 0x2f, 0x00);
    tracks.push(data);
  }
  const header = chunk('MThd', [0, 1, 0, tracks.length, 0x01, 0xe0]);
  return new Uint8Array(header.concat(...tracks.map((d) => chunk('MTrk', d))));
}

/**
 * Instruments by Beast: the Beast's type picks a family of three leads and three
 * plucks, each family one wave character (Magic round: triangle and soft pulse; Hunter sharp: narrow
 * pulses; Brute heavy: square and saw), the 18 non-mega presets used once each. Plucks list the
 * family's fullest first (the bass role the set has no preset for).
 */
export const FAMILIES = [
  { name: 'Magic', leads: [0, 9, 7], plucks: [15, 17, 13] },
  { name: 'Hunter', leads: [2, 1, 8], plucks: [12, 19, 6] },
  { name: 'Brute', leads: [3, 4, 5], plucks: [16, 14, 18] },
];

/**
 * { voice_id: program } by musical role: the theme voice (0) leads with the family lead the species
 * picks; the canon followers take the plucks, the lowest of them the fullest pluck and the others
 * rotated by the name; the countersubject (voice id = voice_count) takes another of the family's leads.
 */
export function beastInstruments(result) {
  const p = result.params, fam = FAMILIES[result.beast.beast_type] ?? FAMILIES[0];
  const events = result.form.events, species = Number(p.species_id), name = Number(p.name_variant_id);
  const st = {};
  for (const e of events) { const s = (st[e.voice_id] ||= { sum: 0, n: 0 }); s.sum += e.pitch; s.n += 1; }
  const lead = species % 3, out = { 0: fam.leads[lead] };
  const cs = p.use_countersubject ? p.voice_count : -1;
  if (st[cs]) out[cs] = fam.leads[(lead + 1 + (name % 2)) % 3];
  const followers = Object.keys(st).map(Number).filter((v) => v !== 0 && v !== cs)
    .sort((a, b) => (st[a].sum * st[b].n - st[b].sum * st[a].n) || a - b); // lowest first
  const others = name % 2 ? [fam.plucks[2], fam.plucks[1]] : [fam.plucks[1], fam.plucks[2]];
  followers.forEach((v, i) => { out[v] = i === 0 ? fam.plucks[0] : others[i - 1]; });
  return out;
}

/** The mega lead presets: Robot Hero Lead (50) and N163 Brass Wave (65), reserved for mega Beasts. */
export const MEGA_LEADS = [50, 65];

/** Which of MEGA_LEADS a mega Beast's lead plays (the double plays the other): fixed by its species and name. */
export const megaLeadPick = (p) => (Number(p.species_id) + Number(p.name_variant_id)) % 2;

/**
 * Mega (the shiny flag) arrangement options, all off by default (the output is then unchanged):
 *   lead    the lead voice plays one of MEGA_LEADS (picked by the score hash); with double, the
 *           octave copy plays the other
 *   double  the lead doubled an octave up on its own channel (panned opposite), three quarters as loud
 *   groove  the mega drum groove (drumEvents)
 */
export const MEGA_ALL = { lead: true, double: true, groove: true };

/**
 * What BeastMidiProvider.get_midi plays for a rendered Beast: the self-contained MIDI with the
 * instruments by Beast (beastInstruments), and the mega arrangement (MEGA_ALL) when the Beast is mega
 * (its shiny flag). Byte-identical to Cairo's
 * v11_score_full_smf_bytes for a composer v1.1 render.
 */
export const beastSoundMidi = (result, formLength) => beastFullMidi(result, formLength, result.beast.shiny ? MEGA_ALL : {}, { instruments: 'beast' });

/**
 * A rendered Beast (engine.render or engine_v11's render) -> self-contained SMF bytes.
 * `instruments`: 'placeholder' (VOICE_PROGRAM on every voice) or 'beast' (beastInstruments).
 */
export function beastFullMidi(result, formLength, mega = {}, { instruments = 'placeholder', programs = null, drums = null, mix = null, topLead = false, notLead = [] } = {}) {
  const f = result.form, p = result.params, length = formLength(f);
  const setup = voiceSetup(f.events);
  if (instruments === 'beast') for (const [v, program] of Object.entries(beastInstruments(result))) if (setup[v]) setup[v].program = program;
  // prototypes (src/lab.js): per-voice program overrides, and a drum generator in place of the
  // groove ((length, sec, tier, mega) -> hits) or false for no drums
  if (programs) for (const [v, program] of Object.entries(programs)) if (setup[v]) setup[v].program = program;
  const notes = f.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]);
  const sec = f.section_ticks;
  // the lead: the voice with the highest mean pitch, ties by the higher voice id
  const st = {};
  for (const [, , pitch, , v] of notes) { const s = (st[v] ||= { sum: 0, n: 0 }); s.sum += pitch; s.n += 1; }
  // notLead (lab specials): voices never taken for the lead, e.g. the Yeti's avalanche run above the melody
  const voiceMean = Object.fromEntries(Object.entries(st).map(([v, x]) => [v, x.sum / x.n]));
  const ids = Object.keys(st).map(Number).filter((v) => !notLead.includes(v));
  const lead = ids.reduce((a, b) => (st[b].sum * st[a].n > st[a].sum * st[b].n || (st[b].sum * st[a].n === st[a].sum * st[b].n && b > a) ? b : a));
  // topLead (a lab prototype, off by default so get_midi is unchanged): the topline never plays a pluck;
  // when the highest voice drew one, it takes the family's lead no other voice plays
  if (topLead && instruments === 'beast' && setup[lead]) {
    const fam = FAMILIES[result.beast.beast_type] ?? FAMILIES[0];
    if (fam.plucks.includes(setup[lead].program)) {
      const used = new Set(Object.values(setup).map((x) => x.program));
      setup[lead].program = fam.leads.find((l) => !used.has(l)) ?? fam.leads[(Number(p.species_id) + 1) % 3];
    }
  }
  const pickLead = megaLeadPick(p);
  if (mega.lead) setup[lead].program = MEGA_LEADS[pickLead];
  let doubleCh = -1;
  if (mega.double) {
    const ch = Math.max(...Object.keys(st).map(Number)) + 1; // past every voice, a skipped one included
    doubleCh = ch;
    setup[ch] = { program: mega.lead ? MEGA_LEADS[1 - pickLead] : setup[lead].program, pan: 128 - setup[lead].pan > 127 ? 127 : 128 - setup[lead].pan };
    for (const [t, d, pitch, vel, v] of notes.slice()) {
      if (v === lead && pitch + 12 <= 127) notes.push([t, d, pitch + 12, Math.max(1, Math.floor(vel * 3 / 4)), ch]);
    }
  }
  // mix 'balanced' (a lab prototype, off by default so get_midi is unchanged): the leads (theme,
  // countersubject, mega double) at channel volume 64 and the plucks at 127, about 12 dB closer, and
  // the panning halved, so a sparse channel set keeps every voice audible
  if (mix === 'balanced') {
    const cs = p.use_countersubject ? p.voice_count : -1;
    const fam = FAMILIES[result.beast.beast_type] ?? FAMILIES[0];
    for (const [v, st] of Object.entries(setup)) { const lead = +v === 0 || +v === cs || +v === doubleCh || fam.leads.includes(st.program) || MEGA_LEADS.includes(st.program); st.vol = lead ? 64 : 127; st.pan = Math.round(64 + (st.pan - 64) / 2); }
    // Pulse 25% Pluck (12), 4-bit Saw Pluck (16) and Muted Pluck (19) read too loud above the bass: full level while the
    // voice's average pitch is at or below MIDI 52 (E3), easing down to -7 dB by MIDI 64 (E4) and above
    // (channel volume is squared, so dB = 40 log10(vol / 127))
    for (const [v, x] of Object.entries(setup)) if ((x.program === 12 || x.program === 16 || x.program === 19) && voiceMean[v] !== undefined) {
      const k = Math.min(1, Math.max(0, (voiceMean[v] - 52) / 12));
      x.vol = Math.round(x.vol * Math.pow(10, (-7 * k) / 40));
    }
  }
  const hits = drums === false ? [] : (drums || drumEvents)(length, sec, p.tier, !!mega.groove);
  return fullMidi(notes, p.tempo_us, length, setup, hits);
}
