# beast_contracts

The Beast composer (`beast_composer`, engine v1) as Starknet contracts. It depends on two
libraries: `beast_composer` (`beasts/beast_composer`, the composer) and `midi` (`core/midi`, the
core MIDI types and interfaces it implements).

- **`BeastMidiProvider`** (`src/provider.cairo`): the production path, a Beasts V3 **sound
  manager**. It answers SRC5 `IBEASTS_SOUND_MANAGER_ID`, so the Beasts registry accepts it as a
  species' sound manager, and serves `ISoundManager::get_track_sound(token_id, track_number,
  block_number)`, which the Beasts renderer calls for a token's default track. It is also the only
  caller the NFT accepts for a token's sound mutations, which it forwards for its owner (the launch
  rollout) and, for `set_default_track` and `set_sound_mode`, for the token's owner. It keeps the
  generic `IMidiProvider` (`get_midi`, `get_midi_for`), `ISynthSettingsProvider::get_settings` and
  onchain-midi-player's `ISoundProvider::get_sound`, which serve the token's Species Song.
- **`BeastTrackComposer`** (`src/track_composer.cairo`): the composer as its own declared class,
  which the provider library-calls: the two do not fit in one class under Starknet's 81,920-felt
  CASM limit.
- **`BeastSoundComposer`** (`src/lib.cairo`): benchmark views that take a Beast and its live state
  as calldata.
- `src/beasts_v3.cairo`: the Beasts V3 interfaces and types the provider uses, declared locally
  (TEMPORARY until beasts-v3 is public; then a git dependency on `beasts_core` replaces it).

## BeastMidiProvider

Declare `BeastTrackComposer`, then deploy the provider with three constructor arguments: the
Beasts V3 NFT it serves, its owner and the `BeastTrackComposer` class hash. The NFT is fixed:
another collection or engine is another deployment. The constructor registers
`IBEASTS_SOUND_MANAGER_ID` (`0x1f268c5b361211a8650d5f3a862f3108067a38059a190fd26aef2ac3425e7b1`,
`selector!("beasts_sound_manager_v1")`); the species owner then sets the provider as the species'
sound manager with the registry's `set_sound_manager`.

### Tracks

A Beast has exactly three tracks. The NFT stores each as `TrackInputs { version, data }` and never
reads it; here a track is its version tag, with no data:

| Track | `version` | Plays |
|---|---|---|
| 0, Sound Check | `TRACK_SOUND_CHECK` (1) | The Beast's scale through each of its presets (the composer's track 0) |
| 1, Species Song | `TRACK_SPECIES_SONG` (2) | The Genesis Track, with the default swaps (the composer's track 1) |
| 2, Custom Name Track | `TRACK_CUSTOM_NAME` (3) | The species' theme in the special name's key and style (the composer's name track, `TRACK_SPECIAL_SONG`); a Beast without a special name plays its Species Song |

Each track composes from the Beast alone (`get_beast`), so a token stores only the version tag. A
version names the track whatever its index; the rollout appends them at indices 0, 1 and 2.

**Composition is unchanged.** For the same Beast and track, the MIDI is byte for byte the
composer's on `main`: `track_smf_bytes` of the Beast's composer inputs, and the Genesis Track
(`genesis_byte_array`) for the Species Song as written. No track reads live state (kills, rank):
the composer's tracks compose with the neutral live state, so the provider reads none.

`get_track_sound(token_id, track_number, block_number)` reads the track (`track_inputs`, which
rejects an unminted token and an index at or above `num_tracks`) and the Beast (`get_beast`), and
returns `TinySynthSound { midi, settings }`. `block_number` is the renderer's resolution of the
token's saved mode: `None` (Original) plays the track as written; `Some(n)` (Live asks for the
current block minus 10, AtBlock(n) for `n`) plays the composer's day of drift at block `n`
(`beast_composer::composition::drift`), from the hashes of its day's, week's and month's first
blocks. `n` must not be in the future (`block in the future`). The Sound Check never drifts.

It reverts for a token the NFT has not minted (the NFT's `ERC721: invalid token ID`), a track the
token does not have (`Sound: invalid track`), a stored track of another version
(`unknown track version`) or with data (`bad track data`), and a future block. The renderer calls
it through a safe dispatcher, so a revert leaves the card silent rather than broken.

### The Beast

The provider reads the Beast from the NFT (`get_beast(token_id: felt252)`, the 26-felt
`PackableBeast`), never from the token ID's bits, so a change of the Beasts V3 bit layout cannot
break it. The composer sees the species, special name, level, health, tier and type, and one sound
flag: `sound_effects` is a preset whose meaning the sound manager defines, and here
`SOUND_PRESET_MEGA` (1) plays the mega sound (the shiny arrangement and the mega leads) while every
other value plays the normal sound. The original species' Genesis Beasts are minted with sound
preset 1. `visual_effects`, the image provider's preset, does not change the sound.

### Entry points

| Entry point | Who | What |
|---|---|---|
| `get_track_sound(token_id, track_number, block_number)` | anyone | The track's `TinySynthSound` (above) |
| `get_sound(token_id: u256)` | anyone | `TinySynthSound` of the token's Species Song as written (onchain-midi-player's `ISoundProvider`), whether or not the token has tracks |
| `get_midi(token_id: u256)`, `get_midi_for(token_address, token_id: u256)` | anyone | Its MIDI (`IMidiProvider`); `get_midi_for` first checks `token_address` (`unsupported collection`) |
| `get_settings(token_id: u256)` | anyone | Its settings, without composing (`ISynthSettingsProvider`) |
| `get_collection()`, `get_engine_version()`, `get_composer_class()` | anyone | The NFT, `1`, the composer class |
| `supports_interface(id)` | anyone | SRC5: `IBEASTS_SOUND_MANAGER_ID` and `ISRC5_ID` |
| `set_default_track(token_id, track_number)` | the token's owner | Forwards the NFT's `set_default_track` |
| `set_sound_mode(token_id, mode)` | the token's owner | Forwards the NFT's `set_sound_mode`: Live, Original or AtBlock(n), `n` not in the future |
| `batch_update_track_capacity(token_ids, new_capacity)` | owner | `update_track_capacity` for every token |
| `batch_add_track(token_ids, version)` | owner | Appends track `version` (one of the three) to every token |
| `batch_set_default_track(token_ids, track_number)` | owner | `set_default_track` for every token |
| `register_interface(interface_id)` | owner | Registers an SRC5 ID, for an instance upgraded from a class whose constructor did not register `IBEASTS_SOUND_MANAGER_ID` |
| `set_composer_class(class_hash)` | owner | Replaces the composer class |
| `upgrade(class_hash)`, `transfer_ownership`, `renounce_ownership` | owner | OpenZeppelin Upgradeable and Ownable |

Every Beasts token ID is a `felt252`; only the inherited `IMidiProvider`, `ISynthSettingsProvider`
and `ISoundProvider` take a `u256`, and reject one at or above the field prime
(`invalid token id`). The provider only calls state getters on the NFT, never `token_uri`, and
caches nothing.

### Launch rollout

The owner drives the rollout while it owns the provider (the NFT accepts sound mutations only from
the species' registered sound manager):

1. `batch_update_track_capacity(ids, 3)`, `batch_add_track(ids, TRACK_SOUND_CHECK)`: every Beast
   gets the Sound Check as track 0, its default, for about 24 hours.
2. `batch_add_track(ids, TRACK_SPECIES_SONG)`, `batch_set_default_track(ids, 1)`: the Species
   Song.
3. `batch_add_track(ids, TRACK_CUSTOM_NAME)`, `batch_set_default_track(ids, 2)`: the Custom Name
   Track.

`renounce_ownership` ends the rollout entry points with upgrades. Every NFT mutation emits two
events (its own and an ERC-4906 `MetadataUpdate`) and Starknet caps a transaction at 1,000 events;
the batch entry points emit none of their own. So one transaction holds about:

| Calls per token in the transaction | Events per token | Tokens per transaction |
|---|---:|---:|
| one batch call (for example `batch_set_default_track`) | 2 | at most 500 |
| two (`batch_add_track` and `batch_set_default_track` in one multicall) | 4 | at most 250 |
| three (capacity, track and default) | 6 | at most 166 |

Gas and steps bound a batch too: size it by a dry-run estimate. A batch reverts as a whole if the NFT
rejects any token.

### Upgrading an earlier instance

An upgrade does not rerun the constructor. An instance upgraded from the earlier provider class
(constructor `(collection, owner)`) needs its owner to call `set_composer_class` with the declared
`BeastTrackComposer` and `register_interface(IBEASTS_SOUND_MANAGER_ID)` before a species can use
it.

## BeastSoundComposer

Every view takes the Beast (`PackableBeastV3`: species, prefix, suffix, level, health, shiny,
animated, tier, type) and rejects one out of range (`invalid tier`, `invalid affix combo`, ...).

| View | Returns |
|---|---|
| `has_sound(beast)` | Sound drop result (salt + bps set at deploy) |
| `get_composition_params(beast, live)` | Bounded musical parameters |
| `get_music_state_hash(beast, live)` | Renderer cache key |
| `get_score_hash(beast, live)` | Commitment to the full score |
| `get_score_notes(beast, live)` | BSN1 compact note stream (7 bits per note), same packing. `bsnToMidi` in `offchain/beast-sound/src/bsn.js` rebuilds the exact MIDI file |
| `get_score_midi(beast, live)` | Standard MIDI File bytes: `[byte_len, 31-byte chunks…]`, byte-identical to the browser engine |

## BSN1 layout

```
header : version 8 | tempo_us 24 | grid_ticks 12 | duration_ticks 12 | articulation 3
         | base_velocity 7 | velocity_ceiling 7 | run_count 8          (81 bits)
run    : voice 4 | start_beat 12 | note_count 8                        (24 bits)
note   : key 7
```

Runs are in emission order; a run whose voice is not above the previous run's voice starts a new
section, which resets the accent counter. Velocity = base, or min(base + 20, ceiling) on every 4th
note of a section when articulation is accent.

## Build and test

Needs Cairo 2.21 (scarb 2.21.0, the root `.tool-versions`); `onchain_midi_types` needs 2.20 or
later. From the repository root (artifacts land in the workspace `target/dev`, named
`beast_contracts_<Contract>`):

```bash
scarb build -p beast_contracts   # CASM: BeastTrackComposer 75,392 felts, BeastMidiProvider 13,566
                                 # (Starknet limit 81,920); Sierra 38,376 and 5,318
scarb test -p beast_contracts    # the provider on a mock Beasts V3 NFT: the three tracks against the
                                 # composer's bytes, drift, the rollout, the token owner's entry
                                 # points, SRC5, rejections, get_sound, and onchain-midi-player's
                                 # validate on the settings
```

## `get_track_sound` gas

L2 (Sierra) gas of one call, nested calls included (the mock NFT's reads and the library call),
from the ignored `gas_probe_*` tests (`snforge test gas_probe --include-ignored
--tracked-resource sierra-gas --trace-components contract-name gas` in this package; scarb 2.21.0,
snforge 0.64.1, no transaction overhead). Live is a day of drift at block 130,100.

| Beast | Track 0, Sound Check | Track 1, Species Song, Original | Track 1, Live | Track 2, Custom Name Track, Original | Track 2, Live |
|---|---:|---:|---:|---:|---:|
| Mega #32 (the largest Genesis Track), special name 13/6 | 8.3M | 162.6M | 170.9M | 184.1M | 184.4M |
| Sorrow Peak Warlock (#1, normal) | 7.0M | 132.5M | 137.1M | 139.2M | 139.4M |

The provider's own share is about 2.4–3.3M: `track_inputs` (0.15M on the mock), `get_beast`
(1.06M on the mock, which stores the Beast in 26 slots), the settings and the library call. The
Species Song as written composes in the class's Genesis Track copy (`genesis_byte_array`); with
drift, and for the other tracks, the general composer.

## BeastMidiProvider gas (`bench/`, the previous class)

The bench (`bench/`) still measures the previous provider class (token ID decoding, Death Mountain
mocks) and needs an update for this one. Its numbers, from `bench/snapshots/baseline-25be776.json`
(scarb 2.21.0 and snforge 0.64.1 on the classes `scarb build` made; mock NFT and Death Mountain; no
transaction overhead):

| Call | Gas |
|---|---:|
| `get_midi`, the 150 Genesis Tracks (every species, normal and shiny) | 61.2M–164.1M, median 110.3M |
| `get_midi`, lightest (#21) / heaviest (#28 shiny) | 61.2M / 164.1M |
| `get_sound` | 0.58–0.71M more than `get_midi` |
| `get_settings` | 0.57–0.74M |
| `get_live_state` | 0.50–0.82M |

The tables below are earlier devnet measurements of the v1.1 live-state path.

## BeastMidiProvider cost (starknet-devnet 0.10.2, 2 Oct 2026)

L2 gas from `starknet_estimateFee`, with the real patched Beasts NFT (see
`offchain/beast-sound/onchain/integration`):

| Beast state | MIDI | `get_midi` | `get_live_state` |
|---|---:|---:|---:|
| Fresh (0 kills, 0 scars) | 816 B | 30–31M | 2.1–2.6M |
| 40 kills, 8 scars | 2,991 B | 108–109M | |
| 200 kills, 63 scars (largest score) | 3,716 B | 134–135M | |

## BeastSoundComposer cost (starknet-devnet 0.10.0, 1 Oct 2026)

L2 gas per call, including ~1M of fixed transaction overhead from the estimate:

| Beast | params | state hash | score hash | score notes (BSN1) | score MIDI |
|---|---:|---:|---:|---:|---:|
| Tier 5, fresh | 1.2M | 1.1M | 2.9M | 5.6M (3 felts) | 14M (7 felts) |
| Sorrow Peak Warlock (mainnet rank-1 Warlock) | 1.2M | 1.1M | 26M | 49M (8 felts) | 145M (52 felts) |
| Tier 1, 3 sections | 1.3M | 1.2M | 37M | 71M (11 felts) | 212M (76 felts) |
| Heaviest: Tier 1, 4 voices + countersubject, 5 sections | 1.4M | 1.3M | 63M | 119M (17 felts) | 350M (122 felts) |

## Reproduce

```bash
# needs: npm i starknet @scure/starknet
node scripts/deploy_and_bench.mjs <rpc> <account> <private_key>   # declare + deploy + calls
node scripts/measure_gas.mjs <rpc> <account> <contract>             # exact L2 gas via estimateFee
```
