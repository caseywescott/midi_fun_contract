// Snapshot a real Beasts V3 token_uri (Sepolia) into fixtures/<name>.json for tests and previews.
//   node onchain/fetch-fixture.mjs [token_id] [name]     (default: genesis Warlock)
import { mkdirSync, writeFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { call, NETWORKS, readV3Beast } from '../src/chain.js';
import { decodeTokenId } from '../src/index.js';

const here = fileURLToPath(new URL('.', import.meta.url));
const tokenId = BigInt(process.argv[2] || '0x7006400010000000000000000001');
const name = process.argv[3] || 'warlock_v3';
const net = NETWORKS.sepolia;

const felts = await call(net.rpc, net.beastsV3, 'token_uri', [tokenId & ((1n << 128n) - 1n), tokenId >> 128n]);
// ByteArray: [word_count, ...31-byte words, pending_word, pending_len]
const n = Number(felts[0]);
const hexBytes = (w, k) => Buffer.from(w.toString(16).padStart(k * 2, '0'), 'hex');
const uri = Buffer.concat([...felts.slice(1, 1 + n).map((w) => hexBytes(w, 31)), hexBytes(felts[1 + n], Number(felts[2 + n]))]).toString('utf8');
const json = Buffer.from(uri.slice(uri.indexOf(',') + 1), 'base64').toString('utf8');
const meta = JSON.parse(json);

// The JSON object body without braces and without `image`, exactly as the contract emits it.
const image = `"image":${JSON.stringify(meta.image)},`;
if (!json.includes(image)) throw new Error('unexpected image member layout');
const members = json.slice(1, -1).replace(image, '');
const svgB64 = meta.image.slice('data:image/svg+xml;base64,'.length);

const { live } = await readV3Beast(tokenId, { network: net, decodeTokenId });
mkdirSync(here + 'fixtures', { recursive: true });
writeFileSync(here + `fixtures/${name}.json`, JSON.stringify({ token_id: '0x' + tokenId.toString(16), name: meta.name, live, members, svg_b64: svgB64 }, null, 1));
console.log(`${meta.name}: members ${members.length} B, svg_b64 ${svgB64.length} B, live ${JSON.stringify(live)}`);
