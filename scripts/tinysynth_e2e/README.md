# Beast Sound through onchain-tinysynth, end to end

Runs `BeastMidiProvider`'s output (the `get_settings` Serde and the self-contained `get_midi` bytes)
through loothero's class in a copy of its repo, as the Beasts NFT's `token_uri` would.

```bash
git clone https://github.com/Provable-Games/onchain-tinysynth /tmp/ots_e2e   # checked at 973f4cf (scarb 2.20.1, snforge 0.64.0)
node scripts/tinysynth_e2e/fixtures.mjs /tmp/ots_e2e/tests/beast_e2e_fixtures.cairo
cp scripts/tinysynth_e2e/test_beast_e2e.cairo /tmp/ots_e2e/tests/
printf 'mod beast_e2e_fixtures;\nmod test_beast_e2e;\n' >> /tmp/ots_e2e/tests/lib.cairo
(cd /tmp/ots_e2e && snforge test test_beast_e2e)
```

Results at 973f4cf (L2 gas): composer v1.1 MIDI, every voice on the Triangle Lead, 12 timbres (894
bytes of `SETTINGS`, reverb 30):

| Test | Gas |
|---|---|
| `beast_build` (fixtures only: settings Serde, two MIDI files) | 1.6M |
| `beast_settings_validate` | 1.1M |
| `beast_encode_settings` | 5.8M |
| `beast_lc_midi_segment_warlock` (1,501-byte MIDI, library call) | 37.4M |
| `beast_lc_midi_segment_heaviest` (8,236-byte MIDI) | 134.8M |
| the same with the class's `default_settings()` | 120.5M |
| `beast_token_uri_heaviest` (Beasts-layout `token_uri`, crate functions) | 143.5M |

The provider's `get_midi` for the heaviest Beast is about 1.0B (beast_sound
`heaviest_score_matches_composer` composes twice: 2.05B), so a whole `token_uri` is roughly 1.15B at
worst; a named rank-1 Warlock about 0.6B, a genesis Warlock about 0.17B. All 400 cached gallery Beasts'
v1.1 files pass onchain-tinysynth's `check_midi` (mean 1,881 bytes, largest 8,648).

`beast_token_uri_warlock_print` (ignored) prints a Warlock `token_uri`. Decoded, its page plays in
Chrome with the TinyChip timbres installed; the token-uri-inspector skill's `split_page.mjs` gives
back MIDI and `SETTINGS` byte-identical to `full_midi.js` and `encodeSettings` of
`offchain/beast-sound/onchain/tinychip/beast_synth_settings.json`.
