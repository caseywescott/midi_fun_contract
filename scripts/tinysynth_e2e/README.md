# Beast Sound through onchain-midi-player, end to end

Runs `BeastMidiProvider`'s output (the `get_settings` Serde and the self-contained `get_midi` bytes)
through loothero's class in a copy of its repo, as the Beasts NFT's `token_uri` would.

```bash
git clone https://github.com/Provable-Games/onchain-midi-player /tmp/ots_e2e
git -C /tmp/ots_e2e checkout e1b0d54757d5545824fffb6c9913bc673f6c5a9e   # the rev midi_provider pins (scarb 2.20.1, snforge 0.64.0)
(cd offchain/beast-sound && npm install)                                  # fixtures.mjs imports the JS engine
node scripts/tinysynth_e2e/fixtures.mjs /tmp/ots_e2e/tests/beast_e2e_fixtures.cairo
cp scripts/tinysynth_e2e/test_beast_e2e.cairo /tmp/ots_e2e/tests/
printf 'mod beast_e2e_fixtures;\nmod test_beast_e2e;\n' >> /tmp/ots_e2e/tests/lib.cairo
(cd /tmp/ots_e2e && snforge test test_beast_e2e)
```

Results at e1b0d54 (within 0.1M of e4e6108's; the bracketed figures were not re-measured), L2 gas: composer v1.1 MIDI, every voice on the
Triangle Lead, 12 timbres with the 50% pulse and the NES triangle as sampled waves (928 bytes of
`SETTINGS`, reverb 30). In brackets, the same with the chip waves approximated by built-in waves
(894 bytes):

| Test | Gas |
|---|---|
| `beast_build` (fixtures only: settings Serde, two MIDI files) | 1.6M (1.6M) |
| `beast_settings_validate` | 1.1M (1.1M) |
| `beast_encode_settings` | 6.2M (5.8M) |
| `beast_lc_midi_segment_warlock` (1,501-byte MIDI, library call) | 38.0M (37.4M) |
| `beast_lc_midi_segment_heaviest` (8,236-byte MIDI) | 135.1M (134.8M) |
| the same with the class's `default_settings()` | 120.5M |
| `beast_direct_midi_segment_heaviest` (crate function, no library call) | 130.1M (129.8M) |
| `beast_token_uri_heaviest` (Beasts-layout `token_uri`, crate functions) | 148.2M (147.9M) |

One call to the provider's `get_midi` (cairo-test estimate, Cairo 2.20.1; 2.11.4 in brackets) is
about 0.43B for the heaviest Beast (0.51B), 0.25B for a named rank-1 Warlock (0.29B) and 0.06B for
a genesis Warlock (0.07B); `get_sound` adds under 1M for the settings. With `midi_segment`, a whole
`token_uri` is then roughly 0.6B at worst, 0.3B for the named Warlock and 0.1B for the genesis one.
(`heaviest_score_matches_composer` composes three times: `get_midi`, the composer and
`get_midi_for`.) All 400 cached gallery Beasts' v1.1 files pass onchain-midi-player's `check_midi`
(mean 1,881 bytes, largest 8,648; checked at 973f4cf).

`beast_token_uri_warlock_print` (ignored) prints a Warlock `token_uri`. Decoded, its page plays in
Chrome with the TinyChip timbres installed; the token-uri-inspector skill's `split_page.mjs` gives
back MIDI and `SETTINGS` byte-identical to `full_midi.js` and `encodeSettings` of
`offchain/beast-sound/onchain/tinychip/beast_synth_settings.json`.
