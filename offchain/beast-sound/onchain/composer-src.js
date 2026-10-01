// Beast Sound composer for `token_uri`: stored onchain once, embedded in every Beast's animation_url.
//
// The page is [this script][one line of inputs][the Beast's animated SVG]. token_uri writes the inputs:
//   <script>BEAST_SOUND="<token_id>,<adventurers_killed>,<scars>,<summit_held_seconds>,<rank>,<species_count>"</script>
// (all decimal), then the SVG as text in <script type="text/plain" id="art">. The SVG uses XML-only
// syntax, so it is shown through an <img> rather than inlined. Both come after this script, so it
// waits for the document. It composes the Beast's theme with engine v1 (byte-identical to the Cairo
// reference, so the score hash is checkable) and plays it with the chip synth on tap. No network.
import { poseidonHashMany } from '@scure/starknet';
import { createEngine } from '../src/engine.js';
import { chip, chipDrum } from '../../../web/beast_sound/chip.js';
import { createLoopScheduler } from '../server/scheduler.js';

const LEAD = chip('chip_tri_lead', 'Triangle lead (vibrato)', 1.3, { wave: 'tri', env: { sustain: 1, release: 2 }, vib: { rate: 6, cents: 30, delay: 0.2 } });
const engine = createEngine({ poseidonHashMany });

function compose(input) {
  const [tokenId, kills, scars, held, rank, count] = String(input).split(',').map((s) => BigInt(s.trim()));
  const beast = engine.decodeTokenId(tokenId);
  const live = { adventurers_killed: Number(kills), scars: Number(scars), summit_held_seconds: Number(held), rank: Number(rank), species_count: Number(count) };
  const r = engine.render(beast, live);
  return { tempo_us: r.params.tempo_us, scoreHash: r.form.score_hash, notes: r.form.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice_id]) };
}

let song = null;
const ready = () => {
  if (!song) { song = compose(window.BEAST_SOUND); window.BEAST_SCORE_HASH = '0x' + song.scoreHash.toString(16); }
  return song;
};
addEventListener('DOMContentLoaded', () => {
  const art = document.getElementById('art');
  if (art) {
    const img = document.createElement('img');
    img.alt = '';
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(art.textContent.trim());
    document.body.insertBefore(img, document.body.firstChild);
  }
});
addEventListener('load', () => setTimeout(ready, 0));

let ac = null, out = null, playing = null;
const LOOKAHEAD = (() => { try { return matchMedia('(pointer: coarse)').matches ? 0.6 : 0.35; } catch { return 0.35; } })();

function unlock() {
  if (!ac) {
    const AC = window.AudioContext || window.webkitAudioContext;
    try { ac = new AC({ latencyHint: 'playback' }); } catch { ac = new AC(); }
  }
  if (ac.state !== 'running') ac.resume().catch(() => {});
  // iOS: a silent buffer inside the gesture unlocks output
  try { const s = ac.createBufferSource(); s.buffer = ac.createBuffer(1, 1, ac.sampleRate); s.connect(ac.destination); s.start(0); } catch { /* not needed */ }
}

function play() {
  unlock();
  const song = ready();
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
    drums: true,
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
  button.textContent = '■';
  button.setAttribute('aria-label', 'Stop sound');
}

function stop() {
  clearInterval(playing.timer); playing = null;
  const g = out, now = ac.currentTime;
  g.gain.setValueAtTime(g.gain.value, now); g.gain.linearRampToValueAtTime(0, now + 0.08);
  setTimeout(() => g.disconnect(), 300);
  button.textContent = '♪';
  button.setAttribute('aria-label', 'Play sound');
}

const button = document.createElement('button');
button.type = 'button';
button.textContent = '♪';
button.setAttribute('aria-label', 'Play sound');
button.style.cssText = 'position:fixed;right:12px;bottom:12px;width:44px;height:44px;border-radius:50%;border:1px solid rgba(255,255,255,.35);background:rgba(0,0,0,.55);color:#fff;font:20px/1 system-ui,sans-serif;cursor:pointer;z-index:1';
document.body.appendChild(button);
// Tap anywhere (art or button) toggles; browsers only start audio from a gesture.
document.addEventListener('click', () => (playing ? stop() : play()));
