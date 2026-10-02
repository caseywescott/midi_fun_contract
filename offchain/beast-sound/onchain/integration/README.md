# Integrating the sound page into `beasts_nft`

`beasts_nft-sound.patch` is a ready-to-apply change to
[Provable-Games/beasts-v3](https://github.com/Provable-Games/beasts-v3), written against `main` at
`dea2d1b` (scarb 2.18.0, snforge 0.60.0):

```bash
git am beasts_nft-sound.patch          # or: git apply beasts_nft-sound.patch
scarb build && snforge test --max-n-steps 4294967295
```

The NFT no longer supplies Beast state. It hands the page its own address and the token ID, and the
page's MIDI provider reads everything it composes from directly.

## What it changes

| File | Change |
|---|---|
| `src/interfaces.cairo` | `set_sound_page_address` / `get_sound_page_address` on `IBeasts`. An `IMidiSoundPage` dispatcher interface: `token_uri(members, svg_b64, token_address, token_id)` |
| `src/lib.cairo` | `sound_page: ContractAddress` storage and an owner-only setter. `build_metadata_uri` calls `generate_metadata_with_sound` when the address is set and the unchanged `generate_metadata` when it is zero |
| `src/metadata_generator.cairo` | `generate_metadata_with_sound` builds the same components and hands the members (name, description, attributes), the SVG base64, `get_contract_address()` and the token ID to the page. `MetadataComponents.image` becomes `image_svg_b64`, and the attribute loop is shared |
| `src/sound_page_tests.cairo` | Four tests: off by default and byte-identical after an on/off round trip; delegates when set; owner-only setter; the page's members match the plain JSON minus `image` |

Mints, transfers and every other write path are untouched. Only the `token_uri` and
`animation_url` views change, and only after the owner sets the address. The NFT never calls the
provider: the page does, and the provider only calls the NFT's state getters
(`get_beast_rank`, `get_species_count`, `get_adventurers_killed`, `get_cached_stats`,
`get_death_mountain_address`), never `token_uri`, so metadata cannot recurse.

## Deploy (separate step, not done here)

1. Declare and deploy `BeastMidiProvider` (`contracts/beast_sound`, scarb 2.11.4). Constructor:
   the Beasts NFT address.
2. Declare and deploy `MidiSoundPage` (`onchain/cairo`). Constructor: the provider address.
3. Upgrade or redeploy `beasts_nft` with the patch.
4. As owner, call `set_sound_page_address(<MidiSoundPage>)`. Setting it back to `0` turns sound off.

Before mainnet:
- **Death Mountain address:** confirm the NFT's `get_death_mountain_address()` is set. Without it,
  genesis-species kills and scars compose as 0 and `get_live_state` reports them `Unavailable`. It
  is zero on both Sepolia deployments.
- **Token ID width:** confirm the token ID format is still 116 bits. The 180-bit format in draft
  PR #116 needs a new provider.

## Verified

- **Their suite:** with the patch, 237 tests pass, 1 is ignored and none fail (their tests plus the
  4 new ones). `scarb fmt --check` is clean.
- **Size:** the `beasts_nft` class grows from 32,753 to 33,046 Sierra felts (+0.9%), and its CASM
  from 74,062 to 74,927 felts against the 81,920 limit.
- **End to end on devnet** (`e2e_devnet.mjs`): the patched NFT with its real art providers, the
  real `BeastMidiProvider` and `MidiSoundPage`, and beasts-v3's mock Death Mountain. That mock
  asserts the `dungeon` key is its own address, the Beasts convention the provider follows. For a
  genesis token and two minted Beasts:
  - **Sound off:** `token_uri` is byte-identical before and after turning sound on and off again.
  - **Sound on:** valid JSON. Name, description, attributes and `image` are identical to the
    sound-off output, with `animation_url` added.
  - **MIDI:** the embedded MIDI equals the provider's `get_midi` and the JS engine's score for the
    live state the provider reports.
  - **Live-state changes:** changing Death Mountain state (40 kills and 9 collects, then 200 and
    64) changes the music on the next `token_uri`, and it matches the engine again.
  - **Playable:** two of those `token_uri`s, exactly as the NFT returned them, pass
    `browser-check.mjs` offline. The art shows, the MIDI plays at its exact tempo with the chip lead
    and drums, stop, restart and the loop work, and no request is made
    (`../browser-check.report.jsonl`).
  - **Cost:** L2 gas and sizes are in `../README.md`. Sound on costs 1.45–1.84B L2 gas against
    1.71–1.86B for today's sound-off `token_uri`.

```bash
starknet-devnet --seed 42 --port 5056 --accounts 1 --initial-balance 1000000000000000000000000000
# in the patched beasts-v3 checkout: scarb build, then CASM for the classes it declares:
#   universal-sierra-compiler compile-contract --sierra-path <class>.contract_class.json --output-path <class>.compiled_contract_class.json
#   (beasts_nft, the four art providers, and unittest_mock_death_mountain.test → <mock casm>)
E2E_URI_DIR=/tmp/uris STARKNET_JS=<node_modules/starknet> node onchain/integration/e2e_devnet.mjs \
  http://127.0.0.1:5056 <account> <private_key> <beasts-v3>/target/dev/ <mock casm>
PLAYWRIGHT_CORE=<node_modules/playwright-core> node onchain/browser-check.mjs /tmp/uris/*.txt
```

## Not wired

- **Sound drop:** every token gets sound once the address is set. To gate non-genesis Beasts by
  the sound drop (`beast_has_sound`), check the roll before calling the page.
- **Metadata refresh events:** setting the address changes every token's metadata, but no ERC-4906
  batch event is emitted.
