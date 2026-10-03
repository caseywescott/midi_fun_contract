# TinyChip: an optional chiptune pack for the TinySynth page

100 chiptune presets and a 19-key chip drum kit for webaudio-tinysynth, built only from tinysynth's
own hooks. It's a separate, removable module: the page player works the same without it.

- **Presets.** Programs 0–49 are generic chip voices (leads, plucks, basses, pads, arps, Game Boy
  wave, FM, noise). Programs 50–99 are styled after classic sound chips and soundtracks: NES, the
  Famicom expansion chips, Game Boy, C64 SID, Atari 2600, AY/PSG, Genesis FM and PC Engine.
- **Waveforms.** 21 sampled waveforms: pulse widths, the NES 4-bit triangle, saws, wavetables,
  LFSR and TIA noise. Each sits in `synth.noiseBuf` as a 1-second buffer holding exactly 440
  cycles, so tinysynth plays it at note pitch without smoothing it.
- **Loudness.** All presets are matched within 0.3 dB, measured as K-weighted RMS of the same
  phrase (`loudness.mjs`, report in `loudness.json`).
- **Size.** 14.2 KB minified (`dist/tinychip.min.js`).

## How the page player uses it

After loading a score, the player calls `window.TinyChip.attach(synth, …)` if the pack is present.
That call is one guarded line in `player-src.js`.

| Score | With TinyChip | Without it |
|---|---|---|
| Bare Beast score (no instruments, no drums) | Every voice plays the chip Triangle Lead; the accompaniment uses the chip kit. Orchestration `tinychip-1` | The player's own lead and the GM kit. Orchestration `1` |
| MIDI with Bank Select MSB = 1 (`CC 0 = 1`) on a channel | That channel's program numbers 0–99 play TinyChip presets; on channel 10, the chip kit | General MIDI |
| Any other MIDI | Unchanged (`attach` returns null and installs nothing) | Unchanged |

The presets live in program slots 129–228, above General MIDI. Slot 128 stays the player's own
lead, so no GM instrument is replaced.

## Turning it off, or keeping it client-only

- **Remove it completely:** revert the commit that added this directory. That takes the module, the
  build step, the player hook and the regenerated page data with it.
- **Client-only:** set `TINYCHIP_ONCHAIN = false` in `config.mjs`, then rebuild:
  ```bash
  node onchain/build.mjs && node onchain/golden.mjs && node onchain/gallery.mjs --rebuild
  ```
  - The stored page drops back to 1,719 felts, and Beasts play with the player's own orchestration.
  - Any client (a site, wallet or game embedding the page) can still add the pack before the first
    Play, and the player will use it:
  ```js
  const s = document.createElement('script');
  s.textContent = await (await fetch('/tinychip.min.js')).text();  // dist/tinychip.min.js
  document.head.appendChild(s);
  ```
- **Your own pack:** `TinyChip.install(synth, { programBase, drums })` also works on any tinysynth
  instance, outside the page.

## Tests

| Test | What it checks |
|---|---|
| `test/tinychip.test.mjs` | Where presets land, GM kept intact, bare scores, Bank Select remapping, untouched MIDI |
| `onchain/browser-check.mjs` | Real pages in Chrome. It expects `tinychip-1` and program 129 for bare scores when `TINYCHIP_ONCHAIN` is on, and `1` and program 128 when it's off |
