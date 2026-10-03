# BeatSync: animated Beast art in time with the music

Browsers give a page no control over a GIF: there's no play, pause, seek or frame index. An animated
Beast's GIF therefore runs on its own timer (3–4 frames at 100–200 ms) and drifts against the music.
BeatSync takes over the frame timing so that picture and sound follow one clock. It's a separate,
removable module, and the page player works the same without it.

## How it works

1. **Decode.** It finds the GIF inside the token's SVG and decodes its frames. The decoder is a small
   LZW decoder with no dependencies; it handles interlacing and disposal. On all 150 Beast GIFs it is
   pixel-identical to Chrome's own `ImageDecoder`.
2. **Layer.** It builds one copy of the SVG per frame, with that frame swapped in as a PNG, and stacks
   those copies over the original `<img>`.
3. **Step.** On every animation frame it reads the position tinysynth is *playing* (the scheduled
   tick minus the look-ahead) and shows the matching layer. When stopped, the original native GIF
   shows again.

| Mode | Frame shown |
|---|---|
| `beat` (default) | Advances one frame per eighth note, so the creature moves on the beat |
| `native` | Uses the GIF's own frame delays, but timed by the audio clock so it never drifts |
| `off` | The native GIF, as without BeatSync |

The page exposes it as `SOUND.beat` (`frames`, `delays`, `mode`, `setMode(m)`, `shown`). Art without
an animated GIF is left alone: `attach` returns null.

- **Size:** 3.4 KB minified (`dist/beatsync.min.js`). It takes the stored page from 2,595 to 2,739
  felts, and `MidiSoundPage` is 26,566 CASM felts.
- **Hook:** one guarded line in `player-src.js`, after the art is placed.

## Turning it off, or keeping it client-only

- **Remove it completely:** revert the commit that added this directory. That takes the module, the
  build step, the player hook and the regenerated page data with it.
- **Client-only:** set `BEATSYNC_ONCHAIN = false` in `config.mjs`, then rebuild:
  ```bash
  node onchain/build.mjs && node onchain/golden.mjs && node onchain/gallery.mjs --rebuild
  ```
  A client embedding the page can still add the module before the page's `DOMContentLoaded`, for
  example as an injected script, and the player will attach it. A client that renders the art
  itself can call `BeatSync.attach({ img, svg, synth: () => mySynth })` directly.

## Tests

- `test/beatsync.test.mjs`: the decoder on real animated Beasts, and the audible-tick clock.
- The real-time check plays an animated Beast page in Chrome and compares the frame shown with the
  frame due from the audible tick on every animation frame. Both modes match on every sample, and
  stopping restores the native GIF.
