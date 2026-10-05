# TinyChip: chiptune orchestration for the TinySynth page

A separate, removable module for webaudio-tinysynth, built only from TinySynth's own hooks. The page
player works the same without it.

| File | What it is | Where it goes |
|---|---|---|
| `tinychip.js` | The runtime: 20 presets, the chip drum kit and the orchestration rules | Stored onchain (`dist/tinychip.min.js`, 5.8 KB) |
| `tinysynth-chip.js` | The full bank: 100 presets (`TinyChipBank`) | Client add-on (`dist/tinychip-bank.min.js`, 13.6 KB) |
| `essentials.mjs` | Fills the runtime's preset data from the full bank at build time | Build only |

- **The 20 essentials** (chosen by ear, 2026-10-05) are programs 0–9 (the leads: Triangle, Pulse
  12.5% and 25%, Square, 4-bit Saw, the dry Square and Pulse 25%, Soft Pulse 12.5%, Fast and Wide
  Delayed Vibrato), 12–19 (the plucks: Pulse 25% and 12.5%, Square, Triangle, 4-bit Saw, Chip Harp,
  Chip Piano, Muted), Robot Hero Lead (50) and N163 Brass Wave (65). They use six sampled chip
  waveforms: 12.5/25/50% pulse, the NES 4-bit triangle, a 4-bit saw and the Namco 163 wave. There are
  no bass or pad presets: low and sustained voices get plucks and soft leads.
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
| Highest, faster than 120 BPM (shiny or animated) | Robot Hero Lead 50, N163 Brass Wave 65, 4-bit Saw Lead 4, Fast Vibrato Lead 8 |
| Lowest, mean pitch below E3 | Triangle Pluck 15, Chip Piano 18, 4-bit Saw Pluck 16, Square Pluck 14 |
| Lowest, higher than that | Keys: Pulse 25% Pluck 12, Pulse 12.5% Pluck 13, Chip Harp 17, Muted Pluck 19 |
| Between, resting a lot (under 0.7 notes per quarter) | Soft Pulse 12.5% 7, Wide Delayed Vibrato 9, Pulse 25% Lead (dry) 6, Square Lead (dry) 5 |
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

## onchain-midi-player sound settings

loothero's onchain-midi-player plays a MIDI file exactly as written and takes its sounds from a
`TinySynthSettings` value passed to `midi_segment(midi, settings)`. `synth_settings.mjs` builds that
value from the same bank data as the runtime:

- **Timbres:** what `BeastMidiProvider.get_settings` serves, by Beast type and shiny flag
  (`beastPrograms`): the type's family from `src/full_midi.js` (Magic 0/9/7 + 15/17/13, Hunter
  2/1/8 + 12/19/6, Brute 3/4/5 + 16/14/18) as custom timbres in their own program slots, the chip kit
  on the 11 drum notes Beast MIDI plays, and for a mega (shiny) Beast the mega leads, Robot Hero Lead
  (50) and N163 Brass Wave (65): 17 or 19 timbres, 1,346 to 1,783 bytes of `SETTINGS`. Quality 1, the
  class's default reverb (30) and volume (40). `--cairo` writes all six with the lookup
  `beast_synth_settings(beast_type, mega)`; the default run writes them as JSON in `settings/`.
  `beastSynthSettings(data, programs, drums)` builds any of the 20 essentials, and
  `interim_check.mjs` checks all 20.
- **Sampled waves:** every pitched chip wave the selected presets and drums use is a custom wave
  (`WaveDef::Samples`), so a preset added to `BEAST_PROGRAMS` gets its exact wave with nothing else
  to change. Each table is one cycle of the wave from `tinysynth-chip.js`'s own `registerWaves`, one
  i8 sample per step (`clamp(round(x * 128), -128, 127)`); `STEPS` in `synth_settings.mjs` lists the
  19 pitched waves and their steps per cycle, and the generator checks each one is exactly stepwise.
  `TinySynthSettings.waves` holds only the waves the selection uses, in `STEPS` order, and each
  operator's `Waveform::Custom(i)` points into it. onchain-midi-player's player registers them with the
  engine's `setSampleWave`, which plays a table sample-and-hold at the note's pitch as TinyChip's
  own looped buffer does, so the operators keep their original level and are no longer split. Today
  that is the 50% pulse (the snare) and the NES triangle (the Triangle Lead, kick and toms); all 20
  essentials use five (12.5%, 25% and 50% pulse, triangle, 4-bit saw). The 50% pulse is a table
  too because TinySynth's square is band-limited, duller than TinyChip's (Square Lead brightness
  0.87x as a square, 0.96x as two samples).
- **Built-in waves:** the LFSR noises stay TinySynth's white and metallic noise.
- **Loudness:** with exact tables, every essential and drum is within 0.04 dB of TinyChip's own
  (tolerance 0.5 dB), noise drums within the noise's render-to-render spread. Brightness (spectral
  centroid) is 0.57-1.03x for the essentials and 0.91-1.03x for the drums. With all 20 essentials
  and the drums, `SETTINGS` is 2,927 bytes and 46 operators, against 4,180 bytes and 75 operators
  when the chip waves were approximated with built-in waves.
- **Cairo:** `contracts/beast_sound/src/synth_settings.cairo` (`beast_synth_settings()`) is generated
  from the same function, with onchain-midi-player's own types (re-exported by
  `midi_provider::synth`); tests check its Serde hash against the generator's and run the class's
  `validate` on it, and its Serde matches onchain-midi-player's own fixture serializer.

```bash
node onchain/tinychip/synth_settings.mjs onchain/tinychip/beast_synth_settings.json  # JSON, for preview.mjs --settings
node onchain/tinychip/synth_settings.mjs --cairo                                      # regenerate the Cairo
PLAYWRIGHT_CORE=... node onchain/tinychip/interim_check.mjs <onchain-midi-player>/tests/vendor/webaudio-tinysynth-fc04dbe.min.js
```

## Tests

| Test | What it checks |
|---|---|
| `test/tinychip.test.mjs` | Runtime matches the bank; orchestration determinism, roles and spread over the gallery; bare scores; Bank Select with and without the full bank; untouched MIDI |
| `onchain/tinychip/interim_check.mjs` | The TinySynthSettings timbres against TinyChip's own presets and drums, rendered in Chrome through onchain-midi-player's engine: loudness within 0.5 dB (noise timbres 1 dB), brightness reported |
| `onchain/browser-check.mjs` | Real pages in Chrome. With `TINYCHIP_ONCHAIN` on, bare scores report `tinychip-2` and each note channel plays 129 + its orchestrated preset; off, `1` and program 128 |
