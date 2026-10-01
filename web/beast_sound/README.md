# Beast Sound simulator

Single-file page that plays any Loot Survivor Beast's canonical theme in the browser.
The engine is `offchain/beast-sound/src/engine.js`, which mirrors `src/composition/beast_v3_sound.cairo`
and `beast_score.cairo`; parity is checked against Cairo by `scripts/beast_v3_parity.mjs`.

- `index.src.html`: page source with `/*BUNDLE*/` and `/*SNAPSHOT*/` placeholders
- `entry.mjs`: bundle entry that pulls in the offchain package
- `snapshot.min.json`: 300 real mainnet Beasts (rank 1, 2, median and last per species) with Death Mountain kills and Summit deaths/hours; the page also lists the 4 Beasts on the V3 Sepolia stack
- `index.html`: built output. Host it anywhere static (GitHub Pages, Vercel). On a hosted copy,
  "Summon" by mainnet token number reads Starknet live through the Cartridge public RPC. The
  claude.ai preview blocks that request and falls back to the snapshot.

## Build

The engine lives in `offchain/beast-sound` (the `@koji/beast-sound` package); this page bundles it.

```bash
(cd ../../offchain/beast-sound && npm install)
npx esbuild entry.mjs --bundle --minify --format=iife --outfile=/tmp/bundle.js
python3 build.py /tmp/bundle.js snapshot.min.json index.html
```

## Parity

```bash
scarb test -- --include-ignored --filter beast_v3_parity_fixture | grep PARITY > /tmp/parity.txt
node scripts/beast_v3_parity.mjs /tmp/parity.txt   # needs @scure/starknet resolvable
```
