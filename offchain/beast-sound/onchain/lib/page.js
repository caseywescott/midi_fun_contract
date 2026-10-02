// token_uri page mount. Runs only when the page carries a line written by the contract:
//   <script>BEAST_SOUND="token,kills,scars,held,rank,count"</script>   inputs: the library composes
//   <script>BEAST_NOTES="f1,f2,…"</script>                            felts: the chain composed (BSN1)
// then the SVG as text in <script type="text/plain" id="art"> (XML-only syntax, shown via <img>).
// Loaded anywhere else, the library just defines window.BeastSound.
//
// Needs midi + play; plus api for an inputs line, or notes for a felts line. A felts page needs no
// composer at all.

function button(label, aria, right) {
  const b = document.createElement('button');
  b.type = 'button';
  b.textContent = label;
  b.setAttribute('aria-label', aria);
  b.style.cssText = `position:fixed;right:${right}px;bottom:12px;min-width:44px;height:44px;padding:0 10px;border-radius:22px;border:1px solid rgba(255,255,255,.35);background:rgba(0,0,0,.55);color:#fff;font:600 15px/1 system-ui,sans-serif;cursor:pointer;z-index:1`;
  document.body.appendChild(b);
  return b;
}

export function mountPage(BeastSound) {
  addEventListener('DOMContentLoaded', () => {
    const v1 = BeastSound.v1;
    const fromFelts = window.BEAST_NOTES !== undefined;
    if (!fromFelts && window.BEAST_SOUND === undefined) return;
    if (fromFelts ? !v1.notes : !v1.fromInputs) throw new Error(`beast-sound: this page needs module ${fromFelts ? 'notes' : 'api'}`);
    const art = document.getElementById('art');
    if (art) {
      const img = document.createElement('img');
      img.alt = '';
      img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(art.textContent.trim());
      document.body.insertBefore(img, document.body.firstChild);
    }
    let song = null;
    const ready = () => {
      if (song) return song;
      song = fromFelts ? v1.notes.decode(window.BEAST_NOTES) : v1.fromInputs(window.BEAST_SOUND);
      if (song.scoreHash) window.BEAST_SCORE_HASH = song.scoreHash;
      window.BEAST_SONG = song;
      return song;
    };
    addEventListener('load', () => setTimeout(ready, 0));

    const playBtn = button('♪', 'Play sound', 12);
    const midiBtn = button('MIDI', 'Download MIDI file', 64);
    let handle = null;
    const show = (on) => {
      playBtn.textContent = on ? '■' : '♪';
      playBtn.setAttribute('aria-label', on ? 'Stop sound' : 'Play sound');
    };
    midiBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const a = document.createElement('a');
      a.href = v1.midi.url(ready());
      a.download = `beast-${(window.BEAST_SOUND || 'score').split(',')[0]}.mid`;
      document.body.appendChild(a); a.click(); a.remove();
    });
    // Tap anywhere else (art or ♪) toggles; browsers only start audio from a gesture.
    document.addEventListener('click', () => {
      if (handle && handle.playing) { handle.stop(); return; }
      handle = v1.play(ready());
      handle.onEnd(() => show(false));
      show(true);
    });
  });
}
