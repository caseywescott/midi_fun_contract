// Reference encoding: fixed HTML is encoded twice at build time; only dynamic MIDI/art is encoded
// at runtime. Fixed HTML ends at a 3-byte boundary; its JSON prefix ends at another 3-byte boundary.
export const PAGE_HEAD = '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Collectible music</title>'
  + '<style>html,body{margin:0;height:100%;background:#000;color:#fff;font:16px system-ui}#artwork{position:fixed;inset:0;width:100%;height:100%;object-fit:contain}.controls{position:fixed;bottom:16px;left:50%;transform:translateX(-50%);display:flex;gap:8px;align-items:center;background:#111e;padding:12px;border-radius:12px}button{font:inherit;cursor:pointer}#status{position:fixed;top:8px;left:8px;background:#111e;padding:6px}</style></head><body>'
  + '<img id="artwork" alt="Collectible artwork"><div id="status" role="status">Tap Play to listen</div><div class="controls"><button id="play" type="button">Play</button><button id="stop" type="button">Stop</button><button id="restart" type="button">Restart</button><label><input id="loop" type="checkbox">Loop</label></div>';
export const URL_KEY = '"animation_url":"data:text/html;base64,';
export const IMAGE_KEY = '"image":"data:image/svg+xml;base64,';
export const MIDI_OPEN = '<script type="text/plain" id="midi">';
export const ART_OPEN = '<script type="text/plain" id="art">';
const len = s => Buffer.byteLength(s, 'utf8');
const b64 = s => Buffer.from(s).toString('base64');
const padTo = (s, n) => s + ' '.repeat((n - len(s) % n) % n);

export function pageHtml(playerJs) {
  let html = padTo(`${PAGE_HEAD}<script>${playerJs.replace(/<\/script/gi, '<\\/script')}</script>${MIDI_OPEN}`, 3);
  while ((len(URL_KEY) + len(html) / 3 * 4) % 3) html += '   ';
  return html;
}
export function storedSegment(playerJs) { return b64(URL_KEY + b64(pageHtml(playerJs))); }

// Base64 is a closed inert text payload; share the encoded long artwork prefix at both layers.
export function midiOpenHtml(midi) {
  let head = b64(midi) + '</script>';
  while ((len(head) + len(ART_OPEN)) % 9) head += ' ';
  return head + ART_OPEN;
}
export function midiHtml(midi, svgB64) { return midiOpenHtml(midi) + svgB64 + '</script></body></html>'; }
export function tokenUri(stored, members, svgB64, midi) {
  let prefix = `{${members},`;
  while ((len(prefix) + len(IMAGE_KEY)) % 3) prefix += ' ';
  prefix += IMAGE_KEY;
  const count = Math.floor(len(svgB64) / 279) * 279;
  const artPrefix = svgB64.slice(0, count), artSuffix = svgB64.slice(count);
  const artOnce = b64(artPrefix);
  const imageTail = padTo(artSuffix + '\",', 3);
  const jsonTail = b64(artSuffix + '</script></body></html>') + '\"}';
  return 'data:application/json;base64,' + b64(prefix) + artOnce + b64(imageTail) + stored
    + b64(b64(midiOpenHtml(midi))) + b64(artOnce) + b64(jsonTail);
}
export function animationHtml(playerJs, midi, svgB64) { return pageHtml(playerJs) + midiHtml(midi, svgB64); }
