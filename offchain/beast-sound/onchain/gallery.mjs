// Build a gallery of onchain TinySynth sound pages from real mainnet Beasts, spread across complexity.
//   node onchain/gallery.mjs [count=100] [candidates=400]
//   node onchain/gallery.mjs --rebuild     (offline: re-render the pages already in public/onchain)
//
// Samples candidate tokens from the current mainnet collection, reads their traits and live stats,
// composes each (engine v1), keeps `count` spread evenly from the simplest theme to the densest,
// then fetches each one's real token_uri art and writes exactly the page its animation_url would
// hold: public/onchain/beasts/<token>.html (+ .svg thumbnail) and public/onchain/index.html.
// Summit is retired, so pages compose with summit_held_seconds = 0, as BeastMidiProvider does.
// (These are pre-V3 Beasts: their scars are what src/chain.js read, which still counts Summit
// revivals.) --rebuild also writes the genesis Warlock preview (warlock.html, warlock-token-uri.txt).
import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { call, NETWORKS, readMainnetBeast } from '../src/chain.js';
import { composeBeast, encodeTokenId, engine } from '../src/index.js';
import { animationHtml, tokenUri } from './page.js';
import { TINYCHIP_ONCHAIN } from './tinychip/config.mjs';
import { BEATSYNC_ONCHAIN } from './beatsync/config.mjs';

const here = fileURLToPath(new URL('.', import.meta.url));
const out = here + '../public/onchain/';
const COUNT = Number(process.argv[2] || 100);
const CANDIDATES = Number(process.argv[3] || 400);
const net = NETWORKS.mainnet;
// the page script as build.mjs stores it: TinySynth, the optional modules that are switched on, the player
const dist = (f) => readFileSync(here + 'dist/' + f, 'utf8').trim();
const js = [dist('tinysynth.min.js'), ...(TINYCHIP_ONCHAIN ? [dist('tinychip.min.js')] : []), ...(BEATSYNC_ONCHAIN ? [dist('beatsync.min.js')] : []), dist('player.js')].join('\n');
const retired = (live) => ({ ...live, summit_held_seconds: 0 });
const midiFor = (tokenId, live) => Uint8Array.from(engine.toMidiFile(engine.render(engine.decodeTokenId(BigInt(tokenId)), retired(live))));

function row(token, tokenId, beast, live, song) {
  return {
    token, token_id: '0x' + BigInt(tokenId).toString(16), live: retired(live), name: song.name, tier: beast.tier, level: beast.level,
    kills: live.adventurers_killed, scars: live.scars, rank: live.rank, count: live.species_count,
    notes: song.events.length, voices: song.params.voice_count, sections: song.params.section_count,
    bpm: Math.round(60e6 / song.params.tempo_us), seconds: Math.round(song.durationSeconds),
  };
}

if (process.argv[2] === '--rebuild') {
  const rows = JSON.parse(readFileSync(out + 'gallery.json', 'utf8'));
  const list = rows.map((r) => {
    const beast = engine.decodeTokenId(BigInt(r.token_id));
    writeFileSync(out + `beasts/${r.token}.html`, animationHtml(js, midiFor(r.token_id, r.live), readFileSync(out + `beasts/${r.token}.svg`, 'utf8')));
    return row(r.token, r.token_id, beast, r.live, composeBeast(beast, retired(r.live)));
  }).sort((a, b) => a.notes - b.notes || a.token - b.token);
  writeFileSync(out + 'gallery.json', JSON.stringify(list, null, 1));
  writeFileSync(out + 'index.html', indexHtml(list));
  // The genesis Warlock fixture (Sepolia V3) as a stand-alone preview and its full token_uri.
  const fx = JSON.parse(readFileSync(here + 'fixtures/warlock_v3.json', 'utf8'));
  const live = { adventurers_killed: 412, scars: 7, summit_held_seconds: 0, rank: 3, species_count: 1243 };
  const midi = midiFor(fx.token_id, live);
  writeFileSync(out + 'warlock.html', animationHtml(js, midi, Buffer.from(fx.svg_b64, 'base64').toString('utf8')));
  writeFileSync(out + 'warlock-token-uri.txt', tokenUri(readFileSync(here + 'dist/stored.b64', 'utf8'), fx.members, fx.svg_b64, midi));
  console.log(`rebuilt ${list.length} pages + index + Warlock preview`);
  process.exit(0);
}

async function pool(items, limit, fn) {
  const results = new Array(items.length);
  let next = 0;
  await Promise.all(Array.from({ length: limit }, async () => {
    while (next < items.length) {
      const i = next++;
      for (let attempt = 0; ; attempt++) {
        try { results[i] = await fn(items[i], i); break; } catch (e) {
          if (attempt === 8) { results[i] = null; console.warn(`skip ${items[i]}: ${e.message.slice(0, 80)}`); break; }
          // the public RPC rate-limits bursts: back off hard
          await new Promise((r) => setTimeout(r, 2000 * 2 ** Math.min(attempt, 4)));
        }
      }
    }
  }));
  return results;
}

async function tokenSvg(token) {
  const felts = await call(net.rpc, net.beasts, 'token_uri', [BigInt(token), 0n]);
  const n = Number(felts[0]);
  const hexBytes = (w, k) => Buffer.from(w.toString(16).padStart(k * 2, '0'), 'hex');
  const uri = Buffer.concat([...felts.slice(1, 1 + n).map((w) => hexBytes(w, 31)), hexBytes(felts[1 + n], Number(felts[2 + n]))]).toString('utf8');
  const json = Buffer.from(uri.slice(uri.indexOf(',') + 1), 'base64').toString('utf8');
  // The current collection's description holds raw newlines; escape them to parse.
  const meta = JSON.parse(json.replace(/\n/g, '\\n'));
  return Buffer.from(meta.image.slice(meta.image.indexOf(',') + 1), 'base64').toString('utf8');
}

// Deterministic sample of token numbers, plus a few known characters.
const supply = Number((await call(net.rpc, net.beasts, 'total_supply', []))[0]);
let seed = 0x5eed;
const rand = () => ((seed = (seed * 1103515245 + 12345) % 2 ** 31) / 2 ** 31);
const tokens = new Set([52918]);
while (tokens.size < CANDIDATES) tokens.add(1 + Math.floor(rand() * supply));

// Reads are cached (onchain/.gallery-cache.json) so a rate-limited run can simply be rerun.
const cacheFile = here + '.gallery-cache.json';
const cache = existsSync(cacheFile) ? JSON.parse(readFileSync(cacheFile, 'utf8')) : {};
const save = () => writeFileSync(cacheFile, JSON.stringify(cache));
console.log(`reading ${tokens.size} of ${supply} Beasts (${Object.keys(cache).length} cached)…`);
const read = await pool([...tokens], 2, async (token) => {
  if (!cache[token]) { cache[token] = await readMainnetBeast(token); save(); }
  const { beast, live } = cache[token];
  return { token, beast, live, song: composeBeast(beast, retired(live)) };
});
const ok = read.filter(Boolean).sort((a, b) => a.song.events.length - b.song.events.length || a.token - b.token);

// Even spread over the complexity ranking, without repeats.
const picks = [];
for (let i = 0; i < Math.min(COUNT, ok.length); i++) {
  const r = ok[Math.round((i * (ok.length - 1)) / Math.max(1, COUNT - 1))];
  if (!picks.includes(r)) picks.push(r);
}
console.log(`composed ${ok.length}; notes ${ok[0].song.events.length}–${ok.at(-1).song.events.length}; fetching art for ${picks.length}…`);

mkdirSync(out + 'beasts', { recursive: true });
const rows = await pool(picks, 2, async (p) => {
  const svg = await tokenSvg(p.token);
  const tokenId = encodeTokenId(p.beast);
  writeFileSync(out + `beasts/${p.token}.html`, animationHtml(js, midiFor(tokenId, p.live), svg));
  writeFileSync(out + `beasts/${p.token}.svg`, svg);
  return row(p.token, tokenId, p.beast, p.live, p.song);
});
const list = rows.filter(Boolean);
writeFileSync(out + 'gallery.json', JSON.stringify(list, null, 1));
writeFileSync(out + 'index.html', indexHtml(list));
console.log(`wrote ${list.length} pages + index`);

function indexHtml(list) {
  const max = Math.max(...list.map((r) => r.notes));
  const level = (n) => (n <= max * 0.15 ? 'Sparse' : n <= max * 0.4 ? 'Moderate' : n <= max * 0.7 ? 'Rich' : 'Dense');
  const esc = (s) => String(s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const cards = list.map((r, i) => `<li data-level="${level(r.notes)}"><a href="beasts/${r.token}.html">
<span class="n">${String(i + 1).padStart(3, '0')}</span>
<img src="beasts/${r.token}.svg" alt="" loading="lazy" width="50" height="70">
<span class="who"><b>${esc(r.name)}</b><small>#${r.token} · tier ${r.tier} · lvl ${r.level} · ${r.kills} kills${r.rank ? ` · rank ${r.rank}/${r.count}` : ''}</small></span>
<span class="music"><span class="bar"><i style="width:${Math.max(2, (100 * r.notes) / max).toFixed(1)}%"></i></span><small>${r.notes} notes · ${r.voices} voice${r.voices > 1 ? 's' : ''} · ${r.sections} section${r.sections > 1 ? 's' : ''} · ${r.bpm} bpm</small></span>
<span class="tag">${level(r.notes)}</span></a></li>`).join('\n');
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Beast Sound Gallery</title>
<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=VT323&display=swap">
<style>
:root{--g:#4af626;--dim:rgba(74,246,38,.62);--line:rgba(74,246,38,.22);--bg:#000;--card:#070a07}
*{box-sizing:border-box}
code{font:inherit;color:var(--g)}
html,body{margin:0;background:var(--bg);color:var(--g);font-family:"VT323",ui-monospace,monospace}
body::after{content:"";position:fixed;inset:0;pointer-events:none;background:repeating-linear-gradient(to bottom,transparent 0 2px,rgba(0,0,0,.2) 2px 3px)}
header,main{width:min(100% - 32px,920px);margin:0 auto}
header{padding:40px 0 18px}
h1{margin:0;font-weight:400;font-size:clamp(36px,8vw,58px);line-height:1;text-transform:uppercase;text-shadow:0 0 14px rgba(74,246,38,.55)}
p{margin:10px 0 0;font-size:21px;color:var(--dim);max-width:62ch}
nav{display:flex;flex-wrap:wrap;gap:8px;margin:22px 0 6px}
nav button{font:inherit;font-size:19px;padding:4px 14px;background:transparent;color:var(--g);border:1px solid var(--line);cursor:pointer}
nav button[aria-pressed="true"]{background:var(--g);color:#000}
ol{list-style:none;margin:0 0 48px;padding:0;display:grid;gap:6px}
li a{display:grid;grid-template-columns:34px 50px minmax(0,1fr) minmax(0,1fr) 84px;gap:14px;align-items:center;padding:8px 12px;background:var(--card);border:1px solid var(--line);color:inherit;text-decoration:none}
li a:hover,li a:focus-visible{border-color:var(--g);outline:none;box-shadow:0 0 14px -4px var(--g)}
.n{color:var(--dim);font-size:18px}
img{display:block;width:50px;height:70px;object-fit:contain;image-rendering:pixelated}
.who,.music{display:grid;gap:3px;min-width:0}
b{font-weight:400;font-size:23px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
small{font-size:17px;color:var(--dim);white-space:nowrap;overflow:hidden;text-overflow:ellipsis}
.bar{height:8px;border:1px solid var(--line)}.bar i{display:block;height:100%;background:var(--g)}
.tag{justify-self:end;font-size:18px;padding:1px 8px;border:1px solid var(--line)}
li[hidden]{display:none}
@media (max-width:640px){li a{grid-template-columns:50px minmax(0,1fr);row-gap:6px}.n,.tag{display:none}img{grid-row:span 2}}
</style></head><body>
<header>
<h1>Beast Sound Gallery</h1>
<p>${list.length} mainnet Beasts, from the sparest theme to the densest. Each page is exactly what its onchain <code>animation_url</code> would hold: the Beast's own art, its theme as a MIDI file composed onchain from its traits and history, and a TinySynth player. Open one and tap ♪.</p>
<nav aria-label="Filter by complexity">${['All', 'Sparse', 'Moderate', 'Rich', 'Dense'].map((l) => `<button type="button" data-f="${l}" aria-pressed="${l === 'All'}">${l}</button>`).join('')}</nav>
</header>
<main><ol>
${cards}
</ol></main>
<script>
document.querySelector('nav').addEventListener('click', (e) => {
  const f = e.target.dataset.f; if (!f) return;
  document.querySelectorAll('nav button').forEach((b) => b.setAttribute('aria-pressed', b.dataset.f === f));
  document.querySelectorAll('li').forEach((li) => { li.hidden = f !== 'All' && li.dataset.level !== f; });
});
</script>
</body></html>`;
}
