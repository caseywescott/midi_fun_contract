# Beast Sound launch music

This change adds the reviewed Sound Checks and Satori arrangement within the existing Composer/Manager split. The listening page is [Beast Sound Check](https://provable-games.github.io/beast-sound-check/).

- All 75 original species receive varied Sound Checks: individual contours, rhythms, tempos and family presets. Unnamed checks warm up the written Species Song's mode/key, including the Harpy/Pegasus swap. The selected original Cyclops sequence is an explicit C-major exception.
- Cyclops 64 uses the complete original #504 sequence: eight programs (34–41), 72 notes and four distinct performances. Written preserves the exact original MIDI/settings; Mega accelerates it, Portato shortens gates, and Mega/accent adds emphasis while retaining all eight timbres. See [implementation details](cyclops-504/IMPLEMENTATION.md).
- Satori 44 uses the original #411 Species Song: A Aeolian, 120 BPM and 72 seconds. Written preserves its exact MIDI and untrimmed settings. Agony Bane (name 1) derives a distinct C-Aeolian, lower-register rhythmic interpretation. Both use Casey's full Mega/Echo arranger and corresponding settings banks. See [named composition and effects](satori-411/NAMED-VARIATION.md).

The shared recipe remains independent of a token's name. Named tracks retain Casey's existing species-theme/name-treatment model. Existing unmarked Satori recipes keep their interpretation; the new arrangement requires both authored markers. Existing input wire versions, interfaces and Manager storage remain intact. Monthly editions retain their current style engines.

The canonical implemented Check table is `offchain/beast-sound/src/sound_check_catalogue_data.js`; `scripts/check_catalogue.mjs` generates its compact Cairo counterpart. The table includes the final contour edits; superseded draft pairings remain available in staging history. The independent Satori oracle uses the retained original lab generator and an unmodified Casey arranger pinned to `cdcad0a`.

## Validation and size

The review fixes make every new Satori route use the same authored base before applying purchase treatment and drift once. Legacy Genesis/Name/seeded calls and the JS preview now agree with the stored-input route; legacy provider settings include the authored bank. `bought_song_inputs` retains both authored markers. Edition generators deliberately retain the shipped procedural species genomes.

For general Sound Checks, a recipe's supplied family selects a compatible installed normal preset when it differs from the catalogue species family; its curated phrase remains. Canonical pairings and Mega voices are unchanged. Catalogue generation validates every packed field, including cadence length and bit widths. CI builds all four production contract classes and rejects missing, malformed or oversized artifacts. Superseded draft pairing exports were removed; the original generator used by the independent oracle remains.

With Scarb 2.21.0 and Foundry 0.64.1:

- **143 JavaScript tests** passed, including generator and size-gate mutation tests. Catalogue/384-case fixture freshness, original #411 reproduction, formatting and unchanged lockfile checks pass.
- Non-ignored Cairo suites pass: **369 composer, 77 contracts, 28 inputs, 34 MIDI and 38 MIDI contracts**. All **154 ignored Composer fixtures** were then run separately, followed by all **13 JS/Cairo comparators**, including 150/150 drift tracks, 150/150 Genesis tracks, 150/150 named tracks, 150/150 seeded tracks, 225/225 checks and the edition matrices. The 11 optional contract benchmark/capture fixtures are separate from this completed Composer parity gate.
- A separate bench workspace executed the actual compiled production `BeastPureComposer` with `--no-optimization`: **1,635 matrix cases plus 36 mixed-family cases** passed. Every matrix MIDI byte/settings hash matches JS, and all **600 canonical lab samples plus 16 explicit authored references** are unchanged from approved source `4a16c58`. The matrix has 1,635 distinct case IDs and 1,599 distinct parameter payloads.
- Production sizes are **69,882** (`BeastMidiProvider`), **22,747** (`BeastSoundComposer`), **17,383** (`BeastPureGenerator`) and **81,920 / 81,920** (`BeastPureComposer`) CASM felts. There is **zero spare headroom**. The Pure Composer compiled artifact SHA-256 is `55e03473d99bd4642ffb2554dca47f11c346054f17129d3c769b0fe7d011e42c`.

The production-class capture executes commit `91557269a17cc5e7bd6411f8589790284d8a618e`; the complete ignored-parity gate executes `cebb41a4f206e5cda06149c13a51ee0ce44e9bbb`. The intervening change fixes only JS edition generation/reference coverage. Final test/comment/documentation changes preserve the captured production artifact, checked by a fresh build and hash comparison. These captures are not represented as executions of a later revision.

The four shared `TrackWriter` `#[inline(never)]` annotations are retained after a paired 47-case benchmark. On original PR head `61379cb`, removing them grows Pure Composer from 81,918 to 83,933 felts. Removal saves 2.48–4.79% gas for checks, 0.79–1.81% for ordinary pure Songs, 4.48–6.08% for authored Satori, 0.84–1.67% for legacy Beast calls and 7.85–7.86% for Scale calls (119,250 Sierra gas). Percentages use the outlined version as denominator; these measure the annotation decision on `61379cb`, not final-head gas. Both variants preserve complete serialized output, with two identical measurements each and production artifact checks. See [the benchmark commands](../../bench/README.md#reproduce-the-pr34-trackwriter-tradeoff). This measured call overhead is the tradeoff for fitting the class without adding another writer API.

Useful checks from the repository root:

```sh
npm ci --prefix offchain/beast-sound
npm test --prefix offchain/beast-sound
node scripts/check_catalogue.mjs --check
node scripts/check_catalogue_parity.mjs --check
node docs/sound-check-scale-plan/satori-411/reproduce-411.mjs
scarb fmt --check
scarb test -p midi
scarb test -p midi_contracts
scarb test -p beast_composer_inputs
scarb test -p beast_composer
scarb test -p beast_contracts
python3 scripts/verify_music_parity.py --out /tmp/beast-music-parity
scarb --profile dev build -p beast_contracts
node scripts/check_production_size.mjs target/dev
git diff --exit-code Scarb.lock
```

See `TESTING.md` for the complete ignored-parity gate. Source, fixtures and the new music remain under this repository's MIT license.

## Production integration

Publishing the code does not select new stored tracks. Beasts V3 must pin the approved engine, regenerate its matching fixtures and publish/select the revised shared recipes. In particular, newly authored Cyclops recipes encode the original 175 BPM tempo; older recipes retain their stored tempo. The Species Song preset policy and rank-one preset controls remain separate Manager changes.
