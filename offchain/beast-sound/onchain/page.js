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
//     ++ STORED  = HEAD ++ MODULE_1 ++ … ++ MODULE_n   (built here; each stored onchain, see below)
//     ++ b64(I)  I = b64(inputs line)                 (~100 bytes: the only new per-call encoding)
//     ++ b64(S)
//     ++ b64('}')
//
// JSON allows the padding spaces between tokens; the SVG base64 sits last in both data URIs, so its
// trailing '=' is legal; every other run is a whole number of 3-byte groups.
//
// The page is the head plus the library's modules (onchain/modules.mjs), each a <script> padded to
// 9n bytes. 9n bytes base64-encode to 12n characters, a whole number of 3-byte groups again, so each
// piece can be base64-encoded twice on its own and the results concatenate:
//   HEAD     = b64('"animation_url":"data:text/html;base64,' ++ b64(PAGE_HEAD padded))
//   MODULE_k = b64(b64('<script>' module_k '</script>' padded))

export const PAGE_HEAD = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Beast</title>'
  + '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}body>img{position:fixed;inset:0;width:100%;height:100%;object-fit:contain}</style></head><body>';
export const URL_KEY = '"animation_url":"data:text/html;base64,';
export const IMAGE_KEY = '"image":"data:image/svg+xml;base64,';

const len = (s) => Buffer.byteLength(s, 'utf8');
const b64 = (s) => Buffer.from(s, 'utf8').toString('base64');
const spaces = (n) => ' '.repeat(n);
const padTo = (s, k, extra = 0) => s + spaces((k - ((len(s) + extra) % k)) % k);

const asList = (modules) => (typeof modules === 'string' ? [{ name: 'composer', js: modules }] : modules);

// Word alignment: Cairo ByteArrays hold 31-byte words, and appending at a word boundary costs a
// fraction of appending mid-word. A piece of 279n bytes (9 × 31) double-encodes to 496n characters
// (16 × 31), so module segments are whole words and the library assembles at word boundaries.

/** One module as its page piece: <script>…</script>, padded to 279n bytes. */
export const modulePiece = (js) => padTo(`<script>${js.replace(/<\/script/gi, '<\\/script')}</script>`, 279);

/**
 * The page head piece: 9k bytes with k ≡ 20 (mod 31), so that HEAD, b64(URL_KEY ++ b64(piece)),
 * is 52 + 16k characters: a whole number of 31-byte words.
 */
export function headPiece() {
  let html = padTo(PAGE_HEAD, 9);
  while ((len(html) / 9) % 31 !== 20) html += spaces(9);
  return html;
}

/** Head + module pieces: the HTML that precedes the per-token inputs line. */
export function pageHtml(modules) {
  return headPiece() + asList(modules).map((m) => modulePiece(m.js)).join('');
}

/** The stored segments: HEAD (kept by the page contract) and one per module contract. */
export function storedSegments(modules) {
  return {
    head: b64(URL_KEY + b64(headPiece())),
    modules: asList(modules).map((m) => ({ name: m.name, segment: b64(b64(modulePiece(m.js))) })),
  };
}

/** All stored segments concatenated, in load order: what token_uri splices in. */
export function storedSegment(modules) {
  const { head, modules: mods } = storedSegments(modules);
  return head + mods.map((m) => m.segment).join('');
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
 * The felts line for a page driven by notes the chain computed: BSN1 felts as 0x-hex
 * (e.g. the Cairo composer's get_score_notes), padded like the inputs line.
 */
export function notesHtml(felts) {
  const v = felts.map((f) => '0x' + BigInt(f).toString(16));
  return padTo(`<script>BEAST_NOTES="${v.join(',')}"</script>`, 9, len(ART_OPEN)) + ART_OPEN;
}

/**
 * The full token_uri around one per-token line (inputsHtml or notesHtml). `members` is the JSON
 * object body without braces and without `image` (e.g. `"name":"Warlock","description":"…",
 * "attributes":[…]`); `svgB64` is base64 of the SVG.
 */
export function tokenUriWithLine(stored, members, svgB64, lineHtml) {
  const s = padTo(`${svgB64}"`, 3);
  // Extra JSON whitespace (3 spaces = 4 base64 characters) until the library lands on a word boundary.
  let pre = padTo(`{${members},`, 3, len(IMAGE_KEY));
  const before = () => 29 + ((len(pre) + len(IMAGE_KEY)) / 3) * 4 + (len(s) / 3) * 4 + 4;
  while (before() % 31 !== 0) pre += spaces(3);
  const a = pre + IMAGE_KEY;
  return 'data:application/json;base64,' + b64(a) + b64(s) + b64(',  ') + stored + b64(b64(lineHtml)) + b64(s) + b64('}');
}

/** token_uri for the inputs page: the library composes from token ID + stats. */
export const tokenUri = (stored, members, svgB64, tokenId, live) => tokenUriWithLine(stored, members, svgB64, inputsHtml(tokenId, live));

/** token_uri for the notes page: the chain composed; the page plays the felts. */
export const tokenUriWithNotes = (stored, members, svgB64, felts) => tokenUriWithLine(stored, members, svgB64, notesHtml(felts));

/** What the browser ends up rendering for animation_url (for tests and local previews). */
export function animationHtml(modules, tokenId, live, svg) {
  return pageHtml(modules) + inputsHtml(tokenId, live) + svg;
}

/** The notes page as the browser renders it. */
export function animationHtmlWithNotes(modules, felts, svg) {
  return pageHtml(modules) + notesHtml(felts) + svg;
}
