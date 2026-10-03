# webaudio-tinysynth (vendored)

| | |
|---|---|
| Source | https://github.com/Provable-Games/webaudio-tinysynth (fork of https://github.com/g200kg/webaudio-tinysynth) |
| Revision | `b70ba90d63c5ea657cb67ca98de90d7f778c29bd` (main, 2026-10-02) |
| File | `webaudio-tinysynth.js`, unmodified |
| sha256 | `abb2d0fb828ada86b692547560102035cf486fc1fac60ca190b5851235c1ee23` |
| License | Apache-2.0 (`LICENSE`, `NOTICE`) |

`../../build.mjs` reads the file, checks its sha256 against `patch.mjs`, then minifies it with esbuild
into `../../dist/tinysynth.min.js` (36 KB) under the banner
`/*! webaudio-tinysynth (c) g200kg, Apache-2.0; Provable Games fork b70ba90, modified (see NOTICE) */`.

## What the fork changes from upstream `3d75aee`

| Change | Why the page needs it |
|---|---|
| MIDI tempo kept fractional instead of `Math.floor(60000000 / tempo)` | Beast tempos are 455,000–500,000 µs per beat. Upstream floors 131.87 BPM to 131, so a score drifts 0.7% (about 0.4 s a minute). |
| `loopEnd` / `setLoopEnd()`: a loop's next pass starts at `loopEnd` (ticks) instead of on the last event | The page loops in whole 4/4 bars. |
| GUI panel and `<webaudio-tinysynth>` element removed | Not used by the page; about 6 KB less to store onchain. |

These were local patches here before the fork carried them. `patch.mjs` can still apply local
changes on top (`PATCHES`, each matching exactly once, checked against `PATCHED_SHA256`); there are
none now.

`test/player.test.mjs` plays a Beast score through the shipped file against a mock WebAudio clock:
every note lands within 1e-9 s of `start + tick × tempo_us / 480e6` over two loop passes.

## Internals the page relies on

Beyond the public API, these modules read TinySynth fields, so a fork update must keep them:
- BeatSync: `playing`, `playTick`, `playTime`, `tick2Time`, `loopEnd`, `maxTick`, `actx`, `song.timebase`.
- TinyChip: `setTimbre`, `program`, `drummap`, `noiseBuf`, `getAudioContext`, `setProgram`, `pg`.

## Updating

Replace `webaudio-tinysynth.js` (and `NOTICE`), update `UPSTREAM` and `PATCHED_SHA256` in
`patch.mjs`, rebuild (`build.mjs`, `golden.mjs`, `gallery.mjs --rebuild`), and rerun the Node tests,
`scarb test` and `browser-check.mjs`. A new TinySynth is a new page class (see `../../README.md`,
Versioning).
