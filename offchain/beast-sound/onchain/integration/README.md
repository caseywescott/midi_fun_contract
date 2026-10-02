# Integrating Beast Sound into `beasts_nft`

`beasts_nft-sound.patch` is a ready-to-apply change to
[Provable-Games/beasts](https://github.com/Provable-Games/beasts) (written against `main` at
`ae3fa8d`):

```bash
git apply beasts_nft-sound.patch      # or: git am beasts_nft-sound.patch
scarb build && snforge test --max-n-steps 4294967295
```

## What it changes

| File | Change |
|---|---|
| `src/interfaces.cairo` | `BeastSoundInputs` struct and an `IBeastSoundPage` dispatcher interface; `set_sound_page_address` and `get_sound_page_address` on `IBeasts` |
| `src/lib.cairo` | `sound_page: ContractAddress` storage, an owner-only setter, and `generate_metadata` receiving `sound_page` and `beast_counts(beast.id)` |
| `src/metadata_generator.cairo` | `sound_page == 0` gives today's output, byte for byte. Otherwise it passes the JSON members (name, description, attributes) and the SVG base64 to the sound page and returns its `token_uri`. `MetadataComponents.image` becomes `image_svg_b64`, and the attribute loop is shared |
| `src/sound_page_tests.cairo` | Three tests: defaults to off, delegates when set, owner-only setter |

Mints, transfers and every other write path are untouched. Only the `token_uri` and
`animation_url` views change, and only after the owner sets the address.

## Deploy

1. Declare and deploy the 9 library module contracts from `../cairo`, in this order:
   `BeastSoundModuleCore`, `Beast`, `Music`, `Midi`, `Synth`, `Play`, `Fx`, `Api`, `Page`. Each is
   stateless, with no constructor arguments. Then deploy `BeastSoundPage` with their addresses, in
   that order, as its constructor argument. The module list is fixed for the page's life: a new
   library version means a new page contract.
2. Upgrade or redeploy `beasts_nft` with the patch.
3. As owner, call `set_sound_page_address(<BeastSoundPage>)`. Setting it back to `0` turns sound
   off.

## Verified

- **Their suite:** 74 pass with the patch (their 71 plus the 3 new ones). `scarb fmt --check` is
  clean.
- **Size:** the `beasts_nft` class grows from 30,249 to 30,556 Sierra felts (+1%).
- **End to end, real contracts:** `sound_e2e_tests.cairo` ran their real PNG and GIF art providers
  with the real `BeastSoundPage` and its 9 module contracts. Running it needs `beast_sound_page` as
  a path dependency and `build-external-contracts = ["beast_sound_page::*"]`.
  - With sound on, `token_uri` decodes to valid JSON. Name, description, attributes and `image`
    are identical to the sound-off output, with `animation_url` added.
  - In Chrome, the page composes the expected score hash and plays, for a plain Beast and for an
    animated shiny one.
- **Gas:** setup, mint and `token_uri` cost 1,249.5M L2 gas with sound off and 1,294.4M with
  sound on. So sound adds under 45M per call, and that figure includes deploying all 10 contracts.
  In the page's own test, the deployed system adds 54M to a 775M baseline (+7%).

## Not wired yet

- **Summit stats:** `scars` and `summit_held_seconds` are passed as 0. Summit deaths, hours held
  and later Death Mountain collects need a source in the NFT, such as a stats cache.
- **Sound drop:** every token gets sound once the address is set. To gate non-genesis Beasts by
  the sound drop, check the roll before calling the page.
