// Reference for the onchain token_uri with sound (onchain/cairo builds the same bytes).
//
// The NFT already returns data:application/json;base64,<json> with its SVG as `image`. With sound,
// the JSON gains an `animation_url`: an HTML page holding the TinySynth player, the token's MIDI as
// base64 text, and the same SVG. Every piece is aligned to 3 bytes, so base64 runs concatenate and
// the fixed player is encoded once, offline, at both layers:
//
//   token_uri = "data:application/json;base64,"
//     ++ b64(A)  A = '{' members ',' <spaces> '"image":"data:image/svg+xml;base64,'
//     ++ b64(S)  S = svg_b64 '"' <spaces>             (encoded once, appended twice)
//     ++ b64(',  ')                                   (comma + 2 spaces)
//     ++ STORED  = b64('"animation_url":"data:text/html;base64,' ++ b64(PAGE)), built here
//     ++ b64(b64(D))  D = b64(midi) <spaces> '</script><script type="text/plain" id="art">'
//     ++ b64(S)
//     ++ b64('}')
//
// PAGE (9n bytes) ends by opening the inert MIDI block; D (9n bytes) closes it and opens the art
// block, whose content is the SVG: the page's own base64 is b64(PAGE) ++ b64(D) ++ svg_b64. Padding
// spaces sit between JSON tokens or inside the MIDI block (the player strips whitespace); the SVG
// base64 sits last in both data URIs, so its trailing '=' is legal. The MIDI is the only per-call
// content the player adds: it is encoded three times at runtime (into D, into the page, into the JSON).

export const PAGE_HEAD = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Sound</title>'
  + '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}body>img{position:fixed;inset:0;width:100%;height:100%;object-fit:contain}</style></head><body>';
export const URL_KEY = '"animation_url":"data:text/html;base64,';
export const IMAGE_KEY = '"image":"data:image/svg+xml;base64,';
export const MIDI_OPEN = '<script type="text/plain" id="midi">';
export const ART_OPEN = '<script type="text/plain" id="art">';
export const MIDI_CLOSE = '</script>' + ART_OPEN;

const len = (s) => Buffer.byteLength(s, 'utf8');
const b64 = (s) => Buffer.from(s, 'utf8').toString('base64');
const spaces = (n) => ' '.repeat(n);
const padTo = (s, k, extra = 0) => s + spaces((k - ((len(s) + extra) % k)) % k);

/** Page head, player script, and the opening of the MIDI block. 9n bytes, so URL_KEY + its base64 is 3n. */
export function pageHtml(playerJs) {
  let html = padTo(`${PAGE_HEAD}<script>${playerJs.replace(/<\/script/gi, '<\\/script')}</script>${MIDI_OPEN}`, 3);
  while ((len(URL_KEY) + (len(html) / 3) * 4) % 3) html += spaces(3);
  return html;
}

/** The constant stored onchain: base64 of the animation_url key and the page's own base64. */
export function storedSegment(playerJs) {
  return b64(URL_KEY + b64(pageHtml(playerJs)));
}

/** D: the MIDI's base64, space padding, then the close of the MIDI block and the art block opening. 9n bytes. */
export function midiHtml(midi) {
  return padTo(Buffer.from(midi).toString('base64'), 9, len(MIDI_CLOSE)) + MIDI_CLOSE;
}

/**
 * The full token_uri. `members` is the JSON object body without braces and without `image`
 * (e.g. `"name":"Warlock","description":"…","attributes":[…]`); `svgB64` is base64 of the SVG;
 * `midi` is the provider's Standard MIDI File bytes.
 */
export function tokenUri(stored, members, svgB64, midi) {
  const a = padTo(`{${members},`, 3, len(IMAGE_KEY)) + IMAGE_KEY;
  const s = padTo(`${svgB64}"`, 3);
  return 'data:application/json;base64,' + b64(a) + b64(s) + b64(',  ') + stored + b64(b64(midiHtml(midi))) + b64(s) + b64('}');
}

/** What the browser ends up rendering for animation_url (for tests and local previews). */
export function animationHtml(playerJs, midi, svg) {
  return pageHtml(playerJs) + midiHtml(midi) + svg;
}
