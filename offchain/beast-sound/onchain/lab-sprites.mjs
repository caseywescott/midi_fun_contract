// Beast sprite sheets for the lab page's tempo-synced art (loothero's "BPM animation sync", as in
// Provable-Games/beast-sound-check): each species GIF from the Beasts art contracts
// (fixtures/beast_gifs.json, keys '<species id>' and '<species id>s' for shiny) is decoded into its
// frames (BeatSync's GIF decoder, beatsync/beatsync.js) and laid out as one horizontal PNG sprite
// sheet, frames × 32 wide and 32 high, which the page steps with a discrete SMIL animation.
import { readFileSync } from 'node:fs';
import { deflateSync } from 'node:zlib';
import './beatsync/beatsync.js'; // defines globalThis.BeatSync

const here = new URL('.', import.meta.url);
export const GIFS = JSON.parse(readFileSync(new URL('fixtures/beast_gifs.json', here), 'utf8'));
export const spriteKey = (beast) => `${beast.id}${beast.shiny ? 's' : ''}`;

const CRC = new Uint32Array(256).map((_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
const crc32 = (buf) => { let c = 0xffffffff; for (const b of buf) c = CRC[(c ^ b) & 255] ^ (c >>> 8); return (c ^ 0xffffffff) >>> 0; };
function chunk(type, data) {
  const out = Buffer.alloc(12 + data.length);
  out.writeUInt32BE(data.length, 0); out.write(type, 4, 'latin1'); data.copy(out, 8);
  out.writeUInt32BE(crc32(out.subarray(4, 8 + data.length)), 8 + data.length);
  return out;
}

/** An indexed-colour PNG (with tRNS) of RGBA pixels, falling back to RGBA above 256 colours. */
export function encodePng(width, height, rgba) {
  const colors = new Map(), idx = new Uint8Array(width * height);
  for (let i = 0; i < width * height; i++) {
    const a = rgba[i * 4 + 3], key = a ? (rgba[i * 4] << 24 | rgba[i * 4 + 1] << 16 | rgba[i * 4 + 2] << 8 | a) >>> 0 : 0;
    if (!colors.has(key)) colors.set(key, colors.size);
    idx[i] = colors.get(key) & 255;
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0); ihdr.writeUInt32BE(height, 4); ihdr[8] = 8;
  const parts = [];
  if (colors.size <= 256) {
    ihdr[9] = 3;
    const plte = Buffer.alloc(colors.size * 3), trns = Buffer.alloc(colors.size);
    for (const [key, i] of colors) { plte[i * 3] = key >>> 24; plte[i * 3 + 1] = (key >>> 16) & 255; plte[i * 3 + 2] = (key >>> 8) & 255; trns[i] = key & 255; }
    const raw = Buffer.alloc((width + 1) * height);
    for (let y = 0; y < height; y++) raw.set(idx.subarray(y * width, (y + 1) * width), y * (width + 1) + 1);
    parts.push(chunk('PLTE', plte));
    let last = trns.length; while (last && trns[last - 1] === 255) last--;
    if (last) parts.push(chunk('tRNS', trns.subarray(0, last)));
    parts.push(chunk('IDAT', deflateSync(raw, { level: 9 })));
  } else {
    ihdr[9] = 6;
    const raw = Buffer.alloc((width * 4 + 1) * height);
    for (let y = 0; y < height; y++) Buffer.from(rgba.buffer, rgba.byteOffset + y * width * 4, width * 4).copy(raw, y * (width * 4 + 1) + 1);
    parts.push(chunk('IDAT', deflateSync(raw, { level: 9 })));
  }
  return Buffer.concat([Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]), chunk('IHDR', ihdr), ...parts, chunk('IEND', Buffer.alloc(0))]);
}

/** The species GIF `key` as a sprite sheet: { n: frames, w: frame size, png: base64, gifBytes }. */
export function spriteSheet(key) {
  const b64 = GIFS[key];
  if (!b64) throw new Error('no species GIF for ' + key);
  const gif = globalThis.BeatSync.decodeGif(new Uint8Array(Buffer.from(b64, 'base64')));
  const { width: w, height: h, frames } = gif, n = frames.length, W = w * n;
  const sheet = new Uint8ClampedArray(W * h * 4);
  frames.forEach((f, k) => { for (let y = 0; y < h; y++) sheet.set(f.rgba.subarray(y * w * 4, (y + 1) * w * 4), (y * W + k * w) * 4); });
  if (w !== h) throw new Error(`species GIF ${key} is ${w}x${h}, not square`);
  return { n, w, png: encodePng(W, h, sheet).toString('base64'), gifBytes: Buffer.from(b64, 'base64').length };
}
