// Self-contained Beast MIDI for a generic player (onchain-tinysynth plays a file exactly as written:
// every play resets each channel to program 0 and adds nothing). On top of the score itself:
//
//   instruments  a program change on every voice at tick 0, from role pools (the TinyChip
//                orchestration's): the highest voice leads (brighter leads when the tempo is above
//                120 BPM), the lowest is a bass (or keys above E3), voices between are pads when
//                they rest a lot and keys when they move; no preset twice. Programs are TinyChip
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

export const POOLS = {
  lead: [0, 2, 3, 1],       // Triangle Lead, Pulse 25% Lead, Square Lead, Pulse 12.5% Lead
  bright: [50, 51, 53, 4],  // Robot Hero Lead, Vampire Hunter Lead, Hero Fanfare, 4-bit Saw Lead
  bass: [20, 61, 23, 21],   // Triangle Bass, Sunsoft Saw Bass, 4-bit Saw Bass (drop), Pulse Bass
  keys: [12, 15, 18, 38],   // Pulse 25% Pluck, Triangle Pluck, Chip Piano, Pulse Blip
  pad: [28, 33, 54, 34],    // Pulse Swell, Triangle Pad, Bounty Hunter Pad, Octave Arp
};

/** { voice_id: { program, pan } } for a score's note events. `hash`: a u32 from the score. */
export function voiceSetup(events, tempo_us, hash) {
  const st = {};
  for (const e of events) {
    const s = (st[e.voice_id] ||= { sum: 0, n: 0, first: e.time, last: e.time });
    s.sum += e.pitch; s.n += 1;
    if (e.time < s.first) s.first = e.time;
    if (e.time > s.last) s.last = e.time;
  }
  const ids = Object.keys(st).map(Number).sort((a, b) => a - b);
  // by mean pitch, lowest first (cross-multiplied: no fractions); ties by voice id
  const order = [...ids].sort((a, b) => (st[a].sum * st[b].n - st[b].sum * st[a].n) || a - b);
  const used = new Set(), out = {};
  const pick = (pool, k) => {
    for (let i = 0; i < 4; i++) { const id = pool[(k + i) % 4]; if (!used.has(id)) { used.add(id); return id; } }
    return pool[k % 4];
  };
  const h4 = Math.floor(hash / 16), h8 = Math.floor(hash / 256);
  order.forEach((id, i) => {
    const s = st[id];
    let program;
    if (i === order.length - 1) program = pick(tempo_us < 500000 ? POOLS.bright : POOLS.lead, hash % 4);
    else if (i === 0) program = pick(s.sum < 52 * s.n ? POOLS.bass : POOLS.keys, h4 % 4);
    else program = pick(4800 * s.n < 7 * (s.last - s.first + 480) ? POOLS.pad : POOLS.keys, (h8 + i) % 4); // < 0.7 notes per quarter: a pad
    out[id] = { program, pan: 0 };
  });
  // pan: 64 + 64 x (-0.85 .. +0.85) across the voices in voice order, floored
  ids.forEach((id, i) => { out[id].pan = ids.length < 2 ? 64 : Math.floor((960 * (ids.length - 1) + 10880 * i) / (100 * (ids.length - 1))); });
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

/** Drum hits [time, key, velocity] in time order, for a form of `length` ticks in sections of `sec`. */
export function drumEvents(length, sec, tier) {
  const f = FILLS[fillFor(tier)], region = f.beats * 480, out = [];
  const fillKick0 = f.notes.some(([o, k]) => o === 0 && k === 36);
  for (let u = 0; u < length; u += 120) {
    const rel = u % sec, fillStart = sec - region, inFill = rel >= fillStart;
    if (fillFor(tier) === 'D' && rel === 0) out.push([u, 49, 76]);                       // a cymbal on each section's downbeat
    if (inFill) for (const [o, k, v] of f.notes) if (o === rel - fillStart) out.push([u, k, v]);
    if (u % 240 !== 0) continue;
    const bar = Math.floor(rel / 1920), second = bar % 2 === 1, q = rel % 1920; // q: ticks into the bar
    if (q === 0) out.push([u, 36, second ? 104 : 122]);                                   // kick on 1, firmer on a pair's first bar
    if (!inFill && second && q === 1200) out.push([u, 36, 86]);                           // pickup on the and of 3
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

/** A rendered Beast (engine.render) -> self-contained SMF bytes. */
export function beastFullMidi(result, formLength) {
  const f = result.form, p = result.params, length = formLength(f);
  const hash = Number(BigInt(f.score_hash) & 0xffffffffn);
  const setup = voiceSetup(f.events, p.tempo_us, hash);
  const notes = f.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]);
  return fullMidi(notes, p.tempo_us, length, setup, drumEvents(length, f.section_ticks, p.tier));
}
