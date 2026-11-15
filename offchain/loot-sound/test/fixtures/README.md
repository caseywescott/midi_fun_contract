These authorities were captured from the untouched `loot-dungeon-sound` snapshot
`965a7824f7b8385a9f0829df49451911640bdd1b`, before the species-ID correction.
Do not regenerate them from the corrected implementation.

`soundtrack-965a782.json` captures the original published HTML's actual `track()`:
30 species × regular/mega × 10 cases = 600 MIDI-length/SHA-256, orchestration and
synth-settings records. Cases include both kinds of Song, two names, original and
purchased Checks/Rounds/Editions, and drift days 45 and 100. `lab-track.mjs` loads
the bundled engine in Node and exercises the page's actual private Beast mapping,
purchase seed, drift, band and `track` code, without browser/audio APIs.

`source-soundtrack-965a782.json` separately captures the original branch's source
Checks/Rounds/Editions: 30 species × regular/mega × 6 cases = 360 complete MIDI
length/SHA-256 and band records. Its drift inputs come from the pinned Beasts
v1.0.1 reference (`8d1d96e664bd35d468e66830324ef25a42fd58bd`).

The distinction matters: the original checked-in HTML has an older 12-style
bundle, while the original source and Cairo have 15 styles. This correction
preserves each existing soundtrack independently; it does not silently upgrade
the published bundle. The existing Cairo fixtures likewise retain their original
MIDI checksums, purchase seeds, drift values and band expectations; only their
public species arguments move by two.

To independently reproduce an authority, check out that exact original commit,
iterate the stored cases against its unmodified modules/page and compare every
hash and band. Public index `b` is the stable catalogue position: original ID
`76 + b` becomes canonical ID `78 + b`. Run the regression suite from a fresh
checkout with `npm test` in `offchain/loot-sound`; no reference checkout or npm
dependencies are needed to execute these frozen cases.
