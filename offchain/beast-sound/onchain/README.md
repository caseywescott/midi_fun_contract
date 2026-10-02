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
                        ◄── data:application/json;base64,{ name, description, attributes, image, animation_url }
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
minified), the player (`player-src.js`, 2,954 bytes) and the opening of the MIDI block, already
encoded at both base64 layers: 45,523 bytes of HTML, 80,996 characters, 2,615 felts. At call time
only the MIDI is encoded.

Every piece is aligned to 3 bytes, so base64 runs concatenate (`page.js` is the reference; the
Cairo builds the same bytes):

```
"data:application/json;base64,"
  ++ b64('{' members ',' <spaces> '"image":"data:image/svg+xml;base64,')
  ++ b64(S)            S = svg_b64 '"' <spaces>        encoded once, appended twice
  ++ b64(',  ')
  ++ STORED            b64('"animation_url":"data:text/html;base64,' ++ b64(PAGE)), built offline
  ++ b64(b64(D))       D = b64(midi) <spaces> '</script><script type="text/plain" id="art">'
  ++ b64(S)
  ++ b64('}')
```

- `PAGE` (9n bytes) ends by opening `<script type="text/plain" id="midi">`; `D` (9n bytes) closes it
  and opens the art block, whose content is the SVG. So the page's own base64 is
  `b64(PAGE) ++ b64(D) ++ svg_b64`.
- **Padding:** spaces sit between JSON tokens or inside the MIDI block, where the player strips
  whitespace. Base64 never produces `<`, so the MIDI cannot close its block early.
- **Trailing `=`:** the SVG's base64 sits last in both data URIs, so its `=` padding is legal there.
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

### Full path, starknet-devnet 0.10.2

Measured 2 Oct 2026. Beasts V3 `main` + `integration/beasts_nft-sound.patch` with the real art
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
| `MidiSoundPage` | 13,621 | 15,828 |
| `BeastMidiProvider` | 9,623 | 22,574 |
| `beasts_nft`, patched (unpatched) | 33,046 (32,753) | 74,927 (74,062) |

### Assembly alone (cairo-test estimate)

These are `bench_*` tests in `cairo/src/tests.cairo`, without calldata or the provider call:

| Case | L2 gas |
|---|---:|
| Real Warlock art + 816 B MIDI | 335M |
| Real Warlock art + 3,716 B MIDI | 416M |
| One base64 pass over the same JSON | 250M |

The MIDI is encoded three times (into `D`, into the page, into the JSON): (416M − 335M) / 2.9 KB,
about 28M gas per KB of MIDI.

### Follow-ups, not done

- **Aligned bulk appends:** appending the 81 KB stored segment to a ByteArray that is not
  word-aligned costs 36.8M instead of 4.6M (measured). Padding before the stored segment and both
  SVG copies, using the same JSON-whitespace trick, would save roughly 55M per call.
- **Fused encoding:** a single pass mapping 27 MIDI bytes to 64 output characters would avoid
  building the two intermediate layers.

## Build and test

```bash
npm install                                  # @scure/starknet (in offchain/beast-sound)
node onchain/build.mjs                       # patch + minify TinySynth, bundle the player, encode STORED, write cairo/src/page_data.cairo
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
