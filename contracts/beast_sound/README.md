# BeastSoundComposer

The Koji Beast composer (`koji::composition::beast_v3_sound`) as a Starknet contract. Every view
is a pure function of a Beasts V3 token ID plus live state. In this build the live state is passed
as calldata; the production `BeastSound` contract reads it from the Beasts NFT and Summit.

| View | Returns |
|---|---|
| `has_sound(token_id)` | Sound drop result (salt + bps set at deploy) |
| `get_composition_params(token_id, live)` | Bounded musical parameters |
| `get_music_state_hash(token_id, live)` | Renderer cache key |
| `get_score_hash(token_id, live)` | Commitment to the full score |
| `get_score_notes(token_id, live)` | BSN1 compact note stream (7 bits per note), same packing. `bsnToMidi` in `web/beast_sound/engine.js` rebuilds the exact MIDI file |
| `get_score_midi(token_id, live)` | Standard MIDI File bytes: `[byte_len, 31-byte chunks…]`, byte-identical to the browser engine |

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

## Build

```bash
scarb build   # CASM 25,139 felts (Starknet limit 81,920)
```

## Measured execution cost (starknet-devnet 0.10.0, 1 Oct 2026)

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
