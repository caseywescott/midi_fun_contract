# TinyChip: chiptune orchestration for the TinySynth page

A separate, removable module for webaudio-tinysynth, built only from TinySynth's own hooks. The page
player works the same without it.

| File | What it is | Where it goes |
|---|---|---|
| `tinychip.js` | The runtime: 20 presets, the chip drum kit and the orchestration rules | Stored onchain (`dist/tinychip.min.js`, 5.8 KB) |
| `tinysynth-chip.js` | The full bank: 100 presets (`TinyChipBank`) | Client add-on (`dist/tinychip-bank.min.js`, 13.6 KB) |
| `essentials.mjs` | Fills the runtime's preset data from the full bank at build time | Build only |

- **The 20 essentials** use five sampled chip waveforms: 12.5/25/50% pulse, the NES 4-bit triangle
  and a 4-bit saw. They are the Triangle, Pulse and Square leads, 4-bit Saw Lead, plucks, Chip Piano,
  four basses, three pads, Octave Arp, Pulse Blip and five NES-styled voices (Robot Hero Lead,
  Vampire Hunter Lead, Hero Fanfare, Bounty Hunter Pad, Sunsoft Saw Bass).
- **One source of truth.** The runtime's presets and drum kit are generated from the full bank, with
  each preset's loudness gain folded into its levels, so the 20 sound the same either way.
  `test/tinychip.test.mjs` checks every operator, drum and waveform against the bank.
- **Waveforms.** Each is a 1-second buffer in `synth.noiseBuf` holding exactly 440 cycles, so TinySynth
  plays it at note pitch without smoothing it.
- **Loudness.** All 100 presets are matched within 0.3 dB (K-weighted RMS of the same phrase,
  `loudness.mjs`, report in `loudness.json`).

## Orchestration (`tinychip-2`)

The player is generic: it sees only the MIDI file. So the orchestration reads the score, and the
score already carries the Beast's traits: voice count (tier, kills, rank), register (species key,
health), rests (kills, ornaments) and tempo (shiny, animated).

| Voice | Pool (bank program numbers) |
|---|---|
| Highest (the lead), tempo 120 BPM | Triangle Lead 0, Pulse 25% Lead 2, Square Lead 3, Pulse 12.5% Lead 1 |
| Highest, faster than 120 BPM (shiny or animated) | Robot Hero Lead 50, Vampire Hunter Lead 51, Hero Fanfare 53, 4-bit Saw Lead 4 |
| Lowest, mean pitch below E3 | Triangle Bass 20, Sunsoft Saw Bass 61, 4-bit Saw Bass 23, Pulse Bass 21 |
| Lowest, higher than that | Keys: Pulse 25% Pluck 12, Triangle Pluck 15, Chip Piano 18, Pulse Blip 38 |
| Between, resting a lot (under 0.7 notes per quarter) | Pads: Pulse Swell 28, Triangle Pad 33, Bounty Hunter Pad 54, Octave Arp 34 |
| Between, moving | Keys |

A hash of the notes picks within each pool (FNV-1a of each note, summed, so the order of notes on
the same tick doesn't matter), and no preset is used twice in a score. The same
MIDI always gets the same instruments. Across the 100 gallery Beasts that gives 62 different
orchestrations and uses all 20 presets (42 of those Beasts have one voice, so they differ only in
the lead). The drums the player adds use the chip kit.

| Score | With TinyChip | Without it |
|---|---|---|
| Bare Beast score (no instruments, no drums) | Orchestrated as above, with the chip kit. Orchestration `tinychip-2` | The player's own lead and the GM kit. Orchestration `1` |
| MIDI with Bank Select MSB = 1 (`CC 0 = 1`) on a channel | Program numbers use bank numbering (0–99): the 20 here, others play the Triangle Lead; all 100 when the client bank is present. Channel 10 gets the chip kit | General MIDI |
| Any other MIDI | Unchanged (`attach` returns null and installs nothing) | Unchanged |

Presets sit at program slots 129 + bank number, above General MIDI. Slot 128 stays the player's own
lead, so no GM instrument is replaced.

## Size

| Stored page | Felts |
|---|---|
| Without TinyChip | 1,719 |
| With TinyChip | 1,971 (+252) |
| With TinyChip and BeatSync | 2,115 |

The previous version stored all 100 presets: 14.2 KB, 612 felts.

## Turning it off, or keeping it client-only

- **Remove it completely:** revert the commits that added this directory. That takes the module, the
  build step, the player hook and the regenerated page data with it.
- **Client-only:** set `TINYCHIP_ONCHAIN = false` in `config.mjs`, then rebuild:
  ```bash
  node onchain/build.mjs && node onchain/golden.mjs && node onchain/gallery.mjs --rebuild
  ```
  - The stored page drops back to 1,719 felts, and Beasts play with the player's own orchestration.
  - Any client (a site, wallet or game embedding the page) can still add the runtime before the first
    Play, and the player will use it:
  ```js
  const s = document.createElement('script');
  s.textContent = await (await fetch('/tinychip.min.js')).text();  // dist/tinychip.min.js
  document.head.appendChild(s);
  ```
- **The full bank:** add `dist/tinychip-bank.min.js` the same way to make all 100 presets available
  to Bank Select 1 MIDI. Bare Beast scores sound the same with or without it.
- **Outside the page:** `TinyChipBank.install(synth, { programBase, drums })` works on any tinysynth
  instance.

## onchain-tinysynth sound settings

loothero's onchain-tinysynth plays a MIDI file exactly as written and takes its sounds from a
`SynthSettings` value passed to `midi_segment(midi, settings)`. `synth_settings.mjs` builds that
value from the same bank data as the runtime:

- **Timbres:** the 20 essentials as custom timbres in their own program slots (bank numbers 0-61;
  the self-contained Beast MIDI selects them with ordinary program changes) and the chip kit on its
  19 drum notes: 39 timbres, 85 operators, 4,295 bytes of `SETTINGS`. Quality 1 and no reverb, as
  the page plays; master volume 40, the class's default.
- **Interim waves:** the class rejects custom waves until its issue #2, so each sampled chip wave is
  rebuilt from TinySynth's own (table in `synth_settings.mjs`). The 25% pulse is exact in
  magnitude spectrum (two squares), the 12.5% pulse close (three), and the NES triangle a smooth
  triangle plus its step error (a saw 32 times faster). Every timbre is loudness-matched to its
  original: tonal timbres within 0.21 dB, noise drums within the noise's own render-to-render
  spread. Brightness (spectral centroid) stays within 0.7-1.3x except the triangle voices (0.4-0.6x,
  the steps are only approximated) and the triangle kick and toms (0.25x, cleaner than the
  4-bit originals). Once custom waves land, the waves become `SynthSettings.waves` and the
  operators go back to one per wave.
- **Cairo:** `contracts/beast_sound/src/synth_settings.cairo` (`beast_synth_settings()`) is generated
  from the same function, with the types mirrored in `midi_provider::synth`; a test checks its
  Serde hash against the generator's, and its Serde matches onchain-tinysynth's own fixture
  serializer.

```bash
node onchain/tinychip/synth_settings.mjs onchain/tinychip/beast_synth_settings.json  # JSON, for preview.mjs --settings
node onchain/tinychip/synth_settings.mjs --cairo                                      # regenerate the Cairo
PLAYWRIGHT_CORE=... node onchain/tinychip/interim_check.mjs <onchain-tinysynth>/tests/vendor/webaudio-tinysynth-b198d6c.min.js
```

## Tests

| Test | What it checks |
|---|---|
| `test/tinychip.test.mjs` | Runtime matches the bank; orchestration determinism, roles and spread over the gallery; bare scores; Bank Select with and without the full bank; untouched MIDI |
| `onchain/tinychip/interim_check.mjs` | The SynthSettings timbres against TinyChip's own presets and drums, rendered in Chrome through onchain-tinysynth's engine: loudness within 0.5 dB (noise timbres 1 dB), brightness reported |
| `onchain/browser-check.mjs` | Real pages in Chrome. With `TINYCHIP_ONCHAIN` on, bare scores report `tinychip-2` and each note channel plays 129 + its orchestrated preset; off, `1` and program 128 |
