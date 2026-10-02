// Generic offline SMF player. All channels keep the SMF's assignments; absent program changes
// use General MIDI program 0 (acoustic grand piano). No extra notes or drums are synthesized.
window.addEventListener('DOMContentLoaded', () => {
  const byId = id => document.getElementById(id);
  const status = byId('status');
  byId('artwork').src = 'data:image/svg+xml;base64,' + byId('art').textContent.trim();
  let synth;
  let midiBuffer;
  let operation = 0;
  let started = false;
  const prepare = async () => {
    if (!synth) {
      const binary = atob(byId('midi').textContent.trim());
      const bytes = Uint8Array.from(binary, c => c.charCodeAt(0));
      if (binary.slice(0, 4) !== 'MThd') throw new Error('Invalid MIDI file');
      synth = new WebAudioTinySynth({ quality: 1, useReverb: 0, voices: 64 });
      midiBuffer = bytes.buffer;
      // Exposed for inspection and timing checks; no collection-specific state.
      window.midiPlayer = synth;
    }
    await synth.actx.resume();
    return synth;
  };
  const start = async restart => {
    const request = ++operation;
    try {
      const player = await prepare();
      if (request !== operation) return;
      if (restart || !player.playing) {
        // Seeking alone retains late programs/controllers/tempo. Reload resets the whole SMF.
        player.loadMIDI(midiBuffer);
        player.setLoop(byId('loop').checked ? 1 : 0);
        player.playMIDI();
      }
      started = true;
      status.textContent = 'Playing';
    } catch (error) { if (request === operation) status.textContent = 'Unable to play: ' + error.message; }
  };
  byId('play').addEventListener('click', () => start(false));
  byId('restart').addEventListener('click', () => start(true));
  byId('stop').addEventListener('click', () => {
    ++operation;
    started = false;
    if (synth) synth.stopMIDI();
    status.textContent = 'Stopped';
  });
  setInterval(() => {
    if (started && synth && !synth.playing) { started = false; status.textContent = 'Finished'; }
  }, 100);
  byId('loop').addEventListener('change', event => { if (synth) synth.setLoop(event.target.checked ? 1 : 0); });
});
