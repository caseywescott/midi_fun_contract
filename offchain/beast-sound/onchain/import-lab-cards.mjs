// Import official rendered outputs, without an RPC or a dependency on the production renderer.
// node onchain/import-lab-cards.mjs <beast-sound-check>/renditions/<deployment>
import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { gunzipSync } from 'node:zlib';
import { createHash } from 'node:crypto';

const root = process.argv[2];
if (!root) throw new Error('usage: node onchain/import-lab-cards.mjs <rendition-set directory>');
const read = (path) => readFileSync(resolve(root, path));
const sha = (bytes) => createHash('sha256').update(bytes).digest('hex');
const manifestBytes = read('manifest.json'), manifest = JSON.parse(manifestBytes);
const fragments = JSON.parse(gunzipSync(read('fragments.json.gz')));
const ref = /\0([a-f0-9]{64})\0/g;
const expand = (s) => s.replace(ref, (_, h) => {
  if (!(h in fragments) || sha(fragments[h]) !== h) throw new Error('invalid fragment ' + h);
  return fragments[h];
});
const output = {
  source: {
    repository: 'https://github.com/Provable-Games/beast-sound-check',
    deployment: manifest.deployment, blockNumber: manifest.blockNumber,
    manifestSha256: sha(manifestBytes), record: manifest.record,
    renderer: manifest.contracts.beasts_renderer_classic,
  },
  fragments: {}, cards: {}, gifs: {}, tokens: [],
};
for (let id = 1; id <= 75; id++) for (const shiny of [false, true]) {
  const token = manifest.tokens.find((t) => t.speciesId === id && (shiny ? t.kind === 'genesis' : t.kind === 'rendition' && t.visualEffects === 2));
  if (!token || !token.notes || token.shiny !== shiny) throw new Error('missing notes rendition for ' + id);
  const s = JSON.parse(gunzipSync(read(token.file))), svg = expand(s.svg);
  // Rebuild and verify the entire original token_uri before using its SVG or GIF.
  const image = s.image + Buffer.from(svg).toString('base64');
  const html = expand(s.html).split('\0I\0').join(image);
  const page = s.page + Buffer.from(html).toString('base64');
  const json = expand(s.json).split('\0I\0').join(image).split('\0P\0').join(page);
  const uri = s.uri + Buffer.from(json).toString('base64');
  if (Buffer.byteLength(uri) !== token.bytes || sha(uri) !== token.sha256) throw new Error('token_uri mismatch: ' + token.tokenId);
  const gif = /data:image\/gif;base64,([A-Za-z0-9+/]+=*)/.exec(svg)?.[1];
  if (!gif || !svg.includes('data-notes-bg')) throw new Error('missing art or notes window: ' + id);
  output.gifs[id + (shiny ? 's' : '')] = gif;
  if (shiny) {
    output.cards[id] = s.svg;
    for (const [, h] of s.svg.matchAll(ref)) output.fragments[h] = fragments[h];
  }
  output.tokens.push({ speciesId: id, shiny, tokenId: token.tokenId, tokenUriSha256: token.sha256, svgSha256: sha(svg) });
}
writeFileSync(new URL('./fixtures/lab-cards.json', import.meta.url), JSON.stringify(output) + '\n');
console.log('Imported 75 Genesis card templates and 150 verified GIFs from ' + manifest.deployment);
