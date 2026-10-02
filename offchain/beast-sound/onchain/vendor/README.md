# Vendored WebAudio-TinySynth

Upstream: https://github.com/g200kg/webaudio-tinysynth

Pinned revision: `3d75aee4b3f43cbd932265e7d60201fd5b770397`.

- `webaudio-tinysynth.upstream.min.js`: untouched distribution, 43,217 bytes; SHA-256 `a381bcc794f476b7e17fefb32d1e18ae053ee33392857118d3101c19eff657ec`.
- `webaudio-tinysynth.upstream.js`: untouched source; SHA-256 `dd2b1d95d64499dfc3c292858e8c2d6525dc0bcdc345a900b7db207dffaae38c`.
- `LICENSE`: exact upstream Apache License 2.0 text; SHA-256 `b40930bbcf80744c86c46a12bc9da056641d722716c378f5659b9e555ef833e1`.

`build.mjs` verifies the minified checksum and applies one marked modification: remove `Math.floor` from the MIDI Set Tempo conversion `60000000 / microseconds_per_quarter`. It preserves fractional BPM and changes no note/instrument data. An Apache-2.0 attribution and modification notice remain in the embedded player and generated page. The upstream files are never edited.
