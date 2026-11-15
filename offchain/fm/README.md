# Loot FM pack

The Kankyo FM instruments of Loot Dungeon Sound (22 instruments, 10 drums, 240 key zones, 374 zone takes)
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
node pack/bench.mjs [runs]       # Chrome timings, and the zones the pack's workers render hashed against the reference's
node pack/cairo.mjs              # loot/loot_contracts/src/fm_pack_data.cairo and the contract test's fixture
sh scripts/cairo_run.sh snforge test -p loot_contracts --max-threads 2 fm_pack   # from the worktree root
```

`build.mjs` reads the reference by running it in Node (nothing depends on its minified names) and stops if
the compact data does not decode to exactly the reference's definitions. When the bank changes, rebuild
`kankyo.min.js` with `banks.mjs` as before, then run the four commands above.

Sources (`pack/`): `engine.js` (FM, sustained and struck, and the noise drums: the parts of engines.js the
Kankyo bank uses; additive, modal, Karplus-Strong, the STK models, the recorded-attack hybrid and BRR are
left out), `sampler.js` (runtime.js without BRR decoding and bank validation), `gen.js` (per-zone settings
computed instead of stored), `data.js` + `kankyo-data.js` (the patches), `main.js` (bank, render queue,
workers), `ref.mjs` (the reference harness), `demo.src.html`.

## What changed

Size (bytes):

| | raw | gzip | gzip + base64 |
|---|---|---|---|
| kankyo.min.js (reference) | 59,205 | 21,467 | 28,624 |
| loot-fm-pack.min.js | 28,370 | 12,680 | 16,908 |

- The workers run the pack's own source (`'(' + LootFmPack + ')()'` as a Blob) instead of a second copy of
  the engine in a string (15.5 KB).
- Only the engine paths the Kankyo patches use, and the sampler without BRR/base64 decoding and validation
  (the reference carried the whole SNES runtime and every engine).
- Patch data 15.4 KB + 1.1 KB drums -> 7.1 KB: harp and clarinet zones computed per note by their banks.mjs
  formulas (`harpAt`, `clarinetAt`; 5.4 KB of numbers), the bowed-string zones as their fitted numbers only
  (the second player and the attack indices are derived as `stringAt` derives them), and any instrument stored
  as an earlier one plus the keys that differ (`b`: guitar = vibraphone, toms = the first tom, open hat =
  hat, the lead violin = the strings with its own EQ and fit, …). The build checks every decoded definition
  against the reference.

Render speed, same samples (the engine's arithmetic is unchanged; only work that was repeated or multiplied
by zero is gone): a modulator shared by several operators (the string carriers all ride one feedback
modulator) is computed once; operators whose index is zero throughout skip their modulator; index envelopes
that cancel (held = attack) skip their `Math.exp`; the vibrato and pitch wander are evaluated once per sample
instead of up to six times; the attack's `exp` and `(1 - u^4)` are shared between operators; the EQ runs a
filter at a time over the whole buffer from typed arrays; the sampler's upsampler reads straight from the
source away from the edges and loop seam. The queue starts the longest zones first among equal priority.

| one thread, all 374 zone takes | reference | pack |
|---|---|---|
| Node 20 | 17.2 s | 10.7 s |
| Chrome, all 240 first takes (page thread) | 5.61 s | 4.25 s |

Chrome as the lab uses it (6 workers; median of 9 page loads alternating reference and pack, on a shared
10-core Mac under load average 8-12, so the parallel numbers are noisy; `node pack/bench.mjs 9`):

| from the start of loading the script | reference | pack |
|---|---|---|
| script run, bank built | 12 ms | 12 ms |
| a track's zones ready (`need`: flute, harp, cello, strings, kick, snare, hat) | 165 ms | 155 ms |
| those first notes scheduled (time to first sound) | 229 ms | 189 ms |
| main-thread cost of a note in a zone not yet played (building its upsampled buffer) | 10 ms | 4.2 ms |
| every first take ready | 1,516 ms | 1,329 ms |
| JS heap after | 77 MB | 77 MB |

Parity (`node pack/parity.mjs`): all 27 instruments and drums, 374 zone takes, 39.6 M samples, bit-identical
to kankyo.min.js's worker engine; the instrument table (zones, keys, tuning, volumes, envelopes, takes) is
identical; in Chrome the 240 first takes the pack's workers render hash the same as the reference's.

Caveat: the computed harp and clarinet zones use `Math.pow`/`Math.log` in the page and round to 4 decimals,
as banks.mjs did when it stored them. In V8 (Chrome, Node) they match the stored numbers exactly (checked at
build); another JavaScript engine whose `pow`/`log` differ in the last bit could, at a rounding boundary,
land one unit off in the 4th decimal of a setting.

## Onchain

`loot/loot_contracts/src/fm_pack.cairo`, contract `LootFmPack` (no storage, no constructor arguments):
`pack() -> ByteArray` (base64 of the gzip, 16,908 characters), `chunk_count()`, `chunk_len()` (3,968 =
128 words of 31 bytes, a multiple of 4, so each chunk is base64 on its own), `chunk(i)`, `pack_len()`,
`gzip_len()`, `script_len()`, `pack_sha256()`, `encoding()` (`'gzip+base64'`), `version()`.
The data is `fm_pack_data.cairo` (generated): one string literal per chunk (Cairo string literals hold ASCII
only, hence base64 rather than raw gzip). Compiled: 5,361 CASM felts (limit 81,920), 4,045 Sierra felts; one
class, no split needed (room for about 15 times this much data before a split into data classes, read with
`library_call_syscall`, would be needed). The tests (`fm_pack::tests`) deploy the class and check that
`pack()` and the joined chunks equal `dist/loot-fm-pack.min.js.gz.b64` (read with snforge `read_txt` from
`loot/loot_contracts/data/loot_fm_pack_b64.txt`) and that `pack_sha256()` is its sha256.
