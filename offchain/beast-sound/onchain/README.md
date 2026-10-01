# Beast Sound in `token_uri` (fully onchain)

The Beasts NFT keeps its animated SVG as `image` and gains an `animation_url`: an HTML page holding
the Beast Sound composer, one line of per-token inputs, and the same SVG. The browser composes the
Beast's theme from the inputs (engine v1, byte-identical to the Cairo reference) and plays it when
the viewer taps. Nothing is fetched and no server is involved.

```
token_uri → data:application/json;base64,{ "name", "description", "image", "animation_url", "attributes" }
                                                    │                 │
                              animated SVG (unchanged)   data:text/html;base64, page = [composer][inputs][SVG]
```

## What it costs

Measured with cairo-test on the real Sepolia genesis Warlock (members 2.3 KB, SVG base64 30 KB):

| | L2 gas (est.) | token_uri size |
|---|---:|---:|
| Today: one base64 pass over the JSON | 775M | 43 KB |
| With sound, via `BeastSoundPage.token_uri` | 812M (+4.8%) | 120 KB |
| With sound, naively (base64 the 43 KB page, put it in the JSON, base64 everything) | ≈3.2B (estimated from the per-byte cost) | 120 KB |

The cross-contract call's calldata and return copying are not included. Measure them on devnet
before mainnet.

The composer is stored once, in the code of a stateless contract: 20 KB of JavaScript, 1,182
felts. The CASM class is 13,146 felts, against the 81,920 limit. No composition runs onchain, so the
v1 Cairo composer's 5–120M gas per call does not apply.

The composer hashes with `src/poseidon_lite.js` instead of `@scure/starknet`: a 1 KB Starknet
Poseidon that derives its round constants (`sha256("Hades" + i) mod p`) on first use, in about
11 ms. `test/poseidon_lite.test.mjs` checks it against `@scure/starknet` on 207 inputs and on
full Beast renders.

### Why the cost barely moves

Every piece is aligned to 3 bytes, so base64 runs concatenate:

```
"data:application/json;base64,"
  ++ b64('{' members ',' <spaces> '"image":"data:image/svg+xml;base64,')
  ++ b64(S)            S = svg_b64 '"' <spaces>        encoded once, appended twice
  ++ b64(',  ')
  ++ STORED            b64('"animation_url":"data:text/html;base64,' ++ b64(page)), built offline
  ++ b64(b64(inputs))  ~150 bytes: the only new per-call encoding
  ++ b64(S)
  ++ b64('}')
```

- **JSON validity:** the padding spaces sit between JSON tokens, where whitespace is allowed.
- **Trailing `=`:** the SVG's base64 sits last in both data URIs, so its `=` padding is legal there.
- **Per-call work:** the NFT's base64 work is what it is today (members plus the SVG), plus the
  inputs line.

### Why the SVG is not inlined

The Beasts SVG embeds the art as `<xhtml:img …/>` inside a `foreignObject`. That syntax is
XML-only, and the HTML parser swallows everything after it.

The page therefore carries the SVG as inert text, in `<script type="text/plain" id="art">`. The
composer shows it through an `<img>`, exactly as marketplaces render `image` today. The SVG needs
no changes, but it must never contain `</script`.

## Integration (Beasts NFT side)

1. **Deploy `BeastSoundPage`** from `onchain/cairo`. It's stateless and has no constructor. Store
   its address in the NFT, e.g. as `sound_page: ContractAddress`, with an admin setter.
2. **Change `generate_metadata`** in `metadata_generator.cairo`:

```cairo
// before
let image = format!("data:image/svg+xml;base64,{}", bytes_base64_encode(svg));
...
let json = Self::components_to_json(components);
format!("data:application/json;base64,{}", bytes_base64_encode(json))

// after
let svg_b64 = bytes_base64_encode(svg);
...
if sound_page.is_zero() || !has_sound {
    // unchanged path
    return format!("data:application/json;base64,{}", bytes_base64_encode(json_with_image));
}
// members: the JSON body without braces and without `image`:
//   "name":"…","description":"…","attributes":[…]
let members = Self::components_to_members(components);
IBeastSoundPageDispatcher { contract_address: sound_page }
    .token_uri(
        members,
        svg_b64,
        token_id,
        BeastSoundInputs {
            adventurers_killed,      // already read from Death Mountain
            scars: 0,                // Summit deaths + later Death Mountain collects, if cached
            summit_held_seconds: 0,  // from Summit, if cached
            rank,                    // already read
            species_count,           // beast_counts(beast.id)
        },
    )
```

`has_sound` decides which tokens play. Genesis tokens always have sound; for the drop, use the
`hasSound(salt, bps, beast)` roll from `@koji/beast-sound`.

`components_to_members` is `components_to_json` minus the `{`, the `}` and the `image` member.

## Build and test

```bash
node onchain/fetch-fixture.mjs   # snapshot a real V3 token_uri (Sepolia) into fixtures/
node onchain/build.mjs           # bundle the composer, encode STORED, generate cairo/src/page_data.cairo
node onchain/golden.mjs          # generate Cairo tests from the JS reference (page.js)
node --test test/onchain.test.mjs
cd onchain/cairo && scarb test   # Cairo token_uri == JS token_uri, byte for byte, incl. the real Warlock
```

`page.js` is the reference implementation of the layout. The Cairo in `cairo/src/lib.cairo` builds
the same bytes.

## Versioning

The composer lives in contract code. A different engine or synth means a new class and a new
`sound_page` address, which also changes the music. Follow the versioning rule in
`docs/beasts/composition_guide.md`.

## Possible next steps

- **Engine v2:** needs its JS port bundled in (about +30 KB). There's still no onchain composition
  cost.
