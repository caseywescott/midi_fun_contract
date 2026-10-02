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
| `notes` | `BeastSoundModuleNotes` | 1.4 KB | | `v1.notes.decode(felts)`: BSN1 felts → song |
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
| Modules on the page | all 10 (27.5 KB) | midi, synth, play, notes, page (12.4 KB) |
| Score in the token data | No (deterministic from onchain code + inputs) | Yes |
| Page `token_uri` gas, real (devnet) | 2.47–2.48B | 2.46–2.81B (BSN1); BSI1 2.49–3.33B, heaviest over the step limit |

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

**Status: too expensive as designed.** Their Beasts NFT plus any sound page exceeds the execution
step limit, so `token_uri` fails. Measured with their real `beasts_nft`, the real art providers and
the real `BeastSoundComposer`, through `starknet_call` and fee estimates:

| NFT `token_uri` | Sound off | Inputs page | Notes page (BSN1) | Notes page (BSI1) |
|---|---:|---:|---:|---:|
| Tier 5 common | 3.00B | step limit | step limit | step limit |
| Sorrow Peak Warlock | 3.01B | step limit | step limit | step limit |
| Tier 1 shiny | 3.09B | step limit | step limit | step limit |
| Animated shiny | 3.25B | step limit | step limit | step limit |

Each page contract on its own, called with the Warlock fixture's members and SVG:

| Beast | Notes | Inputs page | Notes page (BSN1) | Notes page (BSI1) |
|---|---:|---:|---:|---:|
| Tier 5 fresh | 12 | 2.47B | 2.46B | 2.49B |
| Sorrow Peak Warlock | 160 | 2.47B | 2.59B | 3.04B |
| Tier 1, 3 sections | 240 | 2.48B | 2.67B | 3.33B |
| Heaviest | 400 | 2.48B | 2.81B | step limit |

**Why it fails:**
- **Base64 per byte:** base64 in Cairo costs about 70K L2 gas per byte.
- **Already near the cap:** the NFT already base64-encodes the SVG and then the whole JSON, about
  54 KB, which puts it near the step limit before any sound is added.

**Correction:** earlier figures here (+37M, +54M, "+7%") were cairo-test and snforge estimates.
Those use smaller gas units than real L2 gas, and the snforge runs had no step limit. Correctness
results stand: on devnet, every page and composer output matched the JS reference byte for byte.

**Proposed fix (not built yet): plain-JSON `token_uri`**
(`data:application/json;utf8,…`).
- **What it removes:** the outer base64 pass over the whole JSON.
- **Per-call encoding left:** only the SVG, which the NFT encodes today anyway, plus the inputs line.
- **Expected:** `token_uri` with sound should cost less than today's sound-off `token_uri`.
- **To check first:** marketplaces must accept non-base64 JSON data URIs, and `%` or `#` in the
  JSON must be escaped.

### The layout: no extra per-call encoding of the library

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
