// token_uri page mount. Runs only when the page carries the contract's inputs line
// (window.BEAST_SOUND); loaded anywhere else, the library just defines window.BeastSound.
//
// The page is [library][<script>BEAST_SOUND="…"</script>][<script type="text/plain" id="art">SVG].
// The Beasts SVG uses XML-only syntax, so it is shown through an <img> rather than inlined.

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
    if (window.BEAST_SOUND === undefined) return;
    const art = document.getElementById('art');
    if (art) {
      const img = document.createElement('img');
      img.alt = '';
      img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(art.textContent.trim());
      document.body.insertBefore(img, document.body.firstChild);
    }
    let song = null;
    const ready = () => song || (song = BeastSound.fromInputs(window.BEAST_SOUND), window.BEAST_SCORE_HASH = song.scoreHash, song);
    addEventListener('load', () => setTimeout(ready, 0));

    const playBtn = button('♪', 'Play sound', 12);
    const midiBtn = button('MIDI', 'Download MIDI file', 64);
    BeastSound.onPlayingChange((on) => {
      playBtn.textContent = on ? '■' : '♪';
      playBtn.setAttribute('aria-label', on ? 'Stop sound' : 'Play sound');
    });
    midiBtn.addEventListener('click', (e) => {
      e.stopPropagation();
      const a = document.createElement('a');
      a.href = BeastSound.midiUrl(ready());
      a.download = `beast-${ready().tokenId}.mid`;
      document.body.appendChild(a); a.click(); a.remove();
    });
    // Tap anywhere else (art or ♪) toggles; browsers only start audio from a gesture.
    document.addEventListener('click', () => (BeastSound.isPlaying() ? BeastSound.stop() : BeastSound.play(ready())));
  });
}
