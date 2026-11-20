// Cue extraction: the structure of a Beast song, as a list of timed cues an animation can follow.
//
// The composer already knows the structure while it writes the notes: every event it returns carries
// its section and its role ('canon' = the theme in that voice, 'countersubject', 'episode',
// 'cadence', 'drone', ...). songCues() reads that from the render result that the engine returns
// next to the MIDI (genesisMidi(...).result, labMidi(...).result, engine.render(...)), and takes the
// per-voice velocities from the MIDI itself, so the cues describe exactly what is heard. Nothing here
// touches the composer or the MIDI writer: the default MIDI is the same bytes with or without cues.
// A track whose events carry no roles (an authored song, a Sound Check) falls back to cuesFromMidi(),
// which guesses the structure from the notes alone (source: 'midi').
//
//   songCues(result, midi)        -> { source, ppq, bar, length, tempo_us, sections, voices, cues, notes }
//   cuesFromMidi(midi, opts)      -> the same shape, from the MIDI alone
//   cueTrack(cues, opts)          -> one MTrk chunk of FF 06 markers (Uint8Array)
//   withCueTrack(midi, cues, opts)-> a NEW file: the MIDI plus that track (ntrks + 1). Optional and
//                                    separate; the default MIDI never includes it.
//
// Cue types (tick = MIDI ticks, 480 per quarter note):
//   section  { index, degree, label, development }  a section starts (and its key area / degree)
//   bar      { n }                                   a downbeat (4/4)
//   entry    { voice, section, role }                the theme ('subject') or countersubject enters
//   episode  { voice, section }                      the first voice leaves the theme for the episode
//   cadence  { section, final }                      the half cadence that closes a section; final =
//                                                    the last section's, which leads back to the loop
//   climax   { bar, voice, pitch, velocity }         the most intense bar's peak note
export const PPQ = 480, BAR = 4 * PPQ, DRUM_CH = 9;
const ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII'];
const PC = ['C', 'C#', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];

/** Note-ons [tick, channel, velocity, pitch, duration] in time order, from MIDI bytes, with the tempo and
 *  the file's length (its last End of Track). Drum hits with no note-off get a sixteenth. */
export function midiNotes(midi) {
  const b = new Uint8Array(midi), notes = [];
  if (String.fromCharCode(b[0], b[1], b[2], b[3]) !== 'MThd') throw new Error('midiNotes: not a MIDI file');
  const ntrks = (b[10] << 8) | b[11], division = (b[12] << 8) | b[13], scale = PPQ / division;
  let p = 8 + (((b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7]) >>> 0), tempo_us = 500000, length = 0;
  for (let k = 0; k < ntrks && p < b.length; k++) {
    const len = ((b[p + 4] << 24) | (b[p + 5] << 16) | (b[p + 6] << 8) | b[p + 7]) >>> 0, end = p + 8 + len, open = new Map();
    let q = p + 8, t = 0, status = 0;
    const rd = () => { let v = 0, c; do { c = b[q++]; v = (v << 7) | (c & 0x7f); } while (c & 0x80); return v; };
    while (q < end) {
      t += rd();
      let s = b[q];
      if (s & 0x80) q++; else s = status;
      if (s === 0xff) {
        const type = b[q++], n = rd();
        if (type === 0x51 && n === 3) tempo_us = (b[q] << 16) | (b[q + 1] << 8) | b[q + 2];
        q += n;
        if (type === 0x2f) { length = Math.max(length, t); break; }
        continue;
      }
      if (s === 0xf0 || s === 0xf7) { q += rd(); continue; }
      status = s;
      const kind = s & 0xf0, ch = s & 15;
      if (kind === 0xc0 || kind === 0xd0) { q += 1; continue; }
      const key = b[q++], vel = b[q++];
      if (kind === 0x90 && vel > 0) {
        const n = [Math.round(t * scale), ch, vel, key, 120];
        notes.push(n);
        (open.get(ch * 128 + key) || open.set(ch * 128 + key, []).get(ch * 128 + key)).push(n);
      } else if (kind === 0x80 || kind === 0x90) {
        const n = (open.get(ch * 128 + key) || []).shift();
        if (n) n[4] = Math.max(1, Math.round(t * scale) - n[0]);
      }
    }
    p = end;
  }
  notes.sort((x, y) => x[0] - y[0] || x[1] - y[1] || x[3] - y[3]);
  return { notes, tempo_us, length: Math.round(length * scale) || Math.max(0, ...notes.map((n) => n[0] + n[4])) };
}

// The bar whose notes hit hardest: the sum of its pitched velocities (drums left out: their fills mark
// every section end, which the cadence cues already show), ties to the higher top note, then the later
// bar. Its peak note (loudest, then highest) is the climax.
function climaxOf(notes, length, avoid = () => false) {
  const bars = Math.max(1, Math.ceil(length / BAR)), score = new Array(bars).fill(0), top = new Array(bars).fill(0);
  for (const [t, ch, v, k] of notes) {
    const b = Math.floor(t / BAR);
    if (b >= bars || ch === DRUM_CH) continue;
    score[b] += v;
    top[b] = Math.max(top[b], k);
  }
  let best = -1;
  for (let b = 0; b < bars; b++) {
    if (avoid(b * BAR)) continue;
    if (best < 0 || score[b] > score[best] || (score[b] === score[best] && top[b] >= top[best])) best = b;
  }
  if (best < 0) best = 0;
  let peak = null;
  for (const n of notes) {
    if (n[1] === DRUM_CH || Math.floor(n[0] / BAR) !== best) continue;
    if (!peak || n[2] > peak[2] || (n[2] === peak[2] && n[3] > peak[3])) peak = n;
  }
  const at = peak || [best * BAR, -1, 0, 0];
  return { tick: at[0], type: 'climax', bar: best + 1, voice: at[1], pitch: at[3], velocity: at[2], score: score[best] };
}

function barCues(length) {
  const out = [];
  for (let t = 0, n = 1; t < length; t += BAR, n++) out.push({ tick: t, type: 'bar', n });
  return out;
}

const order = { section: 0, bar: 1, cadence: 2, episode: 3, entry: 4, climax: 5 };
const sortCues = (cues) => cues.sort((a, b) => a.tick - b.tick || order[a.type] - order[b.type] || (a.voice ?? 0) - (b.voice ?? 0));

/** Voice names by MIDI channel, from the roles the composer gave each voice. */
function voiceNames(events, channels, params) {
  const roles = {};
  for (const e of events) (roles[e.voice_id] ||= new Set()).add(e.role);
  const cs = params && params.use_countersubject ? params.voice_count : -1;
  return channels.map((ch) => {
    const r = roles[ch];
    let name = ch === DRUM_CH ? 'drums' : !r ? 'double' : ch === 0 ? 'theme' : r.has('countersubject') || ch === cs ? 'countersubject'
      : r.has('avalanche') ? 'avalanche' : r.has('drone') ? 'drone' : r.has('canon') ? `voice ${ch + 1}` : `ch ${ch + 1}`;
    return { ch, name };
  });
}

/**
 * Cues for a render result (its form's events carry section and role) and the MIDI it became.
 * `result`: { form: { events, section_ticks, sections }, params, v11? }; `midi`: the bytes played.
 */
export function songCues(result, midi) {
  const form = result && result.form;
  const events = (form && form.events) || [];
  if (!events.some((e) => e.role)) return cuesFromMidi(midi, { sectionTicks: form && form.section_ticks });
  const { notes, tempo_us, length } = midiNotes(midi);
  const sec = form.section_ticks, count = Math.max(1, Math.round(length / sec));
  const plan = (result.v11 && result.v11.keyPlan) || null, diatonic = result.v11 && result.v11.keys === 'mode';
  const dev = result.v11 && result.v11.trajectory && result.v11.trajectory.development;
  const tonic = result.params && result.params.tonic_keynum;
  const sections = [], cues = barCues(length);
  for (let s = 0; s < count; s++) {
    const step = plan ? plan[s % plan.length] : null;
    // diatonic plan: the theme starts on a scale degree of the home key; modulating plan: a new tonic
    const degree = step ? (diatonic ? ROMAN[((step.degrees % 7) + 7) % 7] : PC[(((tonic ?? 0) + step.shift) % 12 + 12) % 12]) : ROMAN[0];
    const label = s === 0 ? 'theme' : dev ? dev : 'development';
    sections.push({ index: s, start: s * sec, end: (s + 1) * sec, degree, label });
    cues.push({ tick: s * sec, type: 'section', index: s, degree, label: `${s + 1} ${degree}${s ? ' · ' + label : ''}` });
  }
  // first event of each role per (voice, section)
  const first = new Map();
  for (const e of events) {
    const k = `${e.role}:${e.voice_id}:${e.section}`, f = first.get(k);
    if (!f || e.time < f.time) first.set(k, e);
  }
  const episodeBySection = new Map(), cadenceBySection = new Map();
  for (const e of first.values()) {
    if (e.role === 'canon' || e.role === 'countersubject') cues.push({ tick: e.time, type: 'entry', voice: e.voice_id, section: e.section, role: e.role === 'canon' ? 'subject' : 'countersubject' });
    if (e.role === 'episode' && (!episodeBySection.has(e.section) || e.time < episodeBySection.get(e.section).tick)) episodeBySection.set(e.section, { tick: e.time, type: 'episode', voice: e.voice_id, section: e.section });
    if (e.role === 'cadence' && (!cadenceBySection.has(e.section) || e.time < cadenceBySection.get(e.section))) cadenceBySection.set(e.section, e.time);
  }
  cues.push(...episodeBySection.values());
  const last = Math.max(...cadenceBySection.keys());
  for (const [s, tick] of cadenceBySection) cues.push({ tick, type: 'cadence', section: s, final: s === last });
  const finalAt = cadenceBySection.get(last) ?? length;
  cues.push(climaxOf(notes, length, (t) => t + BAR > finalAt));
  const channels = [...new Set(notes.map((n) => n[1]))].sort((a, b) => a - b);
  return { source: 'engine', ppq: PPQ, bar: BAR, length, tempo_us, sections, voices: voiceNames(events, channels, result.params), cues: sortCues(cues), notes };
}

/**
 * Structure guessed from the MIDI alone, for tracks whose composer output carries no roles.
 * Sections every `sectionTicks` (or every 8 bars); an entry when a channel starts after a bar or more
 * of silence; the final cadence at the downbeat of the bar holding the top voice's last note.
 */
export function cuesFromMidi(midi, { sectionTicks = 0 } = {}) {
  const { notes, tempo_us, length } = midiNotes(midi);
  const sec = sectionTicks && sectionTicks < length ? sectionTicks : 8 * BAR;
  const sections = [], cues = barCues(length);
  for (let s = 0, t = 0; t < length; s++, t += sec) {
    sections.push({ index: s, start: t, end: Math.min(length, t + sec), degree: '', label: s ? 'phrase' : 'opening' });
    cues.push({ tick: t, type: 'section', index: s, degree: '', label: `${s + 1}` });
  }
  const lastEnd = {};
  for (const [t, ch, , , d] of notes) {
    if (ch === DRUM_CH) continue;
    if (lastEnd[ch] === undefined || t - lastEnd[ch] >= BAR) cues.push({ tick: t, type: 'entry', voice: ch, section: Math.floor(t / sec), role: 'subject' });
    lastEnd[ch] = Math.max(lastEnd[ch] ?? 0, t + d);
  }
  const pitched = notes.filter((n) => n[1] !== DRUM_CH);
  const mean = {};
  for (const [, ch, , k] of pitched) { const m = (mean[ch] ||= { s: 0, n: 0 }); m.s += k; m.n++; }
  const topCh = Object.keys(mean).map(Number).reduce((a, b) => (mean[b].s / mean[b].n > mean[a].s / mean[a].n ? b : a), pitched[0] ? pitched[0][1] : 0);
  const lastTop = pitched.filter((n) => n[1] === topCh).at(-1);
  const finalAt = lastTop ? Math.floor(lastTop[0] / BAR) * BAR : Math.max(0, length - BAR);
  cues.push({ tick: finalAt, type: 'cadence', section: sections.length - 1, final: true });
  cues.push(climaxOf(notes, length, (t) => t + BAR > finalAt));
  const channels = [...new Set(notes.map((n) => n[1]))].sort((a, b) => a - b);
  return { source: 'midi', ppq: PPQ, bar: BAR, length, tempo_us, sections, voices: channels.map((ch) => ({ ch, name: ch === DRUM_CH ? 'drums' : `ch ${ch + 1}` })), cues: sortCues(cues), notes };
}

// ── an onchain cue track: FF 06 markers ─────────────────────────────────────────────────────────
/** A cue's marker text: short, so the track stays small (S2:V = section 2 on degree V, T1 = the theme
 *  enters in voice 1, CS4 = countersubject in voice 4, EP, CAD / FINAL, PEAK, B9 = bar 9). */
export function markerText(c) {
  if (c.type === 'section') return `S${c.index + 1}${c.degree ? ':' + c.degree : ''}`;
  if (c.type === 'entry') return (c.role === 'countersubject' ? 'CS' : 'T') + c.voice;
  if (c.type === 'episode') return 'EP';
  if (c.type === 'cadence') return c.final ? 'FINAL' : 'CAD';
  if (c.type === 'climax') return 'PEAK';
  if (c.type === 'bar') return 'B' + c.n;
  return c.type;
}

const vlq = (n) => { const b = [n & 0x7f]; while ((n >>= 7)) b.unshift((n & 0x7f) | 0x80); return b; };

/** One MTrk of FF 06 marker events, one per cue (bars only when `bars`), ending at the last marker. */
export function cueTrack(cues, { bars = false } = {}) {
  const data = [];
  let t = 0;
  for (const c of cues) {
    if (c.type === 'bar' && !bars) continue;
    const text = [...markerText(c)].map((ch) => ch.charCodeAt(0) & 0x7f);
    data.push(...vlq(c.tick - t), 0xff, 0x06, ...vlq(text.length), ...text);
    t = c.tick;
  }
  data.push(0, 0xff, 0x2f, 0x00);
  const n = data.length;
  return new Uint8Array([0x4d, 0x54, 0x72, 0x6b, (n >>> 24) & 255, (n >>> 16) & 255, (n >>> 8) & 255, n & 255, ...data]);
}

/** A new file: `midi` with the cue track appended as its last track (header track count + 1). */
export function withCueTrack(midi, cues, opts) {
  const src = new Uint8Array(midi), track = cueTrack(cues, opts);
  if (String.fromCharCode(...src.subarray(0, 4)) !== 'MThd' || src[9] !== 1) throw new Error('withCueTrack: expects a type 1 MIDI file');
  const out = new Uint8Array(src.length + track.length);
  out.set(src);
  out.set(track, src.length);
  const ntrks = ((src[10] << 8) | src[11]) + 1;
  out[10] = ntrks >> 8; out[11] = ntrks & 255;
  return out;
}

/** The markers back out of a MIDI file: [{ tick, text }] (any track), e.g. to check a cue track. */
export function readMarkers(midi) {
  const b = new Uint8Array(midi), out = [];
  let p = 14;
  const ntrks = (b[10] << 8) | b[11];
  for (let k = 0; k < ntrks; k++) {
    const len = ((b[p + 4] << 24) | (b[p + 5] << 16) | (b[p + 6] << 8) | b[p + 7]) >>> 0, end = p + 8 + len;
    let q = p + 8, t = 0, status = 0;
    const rd = () => { let v = 0, c; do { c = b[q++]; v = (v << 7) | (c & 0x7f); } while (c & 0x80); return v; };
    while (q < end) {
      t += rd();
      let s = b[q];
      if (s & 0x80) q++; else s = status;
      if (s === 0xff) { const type = b[q++], n = rd(); if (type === 0x06) out.push({ tick: t, text: String.fromCharCode(...b.subarray(q, q + n)) }); q += n; if (type === 0x2f) break; continue; }
      if (s === 0xf0 || s === 0xf7) { q += rd(); continue; }
      status = s;
      q += (s & 0xf0) === 0xc0 || (s & 0xf0) === 0xd0 ? 1 : 2;
    }
    p = end;
  }
  return out.sort((x, y) => x.tick - y.tick);
}
