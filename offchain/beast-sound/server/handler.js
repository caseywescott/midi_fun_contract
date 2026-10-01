// Beast Sound endpoint: one Fetch-standard handler (Cloudflare Workers, Vercel, Deno, Bun, Node).
//
//   GET /beasts/{token}            -> JSON: score, hashes, live stats used, links
//   GET /beasts/{token}.json       -> same
//   GET /beasts/{token}.mid        -> Standard MIDI File
//   GET /beasts/{token}/player     -> self-contained HTML player (use as the NFT's animation_url)
//
// {token} is a current mainnet token number (e.g. 52918) or a Beasts V3 116-bit token ID (decimal
// or 0x). Query: ?engine=1|2 (default 1), ?network=sepolia|mainnet for V3 IDs (default sepolia
// until V3 ships on mainnet), ?patch=<patch id> and ?drums=0 (drums off) for the player.
//
// Everything is computed from data Provable Games already publishes; nothing is stored. The score
// is deterministic: anyone can recompute it with @koji/beast-sound and compare score_hash.
import { composeBeast, decodeTokenId, ENGINE_VERSION } from '../src/index.js';
import { NETWORKS, readMainnetBeast, readV3Beast } from '../src/chain.js';
import { PLAYER_JS } from './dist/player.bundle.js';

const CACHE_SECONDS = 300; // live stats (kills, Summit, rank) change; five minutes is plenty
const cache = new Map();

const hex = (x) => '0x' + BigInt(x).toString(16);
const json = (body, status = 200) => new Response(JSON.stringify(body, (k, v) => (typeof v === 'bigint' ? hex(v) : v), 2), {
  status, headers: { 'content-type': 'application/json; charset=utf-8', 'access-control-allow-origin': '*', 'cache-control': `public, max-age=${CACHE_SECONDS}` },
});
const b64 = (bytes) => { let s = ''; for (let i = 0; i < bytes.length; i += 0x8000) s += String.fromCharCode(...bytes.subarray(i, i + 0x8000)); return btoa(s); };
const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

async function loadBeast(token, network) {
  const n = BigInt(token);
  if (n < 1n) throw new Error('token must be positive');
  if (n <= 0xffffffffn) return readMainnetBeast(n);                       // current collection token number
  decodeTokenId(n);                                                         // validates the V3 layout
  return readV3Beast(n, { network: network === 'mainnet' ? NETWORKS.mainnet : NETWORKS.sepolia, decodeTokenId });
}

async function compose(token, engineVersion, network) {
  const key = `${token}:${engineVersion}:${network}`;
  const hit = cache.get(key);
  if (hit && hit.at > Date.now() - CACHE_SECONDS * 1000) return hit.value;
  const got = await loadBeast(token, network);
  const song = composeBeast(got.beast, got.live, { speciesName: got.speciesName, engineVersion });
  const value = { got, song };
  cache.set(key, { at: Date.now(), value });
  if (cache.size > 5000) cache.delete(cache.keys().next().value);
  return value;
}

function summary(url, token, { got, song }) {
  const base = `${url.origin}/beasts/${token}`;
  return {
    name: song.name,
    token: String(token),
    v3_token_id: song.tokenId,
    source: got.source,
    engine: song.engineVersion,
    live: song.live,
    music: {
      tempo_bpm: Math.round(60e6 / song.params.tempo_us),
      duration_seconds: Number(song.durationSeconds.toFixed(2)),
      sections: song.params.section_count,
      voices: song.params.voice_count,
      notes: song.events.length,
      ...(song.ornamentStyle ? { ornament_style: song.ornamentStyle } : {}),
    },
    hashes: { sound_seed: song.soundSeed, motif: song.motifHash, state: song.stateHash, score: song.scoreHash },
    // [time_ticks, duration_ticks, midi_key, velocity, voice]; 480 ticks per beat
    notes: song.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice]),
    midi_base64: b64(song.midi),
    compact: { format: song.engineVersion === 2 ? 'BSN2' : 'BSN1', base64: b64(song.bsn) },
    links: { json: `${base}.json`, midi: `${base}.mid`, player: `${base}/player` },
    verify: 'npm @koji/beast-sound: composeBeast(beast, live, { engineVersion }).scoreHash must equal hashes.score',
  };
}

function playerHtml(token, { song }, opts) {
  const data = {
    name: song.name,
    tempo_us: song.params.tempo_us,
    notes: song.events.map((e) => [e.time, e.duration, e.pitch, e.velocity, e.voice]),
    patch: opts.patch, drums: opts.drums,
  };
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover">
<title>${esc(song.name)}: Beast Sound</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=VT323&display=swap">
<style>
html,body{margin:0;height:100%;background:#000;color:#4af626;font-family:"VT323",ui-monospace,monospace}
body{display:grid;place-items:center;text-shadow:rgba(173,216,230,.55) 1px 0 8px}
main{width:min(92vw,560px);display:grid;gap:14px;text-align:center}
h1{margin:0;font-weight:400;font-size:clamp(28px,7vw,44px);text-transform:uppercase;letter-spacing:.02em;text-shadow:0 0 12px rgba(74,246,38,.65)}
p{margin:0;font-size:20px;color:rgba(74,246,38,.75)}
button{justify-self:center;font:inherit;font-size:26px;padding:10px 28px;background:#4af626;color:#000;border:0;cursor:pointer;text-shadow:none;box-shadow:0 0 20px -2px #33ff33}
button:active{transform:scale(.95)}
.track{height:6px;background:#151515;border:1px solid rgba(74,246,38,.38)}#bar{height:100%;width:0;background:#4af626}
body::after{content:"";position:fixed;inset:0;pointer-events:none;background:repeating-linear-gradient(to bottom,transparent 0 2px,rgba(0,0,0,.22) 2px 3px)}
</style></head><body><main>
<h1>${esc(song.name)}</h1>
<p>${song.events.length} notes · ${Math.round(60e6 / song.params.tempo_us)} bpm · loops until stopped</p>
<button id="play" type="button">▶ PLAY</button>
<div class="track"><div id="bar"></div></div>
<p style="font-size:16px">score ${hex(song.scoreHash).slice(0, 18)}…</p>
</main>
<script>window.BEAST=${JSON.stringify(data).replace(/</g, '\\u003c')};</script>
<script>${PLAYER_JS}</script>
</body></html>`;
}

export async function handleRequest(request) {
  const url = new URL(request.url);
  if (request.method === 'OPTIONS') return new Response(null, { headers: { 'access-control-allow-origin': '*', 'access-control-allow-methods': 'GET' } });
  if (url.pathname === '/' || url.pathname === '') {
    return new Response('Beast Sound\n\nGET /beasts/{token}.json | .mid | /player\n{token}: mainnet token number or Beasts V3 token ID\n?engine=1|2  ?network=sepolia|mainnet  ?patch=chip_tri_lead  ?drums=0\n', { headers: { 'content-type': 'text/plain; charset=utf-8' } });
  }
  const m = url.pathname.match(/^\/beasts\/(0x[0-9a-fA-F]+|\d+)(\.json|\.mid|\/player)?\/?$/);
  if (!m) return json({ error: 'Use /beasts/{token}.json, /beasts/{token}.mid or /beasts/{token}/player' }, 404);
  const token = BigInt(m[1]);
  const kind = m[2] || '.json';
  const engineVersion = Number(url.searchParams.get('engine') || ENGINE_VERSION);
  if (engineVersion !== 1 && engineVersion !== 2) return json({ error: 'engine must be 1 or 2' }, 400);
  const network = url.searchParams.get('network') || 'sepolia';
  let composed;
  try {
    composed = await compose(token, engineVersion, network);
  } catch (e) {
    return json({ error: `Could not read or compose Beast ${token}: ${e.message}` }, 404);
  }
  const headers = { 'access-control-allow-origin': '*', 'cache-control': `public, max-age=${CACHE_SECONDS}` };
  if (kind === '.mid') {
    return new Response(composed.song.midi, { headers: { ...headers, 'content-type': 'audio/midi', 'content-disposition': `inline; filename="beast-${token}.mid"` } });
  }
  if (kind === '/player') {
    // Drums are on by default; ?drums=0 turns them off.
    const opts = { patch: url.searchParams.get('patch') || 'chip_tri_lead', drums: url.searchParams.get('drums') !== '0' };
    return new Response(playerHtml(token, composed, opts), { headers: { ...headers, 'content-type': 'text/html; charset=utf-8' } });
  }
  return json(summary(url, token, composed));
}

export default { fetch: handleRequest };
