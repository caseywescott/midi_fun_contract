// Reference for the onchain token_uri with sound (onchain/cairo builds the same bytes).
//
// The Beasts NFT already returns data:application/json;base64,<json> with the animated SVG as
// `image`. With sound, the JSON gains an `animation_url`: an HTML page holding the composer script,
// one line of per-token inputs and the same SVG. Done naively that means base64-encoding ~85 KB more
// on every call. Instead every piece is aligned to 3 bytes, so base64 runs concatenate:
//
//   token_uri = "data:application/json;base64,"
//     ++ b64(A)  A = '{' members ',' <spaces> '"image":"data:image/svg+xml;base64,'
//     ++ b64(S)  S = svg_b64 '"' <spaces>             (encoded once, appended twice)
//     ++ b64(', ')                                    (comma + 2 spaces)
//     ++ STORED  = b64('"animation_url":"data:text/html;base64,' ++ PAGE_B64), built here, stored onchain
//     ++ b64(I)  I = b64(inputs line)                 (~100 bytes: the only new per-call encoding)
//     ++ b64(S)
//     ++ b64('}')
//
// JSON allows the padding spaces between tokens; the SVG base64 sits last in both data URIs, so its
// trailing '=' is legal; every other run is a whole number of 3-byte groups.

export const PAGE_HEAD = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Beast</title>'
  + '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}body>img{position:fixed;inset:0;width:100%;height:100%;object-fit:contain}</style></head><body>';
export const URL_KEY = '"animation_url":"data:text/html;base64,';
export const IMAGE_KEY = '"image":"data:image/svg+xml;base64,';

const len = (s) => Buffer.byteLength(s, 'utf8');
const b64 = (s) => Buffer.from(s, 'utf8').toString('base64');
const spaces = (n) => ' '.repeat(n);
const padTo = (s, k, extra = 0) => s + spaces((k - ((len(s) + extra) % k)) % k);

/** Page head + composer script. Padded to 3n bytes, and so that URL_KEY + its base64 is 3n bytes. */
export function pageHtml(composerJs) {
  let html = padTo(`${PAGE_HEAD}<script>${composerJs.replace(/<\/script/gi, '<\\/script')}</script>`, 3);
  while ((len(URL_KEY) + (len(html) / 3) * 4) % 3) html += spaces(3);
  return html;
}

/** The constant stored onchain: base64 of the animation_url key and the page's own base64. */
export function storedSegment(composerJs) {
  return b64(URL_KEY + b64(pageHtml(composerJs)));
}

/**
 * The per-token line, padded to 9n bytes so its base64 is 3n bytes. Values are decimal. It ends by
 * opening an inert text block that holds the SVG (the rest of the document): the Beasts SVG uses
 * XML-only syntax (`<xhtml:img/>` in a foreignObject) that the HTML parser cannot inline, so the
 * composer shows it through an <img>, exactly as marketplaces render `image`.
 */
export const ART_OPEN = '<script type="text/plain" id="art">';
export function inputsHtml(tokenId, live) {
  const v = [tokenId, live.adventurers_killed, live.scars, live.summit_held_seconds, live.rank, live.species_count].map((x) => BigInt(x).toString());
  return padTo(`<script>BEAST_SOUND="${v.join(',')}"</script>`, 9, len(ART_OPEN)) + ART_OPEN;
}

/**
 * The full token_uri. `members` is the JSON object body without braces and without `image`
 * (e.g. `"name":"Warlock","description":"…","attributes":[…]`); `svgB64` is base64 of the SVG.
 */
export function tokenUri(stored, members, svgB64, tokenId, live) {
  const a = padTo(`{${members},`, 3, len(IMAGE_KEY)) + IMAGE_KEY;
  const s = padTo(`${svgB64}"`, 3);
  const i = b64(inputsHtml(tokenId, live));
  return 'data:application/json;base64,' + b64(a) + b64(s) + b64(',  ') + stored + b64(i) + b64(s) + b64('}');
}

/** What the browser ends up rendering for animation_url (for tests and local previews). */
export function animationHtml(composerJs, tokenId, live, svg) {
  return pageHtml(composerJs) + inputsHtml(tokenId, live) + svg;
}
