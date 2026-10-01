# Beast Sound endpoint

One URL per Beast, computed from data Provable Games already publishes. Nothing is stored and
nothing is added onchain.

| Route | Returns |
|---|---|
| `GET /beasts/{token}/player` | Self-contained HTML player (Loot Survivor style, loops). Use it as the NFT's `animation_url`. |
| `GET /beasts/{token}.mid` | Standard MIDI File |
| `GET /beasts/{token}.json` | Notes, hashes, live stats used, compact score (BSN1/BSN2), links |

`{token}`: a current mainnet token number (e.g. `52918`) or a Beasts V3 token ID (decimal or `0x`).
Query: `?engine=1|2` (default 1), `?network=sepolia|mainnet` (V3 IDs, default sepolia until V3 is
on mainnet), `?patch=chip_tri_lead`, `?drums=0` (the player has chiptune drums on by default).

Live stats (kills, Summit deaths and hours, rank) are read on request and cached for 5 minutes.

## token_uri change (Beasts NFT)

Add one field to the metadata JSON in `metadata_generator.cairo`. It is string concatenation only:
no external call, no extra storage, negligible gas.

```cairo
// inside the metadata JSON object
metadata.append(@",\"animation_url\":\"https://beasts.autonomousaudio.net/beasts/");
metadata.append(@format!("{}", token_id));
metadata.append(@"/player\"");
```

Marketplaces that support HTML `animation_url` (OpenSea, Element, most Starknet galleries) show
the player on the token page. Games can call the `.json` or `.mid` route directly.

## Why a URL and not sound inside token_uri

- Full scores are heavy to compute onchain (engine v1: up to about 350M L2 gas for the largest
  Beast; engine v2 far more), and marketplaces call `token_uri` constantly.
- The V3 design already keeps external calls and heavy work out of `token_uri`.
- The sound stays verifiable: the score is a pure function of the Beast. Anyone can recompute it
  with `@koji/beast-sound` and compare `hashes.score`; the Cairo reference produces the same bytes.

## Run and deploy

```bash
npm install                       # in offchain/beast-sound
node server/build.mjs             # bundle the player into server/dist/player.bundle.js
node server/node.mjs 8787         # local: http://localhost:8787/beasts/52918/player
cd server && npx wrangler deploy  # Cloudflare Workers (or import handler.js on Vercel/Deno/Bun)
```
