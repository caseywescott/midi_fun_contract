# Beast Sound through onchain-midi-player, end to end

Runs `BeastMidiProvider`'s output (the `get_settings` Serde and the self-contained `get_midi` bytes)
through loothero's class in a copy of its repo, as the Beasts NFT's `token_uri` would.

```bash
git clone https://github.com/Provable-Games/onchain-midi-player /tmp/ots_e2e
git -C /tmp/ots_e2e checkout 38d76ce6120d964502891c16445ce083bf1bfedd   # the rev midi_provider pins (scarb 2.20.1, snforge 0.64.0)
(cd offchain/beast-sound && npm install)                                  # fixtures.mjs imports the JS engine
node scripts/tinysynth_e2e/fixtures.mjs /tmp/ots_e2e/tests/beast_e2e_fixtures.cairo
cp scripts/tinysynth_e2e/test_beast_e2e.cairo /tmp/ots_e2e/tests/
printf 'mod beast_e2e_fixtures;\nmod test_beast_e2e;\n' >> /tmp/ots_e2e/tests/lib.cairo
(cd /tmp/ots_e2e && snforge test test_beast_e2e)
```

Results at 38d76ce (2026-10-09, d565daf: `get_midi` plays the Genesis Track), L2 gas. The fixtures
are the Genesis Tracks `get_midi` returns: the Warlock (#1, 4,726 bytes, Magic settings, 17 timbres)
and the largest file, shiny #32 (7,197 bytes, mega Hunter settings, 19 timbres), reverb 30:

| Test | Gas |
|---|---|
| `beast_build` (fixtures only: both settings' Serde, two MIDI files) | 2.2M |
| `beast_settings_validate` (both settings) | 3.8M |
| `beast_encode_settings` | 9.7M |
| `beast_lc_midi_segment_warlock` (4,726-byte MIDI, library call) | 92.8M |
| `beast_lc_midi_segment_heaviest` (7,197-byte mega MIDI, mega Hunter settings) | 133.4M |
| the same with the class's `default_settings()` | 105.4M |
| `beast_direct_midi_segment_heaviest` (crate function, no library call) | 128.0M |
| `beast_token_uri_heaviest` (Beasts-layout `token_uri`, crate functions) | 145.8M |

One call to the provider's `get_midi`, over all 150 Genesis Tracks (75 species, normal and shiny;
cairo-test estimate, Cairo 2.20.1, mock deploys subtracted; `gas_probe_*` and a one-off sweep in
contracts/beast_sound/src/tests.cairo):

| | min | median | max |
|---|---|---|---|
| normal | 0.124B (1.00M steps) | 0.226B (1.81M) | 0.342B (2.74M) |
| shiny | 0.132B (1.06M) | 0.241B (1.92M) | 0.362B (2.88M, #28) |

By tier (normal, median): tiers 1-2 0.32B, tier 3 0.23B, tiers 4-5 0.14B. Shiny adds about 0.02B.
Composing is about two-thirds of it, writing the file about a quarter; the channel pick and ties
take one pass each over the notes (3874be4 had them rescanning per voice: about 10% more).
`get_sound` adds under 2M for the settings. A whole `token_uri` is then roughly 0.51B at worst
(was 0.65B with v1.1), about 0.33B for a median Beast, 0.38B for the Warlock. Every Genesis Track
composes all six channels before the tier's channel filter, so the cheapest tracks cost more than
v1.1's genesis Warlock did (0.06B), and the most expensive cost less than v1.1's heaviest (0.47B).
Composing only the kept channels would cut that further but changes the music (each voice is
chosen against the voices already placed), so it would break parity with the lab.

`beast_token_uri_warlock_print` (ignored) prints a Warlock `token_uri`. Decoded, its page plays in
Chrome with the TinyChip timbres installed; the token-uri-inspector skill's `split_page.mjs` gives
back MIDI and `SETTINGS` byte-identical to `full_midi.js` and `encodeSettings` of
`offchain/beast-sound/onchain/tinychip/beast_synth_settings.json`.
