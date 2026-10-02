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
| `api` | `BeastSoundModuleApi` | 1.1 KB | beast, music, midi, play | `compose`, `fromInputs`, flat API |
| `page` | `BeastSoundModulePage` | 1.6 KB | api | token_uri page mount |

- **Contracts:** each module contract exposes `name()` and `segment()`. A segment is
  base64(base64(`<script>…</script>`)), so a site reading it over RPC decodes it twice to get the
  script.
- **Page contract:** `BeastSoundPage` keeps the page head and a module list fixed at deploy, and
  splices HEAD plus every segment into `animation_url`.
- **One file:** `dist/composer.js` is all modules concatenated, 25.8 KB, for sites that want a
  single file.
- **Build:** `onchain/build.mjs` builds the modules (`onchain/modules.mjs` is the manifest),
  `dist/`, and the Cairo in `cairo/src/modules.cairo` and `page_data.cairo`.

## What it costs

Measured with cairo-test on the real Sepolia genesis Warlock (members 2.3 KB, SVG base64 30 KB):

| | L2 gas (est.) | token_uri size |
|---|---:|---:|
| Today: one base64 pass over the JSON | 775M | 43 KB |
| With sound: deployed `BeastSoundPage` + 9 module contracts | 829M (+7%) | 133 KB |
| With sound, naively (base64 the page, put it in the JSON, base64 everything) | ≈3.5B (estimated from the per-byte cost) | 133 KB |

**Where the 54M goes:** assembling the page costs 18M, and the 9 module calls cost 36M.

**Word alignment:**
- **What's padded:** every segment is a whole number of 31-byte words, and JSON whitespace puts
  the library on a word boundary of the output.
- **Why:** assembling at word boundaries is cheap. Without alignment the same system cost +103M.
- **End to end:** against the real Beasts contracts (`integration/`), sound adds under 45M per
  `token_uri`, including deploying all 10 contracts.

**Contract sizes:** each module contract is 869–2,756 CASM felts and the page is 12,108, all far
under the 81,920 limit. No composition runs onchain, so the v1 Cairo composer's 5–120M gas per call
does not apply.

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
