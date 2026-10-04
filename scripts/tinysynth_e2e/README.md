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

Results at 973f4cf (L2 gas):

| Test | Gas |
|---|---|
| `beast_build` (fixtures only: settings Serde, two MIDI files) | 3.4M |
| `beast_settings_validate` | 4.8M (1.5M over the build) |
| `beast_encode_settings` (4,179 bytes of `SETTINGS`) | 27.0M |
| `beast_lc_midi_segment_warlock` (1,246-byte MIDI, library call) | 85.1M |
| `beast_lc_midi_segment_heaviest` (5,066-byte MIDI) | 140.0M |
| the same with the class's `default_settings()` | 75.1M |
| `beast_token_uri_heaviest` (Beasts-layout `token_uri`, crate functions) | 146.9M |

The settings add about 65M to the heaviest Beast's segment. The provider's `get_midi` for that Beast
is about 478M (beast_sound `heaviest_score_matches_composer`), so a whole `token_uri` is roughly
0.63B at worst.

`beast_token_uri_warlock_print` (ignored) prints a Warlock `token_uri`. Decoded, its page plays in
Chrome with the TinyChip timbres installed; the token-uri-inspector skill's `split_page.mjs` gives
back MIDI and `SETTINGS` byte-identical to `full_midi.js` and `encodeSettings` of
`offchain/beast-sound/onchain/tinychip/beast_synth_settings.json`.
