# SNES-style sample pipeline

Add your sounds later. `manifest.json` is intentionally empty and `SNES_ONCHAIN` is false.
The default page build remains byte-for-byte unchanged. No recordings, SoundFonts or game assets
are included. This module is on the `feat/snes-brr-pipeline` branch, based on `v1.0.1`.

## Add sounds

Run commands from `offchain/beast-sound`:

1. Put short WAV files in `onchain/snes/samples/` (ignored by Git).
2. Copy entries from `manifest.example.json` into `manifest.json`, replacing paths, tuning,
   loop points and credits with your own values. Paths are relative to the manifest.
3. Run `npm run snes:build` and open `onchain/snes/dist/lab.html` to audition samples or a MIDI.

```sh
npm run snes:build
# Or build another bank without changing the default manifest:
npm run snes:build -- /absolute/path/to/manifest.json /absolute/path/to/output
npm run snes:test
```

Input: mono/stereo RIFF WAV, PCM 8/16/24/32-bit or float32, 8–192 kHz.
Output: mono BRR at 16–32 kHz, with a 20 KiB default compressed-bank budget, hard maximum 64 KiB.
Each selected clip must be at most four seconds; short attacks plus loops are much more economical.
Identical encoded samples with identical rate/loop metadata are stored once across instruments.

| Manifest field | Meaning |
|---|---|
| `program` | Zero-based MIDI program 0–127; optional slot 128 for callers using the old custom lead. Use program 0 for bare Beast scores. |
| `drum` | MIDI percussion key, instead of `program`; channel 10 uses the drum mapping. |
| `rootNote` | MIDI note of the recorded sound; e.g. middle C = 60. Required. |
| `sampleRate` | Output rate, default 16000; up to 32000. |
| `trimStart`, `trimEnd` | Seconds in the original WAV; defaults to the whole file. |
| `loopStart` | Seconds relative to the trimmed start; omit for one-shot. Rounded to the nearest 16-sample block. The trim end is the loop end, rounded down to a block. Actual indices are in the report. |
| `gain` | Pre-encoding gain, default 1. Peaks are limited to ±0.9 to leave BRR headroom. |
| `tuneCents` | Fine tuning, default 0. |
| `volume` | Playback gain 0–1, default 0.5. |
| `envelope` | Attack, decay, release in seconds; sustain level 0–1. These are musical envelopes, not SNES register values. |
| `credit` | Author, license text/identifier and source. Included in the bank and shown in the lab/page. Supply any required license notice in full. |

Choose loop points by listening. The builder aligns loops and reports the decoded seam jump, but
does not guess musical sustain regions or crossfade loops. `snrDb` measures encoding error against
prepared PCM; it is not a perceptual-quality guarantee. One-shots are padded with silence to a block.

## Compact Cairo storage

The pipeline is WAV → mono/low-pass resample → BRR → deduplicated bank → minified browser runtime
→ pre-encoded page → Cairo `ByteArray` literal. BRR compresses each 16 samples into 9 bytes. The
encoder searches all four filters and ranges; the first and loop-entry blocks use filter 0 so the
browser can cache decoded loops without history drift.

`dist/page_data.cairo` is a candidate page module with the same `STORED_LEN` and `stored_segment()`
API as the existing TinySynth page. It stores 31-byte words and aligns the HTML to 279 bytes before
base64, using `onchain/page.js`. There is no PCM, sample encoder or resampler in Cairo; only the
packed fixed page is copied at `token_uri` time. Browser decoding is lazy and cached per sample.

The JSON bank contains base64 BRR, and the page adds its own base64 layer. Consequently sample data
alone costs about 16/9 of its raw BRR size in stored page text, plus metadata and alignment. The
report includes both layers. A data-word count is **not** the compiled Sierra/CASM size or gas cost.

```sh
# Compile the actual MidiSoundPage with the candidate in a temporary workspace:
node onchain/snes/measure-cairo.mjs
node onchain/snes/measure-cairo.mjs /absolute/path/to/manifest.json
# Optional synthetic capacity check; does not add sounds to your bank:
node onchain/snes/measure-cairo.mjs --stress-bytes 20480
```

The measurement script uses the repository's pinned Scarb toolchain and reports compiled Sierra
and CASM lengths against the repository's 81,920-felt CASM threshold. It fails if that threshold is
exceeded. It leaves production source/artifacts unchanged. Measure real bank sizes before enabling;
RPC limits, gas and the full NFT call path still need benchmarking with the final sounds.

Measured with Scarb 2.21.0 on 3 November 2026, including the actual `MidiSoundPage` contract,
TinySynth fallback, sample runtime, player and page assembly:

| Candidate | BRR bytes | Stored page bytes | CASM felts |
|---|---:|---:|---:|
| Existing TinyChip/BeatSync page | — | 65,472 | 23,378 |
| SNES pipeline, no samples | 0 | 61,380 | 22,982 |
| Synthetic ~20 KiB bank | 20,475 | 98,208 | 26,546 |
| Synthetic ~64 KiB bank | 65,529 | 178,188 | 34,286 |

The size probes use one synthetic instrument with short credits. Real metadata changes the totals.
Both populated probes fit the configured CASM threshold; these measurements do not establish gas
cost, RPC response suitability, or the maximum deployable bank. The empty candidate uses a smaller
player and replaces TinyChip/BeatSync, which accounts for its smaller size.

To opt into the production page after supplying samples:

1. Set `SNES_ONCHAIN = true` in `config.mjs`.
2. Run `node onchain/build.mjs`, `node onchain/golden.mjs` and `node onchain/gallery.mjs --rebuild`.
3. Run `npm test`, `scarb build -p midi_contracts` and `scarb test -p midi_contracts` from the
   appropriate package/repository directory, then the SNES browser test and the existing gas bench.

The normal generator writes the tracked Cairo module; do not hand-edit or copy constants into it.
An enabled empty bank is rejected before production artifacts are written. Switching back to false
and rebuilding restores the TinyChip/BeatSync page. The SNES page has its own orchestration id
`snes-brr-1`, uses MIDI programs as written, and replaces TinyChip/BeatSync; it adds no drum pattern.

## Browser playback

```js
import { attach, createSampler } from './onchain/snes/runtime.js';
const installed = attach(tinySynth, bank); // after TinySynth has its AudioContext
// Existing MIDI playback uses samples for mapped programs and TinySynth for everything else.
installed.dispose(); // stops sample voices and restores the wrapped methods
```

The generated `bank.min.js` also exposes `window.SnesBank.attach(synth)` and
`window.SnesBank.createSampler(audioContext, options)`. A standalone sampler provides `noteOn`,
`noteOff`, `releaseSustain`, `bend`, `stop`, and `dispose`. Send scheduled notes chronologically.
Call `stop()` before seeking or replacing a sequence. `noteOn` returns false for an unmapped slot.

The sample layer defaults to eight simultaneous voices with oldest-voice stealing, velocity,
tuning, loops, ADSR, stereo channel routing and optional echo. The TinySynth adapter preserves
channel volume, expression, pan, pitch bend, sustain and stop behavior. Unmapped TinySynth fallback
voices have their own limit; this is not a global eight-voice cap across both engines. CC1 modulation,
hardware noise and pitch modulation are not implemented for sample voices.

The sound is SNES-inspired: real BRR compression, binomial smoothing, browser pitch resampling,
low-pass filtering and a feedback delay with an eight-tap FIR. It does **not** implement the exact
S-DSP Gaussian lookup table, register-rate envelopes, fixed 32 kHz mixer or hardware echo arithmetic.
The final timbre depends on the sounds and loop points you supply.

## Verification

```sh
npm test
# Install/use a matching Playwright + Chromium pair, as for the existing browser-check.mjs:
PLAYWRIGHT_CORE=/absolute/path/to/playwright node onchain/snes/browser-check.mjs
# CHROMIUM_EXECUTABLE may explicitly select an existing compatible headless Chromium binary.
```

Unit tests cover known BRR vectors, predictor reset at loops, lossy round-trip quality, antialiasing,
WAV rejection, size limits, deduplication, unsafe script text and Cairo word alignment. The browser
test synthesizes a temporary test signal and checks actual rendered audio, octave pitch, release,
polyphony, stop/voice-stealing, echo, TinySynth fallback/controllers and a generated token page with
all network requests blocked. It does not add a sound to the supplied bank.

Format references: [BRR block documentation](https://snes.nesdev.org/wiki/BRR_samples) and
[SPC-700 programming notes](https://snesmusic.org/files/spc700_documentation.html).
