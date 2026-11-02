// Optional onchain page. MIDI selects the sample programs; unmapped programs use TinySynth.
import { decodeMidi, loopEndTicks } from '../player-core.js';
let synth, playing = false, midi;
const button = document.createElement('button');
button.textContent = 'Play';
button.style.cssText = 'position:fixed;bottom:16px;right:16px;padding:12px 24px;z-index:1';
document.body.append(button);
addEventListener('DOMContentLoaded', () => {
  midi = decodeMidi(document.getElementById('midi')?.textContent ?? '');
  const art = document.getElementById('art');
  if (art) { const img = document.createElement('img'); img.alt = ''; img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(art.textContent.trim()); document.body.prepend(img); }
  if (!midi) button.disabled = true;
  const credits = window.SnesBank.bank.instruments.filter((i) => i.credit);
  if (credits.length) {
    const details = document.createElement('details'), summary = document.createElement('summary'), text = document.createElement('p');
    summary.textContent = 'Sound credits';
    text.style.whiteSpace = 'pre-line';
    text.textContent = credits.map((i) => `${i.id}: ${i.credit.author} — ${i.credit.license}\n${i.credit.source}`).join('\n\n');
    details.style.cssText = 'position:fixed;top:12px;left:12px;max-height:50%;overflow:auto;color:white;background:#222c;padding:8px;font:12px system-ui;z-index:1';
    details.append(summary, text); document.body.append(details);
  }
});
button.addEventListener('click', () => {
  if (!synth) {
    synth = new window.WebAudioTinySynth({ quality: 1, useReverb: 0, voices: 64 });
    window.SnesBank.attach(synth);
    synth.loadMIDI(midi.slice().buffer);
    synth.loopEnd = loopEndTicks(synth.maxTick, synth.song.timebase); synth.setLoop(1);
  }
  if (playing) synth.stopMIDI();
  else { synth.getAudioContext().resume(); synth.locateMIDI(0); synth.playMIDI(); }
  playing = !playing; button.textContent = playing ? 'Stop' : 'Play';
});
window.SOUND = { orchestration: 'snes-brr-1', get synth() { return synth; }, get midi() { return midi; } };
