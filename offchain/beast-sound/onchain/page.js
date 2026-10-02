// Reference for the onchain token_uri with sound (onchain/cairo builds the same bytes).
//
// token_uri is plain JSON (data:application/json;utf8,…), not base64: Cairo base64 is costly per
// byte, and encoding the whole JSON was the biggest cost of a sound token_uri. Only the HTML page
// inside animation_url is base64, and the fixed part (head + TinySynth player) is encoded once at
// build time and stored onchain:
//
//   token_uri = 'data:application/json;utf8,{' ++ escape(members)
//     ++ ',"image":"data:image/svg+xml;base64,' ++ svg_b64 ++ '",' ++ <spaces>
//     ++ '"animation_url":"data:text/html;base64,'
//     ++ STORED      b64(PAGE), PAGE = head + player + '<script type="text/plain" id="midi">'
//     ++ b64(D)      D = b64(midi) <spaces> '</script><script type="text/plain" id="art">'
//     ++ svg_b64     the same SVG base64 the NFT already computed for `image`
//     ++ '"}'
//
// PAGE is padded to 279n bytes (9 × 31), so STORED is 372n characters: whole base64 groups and
// whole 31-byte words. The JSON whitespace before the animation_url key puts STORED on a word
// boundary of the output, where Cairo appends it cheaply. D is padded to 3n bytes inside the MIDI
// block (the player strips whitespace), so b64(D) has no '=' and the SVG base64 can follow; its
// trailing '=' sits last in the data URI, where it is legal. escape() writes '%' as %25 and '#'
// as %23. Per call the page encodes only the MIDI, twice (into D, then into the page).

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
export const URI_PREFIX = 'data:application/json;utf8,';

/** Page head, player script and the opening of the MIDI block, padded to 279n bytes. */
export function pageHtml(playerJs) {
  return padTo(`${PAGE_HEAD}<script>${playerJs.replace(/<\/script/gi, '<\\/script')}</script>${MIDI_OPEN}`, 279);
}

/** The constant stored onchain: base64 of the page. */
export function storedSegment(playerJs) {
  return b64(pageHtml(playerJs));
}

/** D: the MIDI's base64, space padding to 3n bytes, then the close of the MIDI block and the art block opening. */
export function midiHtml(midi) {
  return padTo(Buffer.from(midi).toString('base64'), 3, len(MIDI_CLOSE)) + MIDI_CLOSE;
}

/** '%' → %25 and '#' → %23: the only characters a JSON data URI must escape for browsers. */
export const escapeJson = (s) => s.replace(/%/g, '%25').replace(/#/g, '%23');

/**
 * The full token_uri. `members` is the JSON object body without braces and without `image`
 * (e.g. `"name":"Warlock","description":"…","attributes":[…]`); `svgB64` is base64 of the SVG;
 * `midi` is the provider's Standard MIDI File bytes.
 */
export function tokenUri(stored, members, svgB64, midi) {
  let out = `${URI_PREFIX}{${escapeJson(members)},${IMAGE_KEY}${svgB64}",`;
  out = padTo(out, 31, len(URL_KEY)); // JSON whitespace: STORED starts on a 31-byte word boundary
  return out + URL_KEY + stored + b64(midiHtml(midi)) + svgB64 + '"}';
}

/** Parse a token_uri as a marketplace would (plain JSON data URI). */
export function parseTokenUri(uri) {
  if (!uri.startsWith(URI_PREFIX)) throw new Error('expected ' + URI_PREFIX);
  return JSON.parse(decodeURIComponent(uri.slice(URI_PREFIX.length)));
}

/** What the browser ends up rendering for animation_url (for tests and local previews). */
export function animationHtml(playerJs, midi, svg) {
  return pageHtml(playerJs) + midiHtml(midi) + svg;
}
