// Beast Sound library: stored onchain once, pulled into any page that wants a Beast's music.
//
// Loading this script defines window.BeastSound, a composable API over the deterministic engine
// (engine v1, byte-identical to the Cairo reference, so score hashes and MIDI bytes are checkable):
//
//   const song = BeastSound.compose(tokenId, { adventurers_killed, scars, summit_held_seconds, rank, species_count })
//   song.notes        [[time, duration, pitch, velocity, voice], ...] in ticks (480 per beat)
//   song.scoreHash    '0x…' commitment to the full score
//   BeastSound.midi(song)      Standard MIDI File bytes (Uint8Array)
//   BeastSound.midiUrl(song)   object URL for <a download> or <audio>-style use
//   BeastSound.play(song) / BeastSound.stop() / BeastSound.isPlaying()
//
// Inside a Beast's token_uri animation_url the page also carries one line of inputs written by the
// contract, then the SVG as text in <script type="text/plain" id="art">:
//   <script>BEAST_SOUND="<token_id>,<adventurers_killed>,<scars>,<summit_held_seconds>,<rank>,<species_count>"</script>
// When that line is present the library mounts the page: art, ♪ play and MIDI buttons. No network.
import { poseidonHashMany } from '../src/poseidon_lite.js';
import { createCoreEngine } from '../src/engine.js';
import { chip, chipDrum } from '../../../web/beast_sound/chip.js';
import { createLoopScheduler } from '../server/scheduler.js';

const LEAD = chip('chip_tri_lead', 'Triangle lead (vibrato)', 1.3, { wave: 'tri', env: { sustain: 1, release: 2 }, vib: { rate: 6, cents: 30, delay: 0.2 } });
const engine = createCoreEngine({ poseidonHashMany });

// ── composition ────────────────────────────────────────────────────
function compose(tokenId, live = {}) {
  const id = BigInt(tokenId);
  const beast = engine.decodeTokenId(id);
  const count = Number(live.species_count ?? 1243);
  const l = {
    adventurers_killed: Number(live.adventurers_killed ?? 0),
    scars: Number(live.scars ?? 0),
    summit_held_seconds: Number(live.summit_held_seconds ?? 0),
    species_count: count,
    rank: Number(live.rank ?? (beast.prefix === 0 ? 0 : count)),
  };
  const r = engine.render(beast, l);
  const events = r.form.events;
  const ticks = Math.max(...events.map((e) => e.time + e.duration));
  return {
    tokenId: id, beast, live: l, params: r.params,
    tempo_us: r.params.tempo_us,
    durationSeconds: (ticks / 480) * (r.params.tempo_us / 1e6),
    events,
    notes: events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]),
    scoreHash: '0x' + r.form.score_hash.toString(16),
  };
}

/** Parse the token_uri inputs line: "token,kills,scars,held,rank,count". */
function fromInputs(line) {
  const [tokenId, adventurers_killed, scars, summit_held_seconds, rank, species_count] = String(line).split(',').map((s) => s.trim());
  return compose(tokenId, { adventurers_killed, scars, summit_held_seconds, rank, species_count });
}

const midi = (song) => engine.eventsToMidi(song.events, song.tempo_us);
const midiUrl = (song) => URL.createObjectURL(new Blob([midi(song)], { type: 'audio/midi' }));

// ── playback ───────────────────────────────────────────────────────
let ac = null, out = null, playing = null;
const LOOKAHEAD = (() => { try { return matchMedia('(pointer: coarse)').matches ? 0.6 : 0.35; } catch { return 0.35; } })();
const listeners = new Set();
const notify = () => listeners.forEach((fn) => fn(!!playing));

function unlock() {
  if (!ac) {
    const AC = window.AudioContext || window.webkitAudioContext;
    try { ac = new AC({ latencyHint: 'playback' }); } catch { ac = new AC(); }
  }
  if (ac.state !== 'running') ac.resume().catch(() => {});
  // iOS: a silent buffer inside the gesture unlocks output
  try { const s = ac.createBufferSource(); s.buffer = ac.createBuffer(1, 1, ac.sampleRate); s.connect(ac.destination); s.start(0); } catch { /* not needed */ }
}

/** Play a composed song (call from a user gesture). Loops until stop(). */
function play(song, { drums = true } = {}) {
  if (playing) stop();
  unlock();
  const comp = ac.createDynamicsCompressor(); comp.threshold.value = -18; comp.ratio.value = 3; comp.connect(ac.destination);
  out = ac.createGain(); out.connect(comp);
  const kit = { ac };
  const tick = song.tempo_us / 1e6 / 480;
  const voices = [...new Set(song.notes.map((n) => n[4]))].sort((a, b) => a - b);
  const buses = voices.map((v, i) => {
    const p = ac.createStereoPanner(); p.pan.value = voices.length < 2 ? 0 : -0.85 + (1.7 * i) / (voices.length - 1); p.connect(out); return p;
  });
  const sched = createLoopScheduler(song.notes, {
    tick,
    drums,
    onNote: (n, t) => LEAD.play(kit, buses[voices.indexOf(n[4])], t, n[1] * tick, 440 * 2 ** ((n[2] - 69) / 12), 0.16 * (n[3] / 127) * LEAD.gain),
    onDrum: (d, t) => chipDrum(kit, out, t, d.kind, d.level),
  });
  const p = { started: false };
  const pump = () => {
    if (playing !== p) return;
    if (!p.started) { if (ac.state !== 'running') return; sched.start(ac.currentTime); p.started = true; }
    sched.pump(ac.currentTime + LOOKAHEAD);
  };
  playing = p;
  p.timer = setInterval(pump, 40);
  pump();
  notify();
}

function stop() {
  if (!playing) return;
  clearInterval(playing.timer); playing = null;
  const g = out, now = ac.currentTime;
  g.gain.setValueAtTime(g.gain.value, now); g.gain.linearRampToValueAtTime(0, now + 0.08);
  setTimeout(() => g.disconnect(), 300);
  notify();
}

window.BeastSound = {
  version: 'beast-sound/engine-v1',
  compose, fromInputs, midi, midiUrl, play, stop,
  isPlaying: () => !!playing,
  onPlayingChange: (fn) => { listeners.add(fn); return () => listeners.delete(fn); },
  decodeTokenId: engine.decodeTokenId,
};

// ── token_uri page ─────────────────────────────────────────────────
function button(label, aria, right) {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = label;
  b.setAttribute('aria-label', aria);
  b.style.cssText = `position:fixed;right:${right}px;bottom:12px;min-width:44px;height:44px;padding:0 10px;border-radius:22px;border:1px solid rgba(255,255,255,.35);background:rgba(0,0,0,.55);color:#fff;font:600 15px/1 system-ui,sans-serif;cursor:pointer;z-index:1`;
  document.body.appendChild(b);
  return b;
}

addEventListener('DOMContentLoaded', () => {
  if (window.BEAST_SOUND === undefined) return; // loaded as a library by some other page
  const art = document.getElementById('art');
  if (art) {
    const img = document.createElement('img');
    img.alt = '';
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(art.textContent.trim());
    document.body.insertBefore(img, document.body.firstChild);
  }
  let song = null;
  const ready = () => song || (song = fromInputs(window.BEAST_SOUND), window.BEAST_SCORE_HASH = song.scoreHash, song);
  addEventListener('load', () => setTimeout(ready, 0));

  const playBtn = button('♪', 'Play sound', 12);
  const midiBtn = button('MIDI', 'Download MIDI file', 64);
  window.BeastSound.onPlayingChange((on) => {
    playBtn.textContent = on ? '■' : '♪';
    playBtn.setAttribute('aria-label', on ? 'Stop sound' : 'Play sound');
  });
  midiBtn.addEventListener('click', (e) => {
    e.stopPropagation();
    const a = document.createElement('a');
    a.href = midiUrl(ready());
    a.download = `beast-${ready().tokenId}.mid`;
    document.body.appendChild(a); a.click(); a.remove();
  });
  // Tap anywhere else (art or ♪) toggles; browsers only start audio from a gesture.
  document.addEventListener('click', () => (playing ? stop() : play(ready())));
});
