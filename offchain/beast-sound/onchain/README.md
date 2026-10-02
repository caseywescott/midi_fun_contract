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

## The onchain library: `window.BeastSound`

The stored script is a library of layers that work alone or together. Any page that loads it (the
token_uri page, a game client, a marketplace, a site that pulls it from the chain) gets the same
deterministic engine. Source: `onchain/lib/`.

A **song** is the common currency: `{ notes: [[time, duration, pitch, velocity, voice], ...], tempo_us }`,
with 480 ticks per beat. Every layer consumes or produces one.

| Layer (`BeastSound.v1`) | Functions | Use it for |
|---|---|---|
| `beast` | `decode(tokenId)`, `live(stats)`, `params(traits, live)`, `seed(traits)` | Turning a Beast into musical parameters |
| `music` | `generate(params, seed)` → song, `fromNotes(notes, tempo_us)` | Counterpoint from any params, no Beast needed |
| `midi` | `write(song)` → bytes, `url(song)` | MIDI for any song; Beast scores match the Cairo `get_score_midi` byte for byte |
| `synth` | `instrument(def)`, `presets`, `drum(kit, dest, t, kind, level)` | Chip instruments defined as data |
| `play` | `play(song, { instruments, drums, loop, destination, volume })` → handle `{ stop, playing, position, onNote, onEnd }`; `context()` | Many songs at once, routed into any audio graph |
| `fx` | `transpose`, `tempo`, `voices`, `gain`, `layer(...songs)`, `concat(...songs)` | Pure song → song transforms |

```js
const { beast, music, midi, synth, play, fx } = BeastSound.v1;

// the Beast pipeline, one stage at a time (== BeastSound.compose(tokenId, stats))
const traits = beast.decode(tokenId);
const song = music.generate(beast.params(traits, stats), beast.seed(traits));

// two Beasts in a battle duet, with a custom lead and a callback per note
const duet = fx.layer(BeastSound.compose(a, statsA), fx.transpose(BeastSound.compose(b, statsB), -12));
const h = play(duet, { instruments: [synth.instrument(synth.presets.pulseLead), synth.instrument(synth.presets.triangleBass)] });
h.onNote((n) => pulseArt(n[2]));
const file = midi.write(duet);
```

The flat API from the first release still works: `compose`, `fromInputs`, `midi`, `midiUrl`,
`play`, `stop`, `isPlaying`, `onPlayingChange`, `decodeTokenId`. It drives one global player.

- **Inputs:** a Beast's token ID plus its live stats. The token ID already packs every static trait.
- **No compact note format:** that's only for storing notes onchain, so it isn't in the library.
  The npm package keeps it (`src/bsn.js`) for Cairo parity.
- **Tested:** `test/onchain.test.mjs` runs the built blob in a sandbox:
  - its score and MIDI hashes match the Cairo goldens, and it matches the package engine on 300
    random Beasts;
  - the separate layers compose to exactly the same song as `compose()`;
  - the transforms are pure.
- **Playback, checked in real-time Chrome:** two handles at once, per-voice instruments, a caller's
  destination node, `onNote`, and play-once ending with `onEnd`.
- **The token_uri page:** when the page carries the `BEAST_SOUND` inputs line, `lib/page.js` also
  mounts the art and the ♪ (play) and MIDI (download) buttons. Loaded anywhere else, the library
  only defines the API.

## Onchain modules

Each layer is its own script and its own contract, so a project stores or loads only what it needs.
A module registers itself into `window.BeastSound.v1` and finds its dependencies there. Load any
subset in dependency order; a module whose dependency is missing throws before it runs.

| Module | Contract | JS | Needs | Provides |
|---|---|---:|---|---|
| `core` | `BeastSoundModuleCore` | 11.2 KB | | engine v1 + Poseidon |
| `beast` | `BeastSoundModuleBeast` | 0.7 KB | core | `v1.beast` |
| `music` | `BeastSoundModuleMusic` | 0.7 KB | core | `v1.music` |
| `midi` | `BeastSoundModuleMidi` | 1.1 KB | | `v1.midi` (any song) |
| `synth` | `BeastSoundModuleSynth` | 4.9 KB | | `v1.synth` |
| `play` | `BeastSoundModulePlay` | 3.1 KB | synth | `v1.play`, `v1.context` |
| `fx` | `BeastSoundModuleFx` | 1.4 KB | | `v1.fx` |
| `notes` | `BeastSoundModuleNotes` | 2.1 KB | | `v1.notes.decode(felts)`: BSN1 or BSI1 felts → song |
| `api` | `BeastSoundModuleApi` | 1.1 KB | beast, music, midi, play | `compose`, `fromInputs`, flat API |
| `page` | `BeastSoundModulePage` | 1.9 KB | midi, play (+ api or notes) | token_uri page mount |

- **Contracts:** each module contract exposes `name()` and `segment()`. A segment is
  base64(base64(`<script>…</script>`)), so a site reading it over RPC decodes it twice to get the
  script.
- **Page contract:** `BeastSoundPage` keeps the page head and a module list fixed at deploy, and
  splices HEAD plus every segment into `animation_url`.
- **One file:** `dist/composer.js` is all modules concatenated, 25.8 KB, for sites that want a
  single file.
- **Build:** `onchain/build.mjs` builds the modules (`onchain/modules.mjs` is the manifest),
  `dist/`, and the Cairo in `cairo/src/modules.cairo` and `page_data.cairo`.

## Two page variants: who composes

Both variants implement the same `IBeastSoundPage`, so the NFT patch points at either one.

| | Inputs page (`BeastSoundPage`) | Notes page (`BeastSoundNotesPage`) |
|---|---|---|
| Who composes | The library, in the browser, from token ID + stats | The chain: the Cairo composer's `get_score_notes` |
| Per-token line | `BEAST_SOUND="token,kills,scars,held,rank,count"` | `BEAST_NOTES="0x…,0x…"` (BSN1 felts) |
| Data per Beast | ~2 felts of inputs | 2–16 felts (median 4 over 400 mainnet Beasts) |
| Modules on the page | all but notes, 9 (26.1 KB) | midi, synth, play, notes, page (13.1 KB) |
| Score in the token data | No (deterministic from onchain code + inputs) | Yes |
| Page `token_uri` gas, real (devnet) | 0.27–0.28B | 0.26–0.54B (BSN1), 0.28–1.13B (BSI1) |

**The notes format (BSN1):**
- **Layout:** felts are `[byte_len, 31-byte chunks…]`.
- **Header:** tempo, grid, duration, articulation and velocities.
- **Runs:** each run is `voice 4 | start beat 12 | count 8`, then 7-bit keys.
- **Why runs:** Beast scores sit on a fixed grid with one duration, so run-length coding beats a
  fixed-width instruction. A 62-bit, 4-per-felt instruction format would take about 4–61 felts
  (median 13) for the same Beasts.
- **BSI1, the general format, is also built:** 62-bit instructions (header, tempo, notes), 4 per
  felt, from `src/bsi.js` and the composer's `get_score_instructions`. The `notes` module
  auto-detects it.
- **BSI1 cost:** it's cheaper for the composer to produce (103M against 178M for the heaviest
  Beast), but its line is about 6× larger, and the page base64-encodes that line twice. So the
  BSN1 page is the lighter one.

`test/onchain.test.mjs` checks that the notes page, with no composer loaded, decodes the felts Cairo
emits (golden `bsn_hash`) into exactly the reference notes and MIDI.

## What it costs (real execution, devnet 0.10.0)

`token_uri` is plain JSON (`data:application/json;utf8,…`). That removes the outer base64 pass,
the biggest cost in today's `token_uri`.

**Their Beasts NFT, measured on devnet:** their real `beasts_nft`, the real art providers and the
real `BeastSoundComposer`, through `starknet_call` and fee estimates:

| NFT `token_uri` (L2 gas) | Today, sound off | With inputs page | With notes page (BSN1) | With notes page (BSI1) |
|---|---:|---:|---:|---:|
| Tier 5 common | 3.00B | **1.51B** | 1.50B | 1.52B |
| Sorrow Peak Warlock | 3.01B | **1.52B** | 1.55B | 1.67B |
| Tier 1 shiny | 3.09B | **1.56B** | 1.59B | 1.71B |
| Animated shiny | 3.25B | **1.60B** | 1.63B | 1.75B |

With sound, `token_uri` costs about half of today's `token_uri` without sound.

**Each page contract on its own,** with the Warlock fixture's members and SVG. The notes pages
include the real composer's call:

| Beast | Notes | Inputs page | Notes page (BSN1) | Notes page (BSI1) |
|---|---:|---:|---:|---:|
| Tier 5 fresh | 12 | 0.28B | 0.26B | 0.28B |
| Sorrow Peak Warlock | 160 | 0.27B | 0.37B | 0.60B |
| Tier 1, 3 sections | 240 | 0.28B | 0.43B | 0.78B |
| Heaviest | 400 | 0.28B | 0.54B | 1.13B |

**What's verified:**
- **Byte-identical output:** every composer output and page `token_uri` on devnet matches the JS
  reference byte for byte.
- **Real-time playback:** the heaviest BSI1 page, as the contract returned it, plays in real-time
  Chrome with all 400 notes and the MIDI bytes exact.

**Before plain JSON:** with a base64 JSON, the same pages cost 2.46–2.81B on their own, and the NFT
plus any page exceeded the execution step limit. Earlier "+7%" figures were cairo-test estimates.
Those use smaller gas units than real L2 gas.

**Marketplace check (open):** marketplaces must accept a `data:application/json;utf8,` token_uri.
- **Escaping:** `%` and `#` are escaped as `%25` and `%23`.
- **Parsing:** `decodeURIComponent` of the payload, or the raw payload, both parse as JSON.

### The layout

```
'data:application/json;utf8,{' ++ escape(members)
  ++ ',"image":"data:image/svg+xml;base64,' ++ svg_b64 ++ '",' ++ <spaces>
  ++ '"animation_url":"data:text/html;base64,'
  ++ HEAD ++ MODULE_1 ++ … ++ MODULE_n      stored, base64 at build time, word-aligned by <spaces>
  ++ b64(inputs or notes line)              ~100 bytes: the only per-call base64
  ++ svg_b64 ++ '"}'                        reused from `image`
```

- **Piece size:** each page piece is padded to 279n bytes (9 × 31). Its base64 is then 372n
  characters: whole base64 groups and whole 31-byte words.
- **Why:** the stored segments concatenate, and Cairo appends them at word boundaries, which is
  cheap.
- **The SVG:** its base64 sits last in the HTML data URI, so its trailing `=` is legal.

### Why the SVG is not inlined

The Beasts SVG embeds the art as `<xhtml:img …/>` inside a `foreignObject`. That syntax is
XML-only, and the HTML parser swallows everything after it.

The page therefore carries the SVG as inert text, in `<script type="text/plain" id="art">`. The
composer shows it through an `<img>`, exactly as marketplaces render `image` today. The SVG needs
no changes, but it must never contain `</script`.

## Integration (Beasts NFT side)

`integration/beasts_nft-sound.patch` is a ready-to-apply change to the Beasts repo. It's tested
against their suite and end to end with the real contracts; see `integration/README.md`. In short:
- **Contract change:** `beasts_nft` gets an owner-set `sound_page` address.
- **`token_uri`:** when the address is set, it passes its JSON members (name, description,
  attributes) and SVG base64 to `BeastSoundPage.token_uri`. When it's zero, `token_uri` is
  unchanged, byte for byte.

## Build and test

```bash
npm install                      # esbuild (pinned dev dependency, used by the module build)
node onchain/fetch-fixture.mjs   # snapshot a real V3 token_uri (Sepolia) into fixtures/
node onchain/build.mjs           # build the modules, dist/, and cairo/src/{modules,page_data}.cairo
node onchain/golden.mjs          # generate Cairo tests from the JS reference (page.js)
node --test test/onchain.test.mjs
cd onchain/cairo && scarb test   # Cairo == JS byte for byte (incl. the real Warlock); deployed page + modules
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
