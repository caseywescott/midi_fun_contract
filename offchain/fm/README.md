# Loot FM pack

The Kankyo FM instruments of Loot Dungeon Sound (28 instruments, 10 drums, 298 key zones, 415 zone takes; the bank of midi_fun_contract 0f2d0ba, 2026-11-16)
as one self-contained script, built from the reference bank script `kankyo.min.js` (the one the Loot lab
loads) and sounding exactly like it: every zone and take renders to the same samples, bit for bit.

```
dist/loot-fm-pack.min.js          the pack (a classic script; also its own worker script)
dist/loot-fm-pack.min.js.gz       gzip -9 of it
dist/loot-fm-pack.min.js.gz.b64   base64 of the gzip: what the LootFmPack contract returns
dist/demo.html                    drop a .mid file to hear it played with the pack (pack inlined as .gz.b64)
```

## API

Loading the script builds the bank and starts rendering every zone's first take in background workers
(`min(6, cores - 1)`; the workers run the pack's own source, so the engine is in the file once). It sets
`window.LootFmPack`, and `window.SnesBank` (the same object), the name the Loot lab reads a bank script by,
so the pack drops in where `kankyo.min.js` was (checked: the lab page with the pack inlined plays, no errors).

| member | |
|---|---|
| `bank` | the BSBRR1 bank `{ format, name: 'kankyo', samples, instruments }`; instruments as in kankyo.min.js (`id`, `program` or `drum`, `rootNote`, `keys`, `tuneCents`, `volume`, `envelope`, `takes`, `human`, `slur`) |
| `need([[program, note], …])` | render those zones first (a drum: `[-1, key]`); a Promise that resolves when they are ready, with `.pending` false if they already were |
| `ready()` | a Promise for every first take |
| `progress()` | `{ done, total }` first takes rendered |
| `createSampler(audioContext, options)` | a sampler on the bank (runtime.js API: `noteOn({ channel, program, drum, note, velocity, time, destination, bend })`, `noteOff`, `releaseSustain`, `bend`, `stop`, `articulate`, `dispose`, `activeVoices`) |
| `attach(tinySynth, options)` | the same, wired into a TinySynth instance (unmatched programs fall back to TinySynth) |
| `version` | `1` |

A zone asked for before it is rendered is rendered on the spot (main thread), as before; a zone's other takes
are rendered after its first note. Without workers the queue runs on a timer.

Loading it from the contract (or `dist/*.gz.b64`):

```js
const b64 = /* LootFmPack.pack() as a string */;
const gz = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
const js = await new Response(new Blob([gz]).stream().pipeThrough(new DecompressionStream('gzip'))).text();
const s = document.createElement('script'); s.textContent = js; document.head.appendChild(s);
const pack = window.LootFmPack;
```

## Build and checks

```
npm install                      # esbuild
node pack/build.mjs [bank.js]    # reference bank (default kankyo.min.js) -> pack/kankyo-data.js, dist/*
node pack/parity.mjs             # every zone and take, reference vs dist/loot-fm-pack.min.js, sample by sample
node pack/sampler-parity.mjs [rate]  # the sampler's upsampled playback buffers, reference vs pack (one zone per instrument)
node pack/bench.mjs [runs]       # Chrome timings, and the zones the pack's workers render hashed against the reference's
node pack/cairo.mjs              # loot/loot_contracts/src/fm_pack_data.cairo and the contract test's fixture
sh scripts/cairo_run.sh snforge test -p loot_contracts --max-threads 2 fm_pack   # from the worktree root
```

`build.mjs` reads the reference by running it in Node (nothing depends on its minified names) and stops if
the compact data does not decode to exactly the reference's definitions. When the bank changes, rebuild
`kankyo.min.js` with `banks.mjs` as before, then run the four commands above.

Sources (`pack/`): `engine.js` (FM, sustained and struck, with sections, formants, the fm-violin, `nmod` and
`bend`, and the noise drums: the parts of engines.js the Kankyo bank uses; additive, modal, Karplus-Strong, the STK models, the recorded-attack hybrid and BRR are
left out), `sampler.js` (runtime.js without BRR decoding and bank validation), `gen.js` (per-zone settings
computed instead of stored), `data.js` + `kankyo-data.js` (the patches), `main.js` (bank, render queue,
workers), `ref.mjs` (the reference harness), `demo.src.html`.

## What changed

Size (bytes):

| | raw | gzip | gzip + base64 |
|---|---|---|---|
| kankyo.min.js (reference, 0f2d0ba bank) | 58,678 | 22,622 | 30,164 |
| loot-fm-pack.min.js | 31,502 | 13,785 | 18,380 |
| (previous bank: kankyo.min.js / pack) | 59,205 / 28,370 | 21,467 / 12,680 | 28,624 / 16,908 |

- The workers run the pack's own source (`'(' + LootFmPack + ')()'` as a Blob) instead of a second copy of
  the engine in a string (15.5 KB).
- Only the engine paths the Kankyo patches use, and the sampler without BRR/base64 decoding and validation
  (the reference carried the whole SNES runtime and every engine).
- Patch data 8.6 KB (minified; level changes such as the `trim`s of 8b7b8ad, 64bc5a5 and 7d64b83 (flute, ocarina, oboe, trumpet; bassoon and trombone state 0) are folded into each instrument's `lvl` by banks.mjs, and the pack stores the `lvl`, so a `base` instrument never inherits its base's trim): harp zones computed per note by banks.mjs's formula (`harpAt`), and any
  instrument stored as an earlier one plus the keys that differ (`b`: guitar = vibraphone, toms = the first tom,
  open hat = hat, the lead violin = the strings, bassoon = oboe, trombone = trumpet, …). The build checks every
  decoded definition against the reference.

The 2026-11-16 bank (ff34a3f) replaced the strings and lead violin with Schottstaedt's fm-violin (a section of
six players and a soloist), the clarinet with Chowning's 1:2 FM clarinet, gave the flute breath in the tone, and
added oboe, bassoon, trumpet, trombone section, bowed cello, koto, kalimba and choir. The pack's engine gained
what engines.js gained, keeping the reference's arithmetic: `sectionOps` (verbatim: section players, formant
carriers, choir, `fmv`), each operator's own vibrato `ov` (computed once per player, and the shared modulator cache
keyed per player), attack indices for parallel modulators (`ar`), `nmod` (noise in the index, its bandwidth the narrower of `nmod[1]` Hz and `nmod[2]` times the note since cb728e0, folded into the
per-sample brightness), and `bend` on struck notes. `clarinetAt` and the fitted string zones (`stringZone`)
left the pack with the voices they made (+5.0 KB raw for the new engine paths and the bigger bank, +1.1 KB gzip).

Render speed, same samples (the engine's arithmetic is unchanged; only work that was repeated or multiplied
by zero is gone): a modulator shared by several operators (the string carriers all ride one feedback
modulator) is computed once; operators whose index is zero throughout skip their modulator; index envelopes
that cancel (held = attack) skip their `Math.exp`; the vibrato and pitch wander are evaluated once per sample
instead of up to six times; the attack's `exp` and `(1 - u^4)` are shared between operators; the EQ runs a
filter at a time over the whole buffer from typed arrays; the sampler's upsampler reads straight from the
source away from the edges and loop seam. The queue starts the longest zones first among equal priority.

| one thread, all 374 zone takes (previous bank) | reference | pack |
|---|---|---|
| Node 20 | 17.2 s | 10.7 s |
| Chrome, all 240 first takes (page thread) | 5.61 s | 4.25 s |

The 415 zone takes of the ff34a3f bank: reference 23.4 s, pack 13.4 s (Node 20, one thread). The Chrome
figures below were measured on the previous bank. Chrome as the lab uses it (6 workers; median of 9 page loads alternating reference and pack, on a shared
10-core Mac under load average 8-12, so the parallel numbers are noisy; `node pack/bench.mjs 9`):

| from the start of loading the script | reference | pack |
|---|---|---|
| script run, bank built | 12 ms | 12 ms |
| a track's zones ready (`need`: flute, harp, cello, strings, kick, snare, hat) | 165 ms | 155 ms |
| those first notes scheduled (time to first sound) | 229 ms | 189 ms |
| main-thread cost of a note in a zone not yet played (building its upsampled buffer) | 10 ms | 4.2 ms |
| every first take ready | 1,516 ms | 1,329 ms |
| JS heap after | 77 MB | 77 MB |

Parity (`node pack/parity.mjs`, 0f2d0ba bank): all 28 instruments and 10 drums, 415 zone takes (34.5 M samples),
bit-identical to kankyo.min.js's worker engine; plus 121 takes the bank does not hold, for the instruments on the
new paths (strings, lead violin, trumpet, trombone, bowed cello, choir, flute, koto: each zone 2 semitones above
its root, and as a take beyond the bank's), rendered by the dist script loaded as its own worker, bit-identical
too; the instrument table (zones, keys, tuning, volumes, envelopes, takes) is identical; the sampler's playback
buffers (upsampled for a 44.1, 48 or 96 kHz context) are identical. (On the previous bank, in Chrome, the
first takes the pack's workers render hashed the same as the reference's; not rerun.)

Caveat: the computed harp zones use `Math.pow`/`Math.log` in the page and round to 4 decimals,
as banks.mjs did when it stored them. In V8 (Chrome, Node) they match the stored numbers exactly (checked at
build); another JavaScript engine whose `pow`/`log` differ in the last bit could, at a rounding boundary,
land one unit off in the 4th decimal of a setting.

## Onchain

`loot/loot_contracts/src/fm_pack.cairo`, contract `LootFmPack` (no storage, no constructor arguments):
`pack() -> ByteArray` (base64 of the gzip, 18,380 characters), `chunk_count()`, `chunk_len()` (3,968 =
128 words of 31 bytes, a multiple of 4, so each chunk is base64 on its own), `chunk(i)`, `pack_len()`,
`gzip_len()`, `script_len()`, `pack_sha256()`, `encoding()` (`'gzip+base64'`), `version()`.
The data is `fm_pack_data.cairo` (generated): one string literal per chunk (Cairo string literals hold ASCII
only, hence base64 rather than raw gzip). Compiled (0f2d0ba bank, 18,380 characters): 5,502 CASM felts (limit 81,920), 4,469 Sierra felts (the first bank, 16,908 characters: 5,361 and 4,045); one
class, no split needed (room for about 15 times this much data before a split into data classes, read with
`library_call_syscall`, would be needed). The tests (`fm_pack::tests`) deploy the class and check that
`pack()` and the joined chunks equal `dist/loot-fm-pack.min.js.gz.b64` (read with snforge `read_txt` from
`loot/loot_contracts/data/loot_fm_pack_b64.txt`) and that `pack_sha256()` is its sha256.
