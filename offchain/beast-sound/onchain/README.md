# Sound in `token_uri`: TinySynth page + onchain MIDI

The NFT keeps its animated SVG as `image` and gains an `animation_url`: an HTML page holding a
TinySynth player, the token's music as a Standard MIDI File composed onchain, and the same SVG. The
browser plays the MIDI when the viewer taps. Nothing is fetched, and the player knows nothing about
Beasts.

```
NFT token_uri ──► MidiSoundPage.token_uri(members, svg_b64, token_address, token_id)
                        │
                        └─► IMidiProvider.get_midi(token_address, token_id)      (BeastMidiProvider)
                                   │  reads rank, species count, kills, Death Mountain defeats
                                   └─ composes with the Cairo engine (v1) → MIDI bytes
                        ◄── data:application/json;utf8,{ name, description, attributes, image, animation_url }
                                                                                     │
                            data:text/html;base64, [TinySynth + player][MIDI as base64][SVG]
```

- `contracts/midi_provider`: the generic `IMidiProvider` interface and a non-Beast example provider.
- `contracts/beast_sound`: `BeastMidiProvider`, which validates the collection and token and reads
  the Beast's live state itself (see its README for sources and missing-state behavior).
- `cairo/` (`beast_sound_page`): `MidiSoundPage`, configured with one provider at deploy.
- `integration/`: the Beasts V3 patch and the devnet end-to-end check.

## The page

`cairo/src/page_data.cairo` stores the page head, the patched TinySynth (`vendor/`, 42,214 bytes
minified), the player (`player-src.js`, 2,954 bytes) and the opening of the MIDI block, base64-encoded
at build time: 45,748 bytes of HTML (padded), 61,008 characters, 1,971 felts. At call time only the
MIDI is encoded.

`token_uri` is plain JSON (`data:application/json;utf8,…`). Base64-encoding the whole JSON was the
biggest per-call cost, so the JSON and the SVG are never re-encoded. `page.js` is the reference, and
the Cairo builds the same bytes:

```
'data:application/json;utf8,{' ++ escape(members)
  ++ ',"image":"data:image/svg+xml;base64,' ++ svg_b64 ++ '",' ++ <spaces>
  ++ '"animation_url":"data:text/html;base64,'
  ++ STORED       b64(PAGE): head + TinySynth + player + '<script type="text/plain" id="midi">'
  ++ b64(D)       D = b64(midi) <spaces> '</script><script type="text/plain" id="art">'
  ++ svg_b64      the same SVG base64 the NFT computed for `image`
  ++ '"}'
```

- **Word alignment:** `PAGE` is padded to 279n bytes (9 × 31), so `STORED` is 372n characters:
  whole base64 groups and whole 31-byte words. The JSON whitespace before the `animation_url` key
  puts `STORED` on a word boundary of the output, where Cairo appends it cheaply.
- **The MIDI block:** `D` closes the MIDI block and opens the art block, whose content is the SVG.
  `D` is padded to 3n bytes inside the MIDI block, where the player strips whitespace. So `b64(D)`
  has no `=`, and base64 never produces `<`.
- **Trailing `=`:** the SVG's base64 sits last in the HTML data URI, where its `=` is legal.
- **Escaping:** `escape()` writes `%` as `%25` and `#` as `%23`. A JSON data URI can't carry them
  raw; everything else is already URI-safe for browsers.
- **Marketplaces:** ArkProject's open-source metadata parser accepts `data:application/json;utf8,`
  and keeps `animation_url`. Its parsing code was run on these `token_uri`s, and both variants
  parsed cleanly. Closed-source marketplaces need a check. With sound off, the NFT's own base64 JSON
  is unchanged.
- **The SVG is not inlined:** the Beasts SVG embeds its art as `<xhtml:img …/>` in a
  `foreignObject`, which the HTML parser cannot read. The page shows it through an `<img>`, exactly
  as marketplaces render `image`. It must never contain `</script`.

### Player and orchestration

The player decodes the MIDI, builds TinySynth inside the first tap (browsers only start audio from a
gesture), and loops. Tap anywhere or ♪/■ to play or stop; ↺ restarts from the top.

**Orchestration v1** (`player-core.js`, `ORCHESTRATION = 1`). MIDI bytes are composition, so they
come from the provider unchanged. Instruments and accompaniment belong to the page, so they carry
their own version:

| Score | Instruments | Accompaniment | Loop |
|---|---|---|---|
| Bare: no program change, nothing on channel 10 (every Beast v1 score) | Every channel plays the chip lead (program slot 128): triangle, 3 ms attack, 33 ms release, 6 Hz / 30-cent vibrato faded in over 0.2 s. This is the previous page's lead. Voices are panned from −0.85 to 0.85. | The previous page's pattern on channel 10: kick on beat 1, snare on beat 3, hi-hat on every eighth at ±30%, about 1 in 8 off-beats opened. Hi-hat levels are rolled again on every Play (the old page rolled them every pass). | Whole 4/4 bars |
| Anything else | As written, with TinySynth's General MIDI set | None added | Whole 4/4 bars |

Tempo is exact: the vendored TinySynth is patched to keep fractional BPM (`vendor/README.md`).

### Playback limits

- 16 channels; channel 10 is percussion. Beast scores use channels 1–5, and the golden generator
  checks every tier/type at its most crowded.
- 64 simultaneous voices (TinySynth `voices`), then the oldest note is cut.
- TinySynth's General MIDI set: note on/off, program change, pitch bend, CC 1/7/10/11/64 and RPN.
  Its SysEx and text events are ignored.
- The MIDI's length is the provider's. A Beast score is 816–3,716 bytes.
- Audio starts only from a click or tap, and the page makes no network requests (checked with all
  routes aborted).

## What it costs

### The page, before and after the rebase (starknet-devnet 0.10.0)

Measured 2 Oct 2026, both page classes on one devnet: the public Beasts NFT (`ae3fa8d`, real art
providers, no Death Mountain), the real `BeastMidiProvider`, and each `MidiSoundPage` called with
the members and SVG base64 that NFT's own `token_uri` holds. Values are L2 gas, read as raw
`l2_gas_consumed` from `starknet_estimateFee`:

| Beast | NFT `token_uri`, sound off | `get_midi` | Page, base64 JSON (PR #1) | **Page, plain JSON + `b64.cairo`** |
|---|---:|---:|---:|---:|
| Tier 5 common (153 B MIDI) | 2,013M | 5.4M | 646M | **177M** |
| Sorrow Peak Warlock (816 B) | 2,022M | 29.4M | 721M | **212M** |
| Tier 1 Brute, shiny + animated (816 B) | 2,166M | 29.4M | 761M | **194M** |

- **3.6–3.9× cheaper:** that's the page, against PR #1's own page on the same chain.
- **Byte-identical:** both pages' output matches its JS reference byte for byte. The plain-JSON
  output keeps the NFT's name, image and attributes unchanged.
- **Not measured: the full NFT path with the patch.** It needs the private beasts-v3 `main`
  (`integration/e2e_devnet.mjs` runs it).
  - Estimate: the PR #1 measurement below minus this page saving puts sound-on `token_uri` at
    roughly 1.0–1.3B, against 1.7–2.2B with sound off.
  - That's derived, not measured.

### Full path, starknet-devnet 0.10.2 (base64 layout, before the plain-JSON rebase)

Measured 2 Oct 2026, on the base64 layout this branch replaced, so rerun it before relying on it. Beasts V3 `main` + `integration/beasts_nft-sound.patch` with the real art
providers, `BeastMidiProvider`, `MidiSoundPage`, and beasts-v3's mock Death Mountain. Values are L2
gas from `starknet_estimateFee`, followed by the `token_uri` size:

| Beast | Sound off (today) | Sound on, fresh | Sound on, 40 kills / 8 scars | Sound on, 200 kills / 63 scars |
|---|---:|---:|---:|---:|
| Genesis Warlock | 1,808M · 43.4 KB | 1,515M · 166.6 KB | 1,734M · 171.8 KB | 1,768M · 173.5 KB |
| Sorrow Peak Warlock | 1,713M · 41.1 KB | 1,450M · 162.0 KB | 1,655M · 167.2 KB | 1,714M · 168.9 KB |
| Tier 1 Brute, shiny + animated | 1,862M · 44.6 KB | 1,560M · 168.9 KB | 1,774M · 174.1 KB | 1,840M · 175.8 KB |

The MIDI was 816, 2,991 and 3,716 bytes in those three states.

- **Sound on is not more expensive than sound off.** The NFT skips its own base64 pass over the
  JSON, and the page's word-wise encoder costs about a third as much per byte. Even the largest
  score lands within ±2% of today's `token_uri`.
- **Where the gas goes, sound on:**

  | Part | L2 gas |
  |---|---:|
  | `BeastMidiProvider.get_midi` | 30M / 108M / 134M |
  | `get_live_state` reads | 2.1–2.6M |
  | `MidiSoundPage.token_uri` called directly with the NFT's ~43 KB of members and SVG as calldata | 715–760M |
  | The NFT's own work (art, SVG, members) | the rest |

- **Call latency** (`starknet_call` on local devnet, execution only): sound off 830–885 ms, sound on
  655–690 ms.
- **Sepolia public RPC:** the provider's getters each take 41–45 ms to read from offchain, and
  `token_uri` takes 65–128 ms today. Inside `get_midi` they are in-process calls in one execution.
- **Execution limits:** public RPC nodes may cap `starknet_call`. Sound on stays at or below
  today's sound-off cost, so it does not move a Beast closer to such a cap than it is today.

### Contract sizes

| Class | Sierra felts | CASM felts (limit 81,920) |
|---|---:|---:|
| `MidiSoundPage` | 26,462 | 24,202 (15,828 with the PR encoder) |
| `BeastMidiProvider` | 9,623 | 22,574 |
| `beasts_nft`, patched (unpatched) | 33,046 (32,753) | 74,927 (74,062) |

### Assembly alone (cairo-test estimate)

These are the `bench_*` tests in `cairo/src/tests.cairo`, without calldata or the provider call.
cairo-test reports Sierra gas, a different unit from devnet's fee estimate, so only compare rows
here with each other:

| Case | Base64 JSON, PR encoder | Plain JSON, PR encoder | Plain JSON, `b64.cairo` |
|---|---:|---:|---:|
| Real Warlock art + 816 B MIDI | 335M | 101.5M | **92.9M** |
| Real Warlock art + 3,716 B MIDI | 416M | 148.9M | **109.2M** |
| (reference) one base64 pass over the same JSON | 250M | | |

**Encoders:**
- **`b64.cairo`:** reads input as 31-byte words, 93 bytes per step, through a 4,096-entry 12-bit
  table. On devnet it measured about 6.7K L2 gas per byte, against 40K for the NFT's encoder.
- **Its size:** it takes `MidiSoundPage` from 14.5K to 24.2K CASM felts (the limit is 81,920).

**Pending:** the devnet full-path table above was measured on the base64 layout and needs a rerun
on this one.

## Build and test

```bash
npm install                                  # @scure/starknet (in offchain/beast-sound)
node onchain/build.mjs                       # patch + minify TinySynth, bundle the player, encode STORED, write cairo/src/page_data.cairo
node onchain/build-library.mjs               # the offchain JS library (onchain/lib) and dist/composer.js, for sites and demos
node onchain/engines-demo.mjs                # public/onchain/engines.html: the same MIDI through the chip synth or TinySynth
node onchain/golden.mjs                      # Cairo tests from the JS reference (page.js) and JS engine MIDI
npm test                                     # layout, decoding, player core, TinySynth timing (Node)
cd onchain/cairo && scarb test               # Cairo token_uri == JS token_uri byte for byte; contract tests
node onchain/browser-check.mjs [uri files]   # offline headless Chromium (see the header for setup)
node onchain/integration/e2e_devnet.mjs …    # full path on devnet (see integration/README.md)
node onchain/gallery.mjs --rebuild           # re-render public/onchain from recorded inputs
```

The golden Cairo tests cover base64 at every length 0..100 into empty and unaligned outputs, the MIDI
block at every MIDI length 0..92 (every remainder mod 31 and mod 3), full URIs for small and real
Beast MIDI, and the real Sepolia Warlock art. `browser-check.mjs` opens each token's real
`animation_url` with every request aborted, taps, and checks the following:
- the art and decoded MIDI;
- a running audio context and non-silent output;
- the exact fractional tempo and whole-bar loop end;
- the orchestration rule;
- stop, restart and loop wrap;
- zero requests and no page errors.

## Versioning

| What changes | What ships |
|---|---|
| Composition (the MIDI) | A new provider deployment and a new `MidiSoundPage` pointing at it. Follow the rule in `docs/beasts/composition_guide.md`: a version never changes what it produces. |
| Player, orchestration or TinySynth | A new page class. Bump `ORCHESTRATION` when the sound of a given MIDI changes. |
| Neither | The NFT owner points `sound_page` at a new page, or sets it to zero to turn sound off. |
