# webaudio-tinysynth (vendored)

| | |
|---|---|
| Upstream | https://github.com/g200kg/webaudio-tinysynth |
| Revision | `3d75aee4b3f43cbd932265e7d60201fd5b770397` (master, 2022-12-20) |
| File | `webaudio-tinysynth.js`, unmodified |
| sha256 (upstream file) | `dd2b1d95d64499dfc3c292858e8c2d6525dc0bcdc345a900b7db207dffaae38c` |
| sha256 (after patches) | `c20c90a1fd924f2ce5c106a736007abcd0dc320407a99c2ee3a6f0179eabf2d0` |
| License | Apache-2.0 (`LICENSE`, sha256 `b40930bb…f833e1`) |

`../../build.mjs` reads the upstream file, checks its sha256, applies the patches in `patch.mjs`
(each must match exactly once), checks the patched sha256, then minifies it with esbuild into
`../../dist/tinysynth.min.js` (42 KB) under the banner
`/*! webaudio-tinysynth 3d75aee (c) g200kg, Apache-2.0; modified: fractional-tempo, loop-end */`.
`tinysynth.patch` is the same change as a unified diff, for review.

## Patches

| Name | Change | Why |
|---|---|---|
| `fractional-tempo` | `60000000 / tempo` instead of `Math.floor(60000000 / tempo)` when parsing the MIDI tempo meta event | Beast tempos are 455,000–500,000 µs per beat. Upstream floors 131.87 BPM to 131, so a score drifts 0.7% (about 0.4 s a minute). |
| `loop-end` | When `loopEnd` (ticks) is set, a loop's next pass starts at `loopEnd` instead of on the last event | The page loops in whole 4/4 bars, as the previous scheduler did. Without it the next pass starts on the final note-off. |

`test/player.test.mjs` plays a Beast score through the shipped file against a mock WebAudio clock:
every note lands within 1e-9 s of `start + tick × tempo_us / 480e6` over two loop passes, and the
unpatched upstream file drifts and wraps early.

## Updating

Replace `webaudio-tinysynth.js`, update `UPSTREAM` and `PATCHED_SHA256` in `patch.mjs`, regenerate
`tinysynth.patch`, rebuild, and rerun the Node tests and `browser-check.mjs`. A new TinySynth is a new
page class (see `../../README.md`, Versioning).
