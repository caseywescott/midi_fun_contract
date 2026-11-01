# Beast Sound launch music

This change adds the reviewed Sound Checks and Satori arrangement within the existing Composer/Manager split. The listening page is [Beast Sound Check](https://provable-games.github.io/beast-sound-check/).

- All 75 original species receive varied Sound Checks: individual contours, rhythms, tempos and family presets. Unnamed checks warm up the written Species Song's mode/key, including the Harpy/Pegasus swap. The selected original Cyclops sequence is an explicit C-major exception.
- Cyclops 64 uses the complete original #504 sequence: eight programs (34–41), 72 notes and four distinct performances. Written preserves the exact original MIDI/settings; Mega accelerates it, Portato shortens gates, and Mega/accent adds emphasis while retaining all eight timbres. See [implementation details](cyclops-504/IMPLEMENTATION.md).
- Satori 44 uses the original #411 Species Song: A Aeolian, 120 BPM and 72 seconds. Written preserves its exact MIDI and untrimmed settings. Agony Bane (name 1) derives a distinct C-Aeolian, lower-register rhythmic interpretation. Both use Casey's full Mega/Echo arranger and corresponding settings banks. See [named composition and effects](satori-411/NAMED-VARIATION.md).

The shared recipe remains independent of a token's name. Named tracks retain Casey's existing species-theme/name-treatment model. Existing unmarked Satori recipes keep their interpretation; the new arrangement requires both authored markers. Existing input wire versions, interfaces and Manager storage remain intact. Monthly editions retain their current style engines.

The canonical implemented Check table is `offchain/beast-sound/src/sound_check_catalogue_data.js`; `scripts/check_catalogue.mjs` generates its compact Cairo counterpart. The earlier [pairing sheet](pairings.csv) and [structured pairings](pairings.json) are authoring provenance; the implemented table records the final contour edits. The independent Satori oracle uses the retained original lab generator and an unmodified Casey arranger pinned to `cdcad0a`.

## Validation and size

The music, generator and test sources are byte-identical to qualified fork commit `4a16c58bf1738bcd3636f1e475a310b24ecbddc5`. This PR omits unused planning/audit exports and retains the original MIDI/settings, historical recipe and independent oracle fixtures.

- 89 JavaScript tests; 362 composer, 69 contracts, 28 inputs and 34 core MIDI tests passed.
- All 300 shared Sound Checks match full MIDI bytes and settings through a declared production-equivalent class.
- The Sound Lab's full matrix compared 1,635 actual Cairo outputs with the shipped adapter, including Species Songs, named songs, purchases, all 23 editions/styles, effects and boundary seeds. All 75 embedded Species Songs and 600 current Species/Check selections also match across the lab pages.
- With Scarb 2.21.0 and Foundry 0.64.1, the production-equivalent dev `BeastPureComposer` is **81,918 / 81,920 CASM felts**. Its compiled artifact SHA-256 is `14f9c465701bce6f42ce425f0812888303ff3f834bbfe5c447311b005fd02de9`. The two-felt margin requires rechecking the compiled size after source or toolchain changes.

Useful checks from the repository root:

```sh
npm ci --prefix offchain/beast-sound
npm test --prefix offchain/beast-sound
node scripts/check_catalogue.mjs --check
node scripts/check_catalogue_parity.mjs --check
node docs/sound-check-scale-plan/satori-411/reproduce-411.mjs
scarb fmt --check
scarb test -p midi
scarb test -p beast_composer_inputs
scarb test -p beast_composer
scarb test -p beast_contracts
git diff --exit-code Scarb.lock
```

Follow `TESTING.md` for the existing ignored parity fixtures. Source, fixtures and the new music remain under this repository's MIT license.

## Production integration

Publishing the code does not select new stored tracks. Beasts V3 must pin the approved engine, regenerate its matching fixtures and publish/select the revised shared recipes. In particular, newly authored Cyclops recipes encode the original 175 BPM tempo; older recipes retain their stored tempo. The Species Song preset policy and rank-one preset controls remain separate Manager changes.
