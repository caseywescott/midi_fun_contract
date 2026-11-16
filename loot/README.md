# Loot Dungeon Sound: Cairo release notes

Music for the 30 Loot Dungeon Beasts (public ids **78–107**) onchain, byte for byte the Loot lab at
loot_dungeon_sound **9103b11** with the Kankyo FM bank at midi_fun_contract **0f2d0ba** (sampler fix
e27ac75). Scarb workspace at the repo root (scarb 2.21.0, snforge 0.64.1).

Built on Beast Sound **v1.1.0**, pinned by tag (`midi`, `beast_composer`, `beast_composer_inputs` from
midi_fun_contract `v1.1.0`) and never modified. This branch is standalone and does not contain midi_fun_contract
`main`; Species and Name Songs are played by the v1.1.0 release's own `BeastPureComposer` class.

## Classes

| Class | What it does | Storage | CASM felts (limit 81,920) |
|---|---|---|---|
| `LootPureComposer` | Monthly Track Editions, Rounds and Sound Checks: composes the track and writes the lab's band (programs), the Round's +7 lift and the volumes in place (style MIX, lead turn-downs and drops, the accompaniment's drops and octave-lower tracks, TOP_SOFT on the highest voice). A `Song` reverts here. | none | 79,128 |
| `LootMidiProvider` | Every track behind one ABI (`ILootMidiProvider`): Editions/Rounds/Checks library-call `LootPureComposer`; Species/Name Songs build the Beast's song inputs and library-call the pinned `BeastPureComposer`, then add the band, a Name Song's +12 and lead pool, the song volumes, a Name Song's softer kick and TOP_SOFT. OpenZeppelin Ownable + Upgradeable; `set_classes`. | class hashes, pack address, owner | 33,600 |
| `LootFmPack` | The FM sound pack that plays these files: one gzip + base64 script (31.5 KB raw, 13.8 KB gzip), `pack()`, `chunk(i)`, `pack_sha256()`. | none (data in code) | 5,505 |
| `BeastPureComposer` | Not ours: Beast Sound v1.1.0's class `0x07eb6480204a1367381b782116e6a3d6dedd8fb8b03535ca453e5c681002eb63`, used as is. `loot/deps/beast_contracts` (v1.1.0's source verbatim, test only) builds to this hash. | none | 81,920 |

## ABI

`compose(inputs: LootInputs, sound_effects: u8) -> ByteArray` and
`compose_drift(inputs, sound_effects, drift: DriftInputs) -> ByteArray` return a Standard MIDI File as the
lab plays it (each channel's program is its band instrument in the FM pack).

- `LootInputs`: `Song { species, name }` (name 0 = Species Song, 1..1242 = Name Song),
  `Edition { species, edition, purchase }` (edition from 1, purchase 1..2^32 − 1),
  `Round { species, purchase }` (0 = the species' own), `SoundCheck { species, take }` (0 = its own).
  `species` is the public id, 78..107; anything else reverts ('not a Loot Beast').
- `sound_effects`: v1.1's, 0 written, 1 mega, 2 echo, 3 mega + echo; 4+ revert. Songs get v1.1's whole
  performance (the Beast class plays them); Editions, Rounds and Checks take the mega sound only.
- `drift`: v1.1's `DriftInputs` (day from 1, block hashes of the day, week, month). Day 1 is as written.
  Sound Checks do not drift.

### Ids: `musical_id`

Public and contract ids are 78–107 (loothero's mapping, PR #35). Each Beast keeps the soundtrack that was
written for it at the provisional ids 76–105: `musical_id(id) = id − 2` feeds every seed, theme, band,
drift and the Beast id given to `BeastPureComposer`, exactly where the lab calls `musicalId`. The species
table stores both (`LootSpecies.music`).

## Deploy

1. Make sure `BeastPureComposer` v1.1.0 (`0x07eb6480…02eb63`) is declared on the network (it is part of
   the Beast Sound v1.1.0 release; if not, declare it from `loot/deps/beast_contracts`, which builds to
   the same hash).
2. Declare `LootPureComposer` (no deployment needed: it is only library-called).
3. Declare and deploy `LootFmPack` (no constructor arguments).
4. Declare and deploy `LootMidiProvider` with constructor
   `(composer_class: ClassHash, song_class: ClassHash, pack: ContractAddress, owner: ContractAddress)` =
   (`LootPureComposer`'s class hash, `0x07eb6480…02eb63`, the `LootFmPack` address, the owner).

The owner can `set_classes(composer_class, song_class, pack)` and `upgrade(class_hash)`;
`renounce_ownership` ends both for good.

## Gas (l2, approximate)

| Call | Typical | Range seen in tests |
|---|---|---|
| Edition, composer alone | 77M | 33–119M |
| Edition through the provider (test harness incl.) | ~165M | 109–276M |
| Round through the provider | ~250M | 177–300M (heaviest: late drift days, full ornaments) |
| Sound Check through the provider | ~55M | 49–74M |
| Species / Name Song through the provider | ~190M | 128–354M (mega + echo Name Song ~740M) |

Provider figures come from `front_tests` and include the test's deploy and checksum work, so they overstate
a bare call somewhat.

## Parity (all identical to the lab at 9103b11)

| What | Cases |
|---|---|
| Editions | 96 |
| Rounds | 116 |
| Sound Checks | 100 |
| Species and Name Songs (raw and played, drift) | 49 |
| Band choices (editions, songs, name songs, rounds; drift) | 525 |
| Rounds/Checks written in place vs orchestrated | 6 |
| Deployed provider vs the lab's playback (every kind, the edition mix, TOP_SOFT) | 39 |
| Volume table vs `Math.round(v * f − d)` | 598,528 |
| FM pack renders vs the bank | 415 takes + 121 extra, sampler buffers at 3 rates |
| JS tests (`offchain/loot-sound`) | 37 |

How to run them: the root README's "Cairo (onchain)" section. Run Cairo only through
`sh scripts/cairo_run.sh` (one at a time, memory watchdog); each parity fixture in `loot_composer` is
behind its own feature (`--no-default-features --features rounds_fx`, ...).
