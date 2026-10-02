// Reference for the onchain token_uri with sound (onchain/cairo builds the same bytes).
//
// token_uri is plain JSON, not base64: Cairo base64 costs ~70K L2 gas per byte, and base64-encoding
// the whole JSON is the biggest cost in today's token_uri. Only the HTML page inside animation_url is
// base64, and almost all of it is encoded once at build time and stored onchain:
//
//   token_uri = 'data:application/json;utf8,{' ++ escape(members)
//     ++ ',"image":"data:image/svg+xml;base64,' ++ svg_b64 ++ '",' ++ <spaces>
//     ++ '"animation_url":"data:text/html;base64,'
//     ++ STORED                   HEAD ++ MODULE_1 ++ … ++ MODULE_n   (built here, stored onchain)
//     ++ b64(line)                the inputs or notes line (~100 bytes: the only per-call encoding)
//     ++ svg_b64                  the same SVG base64 the NFT already computed for `image`
//     ++ '"}'
//
// escape() turns '%' and '#' into %25 / %23 so the data URI is unambiguous (the rest of the JSON is
// already URI-safe for browsers). The page is the head plus the library's modules
// (onchain/modules.mjs), each piece padded to 279n bytes (9 × 31): its base64 is 372n characters,
// whole base64 groups and whole 31-byte words, so pieces concatenate and Cairo appends them at word
// boundaries. JSON whitespace before the animation_url key word-aligns STORED in the output.

export const PAGE_HEAD = '<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Beast</title>'
  + '<style>html,body{margin:0;height:100%;background:#000;overflow:hidden}body>img{position:fixed;inset:0;width:100%;height:100%;object-fit:contain}</style></head><body>';
export const URI_PREFIX = 'data:application/json;utf8,';
export const IMAGE_KEY = '"image":"data:image/svg+xml;base64,';
export const URL_KEY = '"animation_url":"data:text/html;base64,';

const len = (s) => Buffer.byteLength(s, 'utf8');
const b64 = (s) => Buffer.from(s, 'utf8').toString('base64');
const spaces = (n) => ' '.repeat(n);
const padTo = (s, k, extra = 0) => s + spaces((k - ((len(s) + extra) % k)) % k);

const asList = (modules) => (typeof modules === 'string' ? [{ name: 'composer', js: modules }] : modules);

/** One module as its page piece: <script>…</script>, padded to 279n bytes. */
export const modulePiece = (js) => padTo(`<script>${js.replace(/<\/script/gi, '<\\/script')}</script>`, 279);

/** The page head piece, padded to 279n bytes. */
export const headPiece = () => padTo(PAGE_HEAD, 279);

/** Head + module pieces: the HTML that precedes the per-token line. */
export function pageHtml(modules) {
  return headPiece() + asList(modules).map((m) => modulePiece(m.js)).join('');
}

/** The stored segments, each base64 of its piece: HEAD (page contract) and one per module contract. */
export function storedSegments(modules) {
  return {
    head: b64(headPiece()),
    modules: asList(modules).map((m) => ({ name: m.name, segment: b64(modulePiece(m.js)) })),
  };
}

/** All stored segments concatenated, in load order: what token_uri splices in. */
export function storedSegment(modules) {
  const { head, modules: mods } = storedSegments(modules);
  return head + mods.map((m) => m.segment).join('');
}

/**
 * The per-token line, padded to 3n bytes so its base64 has no '=' and the SVG base64 can follow.
 * Values are decimal. It ends by opening an inert text block that holds the SVG (the rest of the
 * document): the Beasts SVG uses XML-only syntax (`<xhtml:img/>` in a foreignObject) that the HTML
 * parser cannot inline, so the library shows it through an <img>, as marketplaces render `image`.
 */
export const ART_OPEN = '<script type="text/plain" id="art">';
export function inputsHtml(tokenId, live) {
  const v = [tokenId, live.adventurers_killed, live.scars, live.summit_held_seconds, live.rank, live.species_count].map((x) => BigInt(x).toString());
  return padTo(`<script>BEAST_SOUND="${v.join(',')}"</script>`, 3, len(ART_OPEN)) + ART_OPEN;
}

/** The felts line for a page driven by notes the chain computed (BSN1 or BSI1 felts as 0x-hex). */
export function notesHtml(felts) {
  const v = felts.map((f) => '0x' + BigInt(f).toString(16));
  return padTo(`<script>BEAST_NOTES="${v.join(',')}"</script>`, 3, len(ART_OPEN)) + ART_OPEN;
}

/** '%' → %25 and '#' → %23: the only characters a JSON data URI must escape for browsers. */
export const escapeJson = (s) => s.replace(/%/g, '%25').replace(/#/g, '%23');

/**
 * The full token_uri around one per-token line (inputsHtml or notesHtml). `members` is the JSON
 * object body without braces and without `image` (e.g. `"name":"Warlock","description":"…",
 * "attributes":[…]`); `svgB64` is base64 of the SVG.
 */
export function tokenUriWithLine(stored, members, svgB64, lineHtml) {
  let out = `${URI_PREFIX}{${escapeJson(members)},${IMAGE_KEY}${svgB64}",`;
  out = padTo(out, 31, len(URL_KEY)); // JSON whitespace: STORED starts on a 31-byte word boundary
  return out + URL_KEY + stored + b64(lineHtml) + svgB64 + '"}';
}

/** token_uri for the inputs page: the library composes from token ID + stats. */
export const tokenUri = (stored, members, svgB64, tokenId, live) => tokenUriWithLine(stored, members, svgB64, inputsHtml(tokenId, live));

/** token_uri for the notes page: the chain composed; the page plays the felts. */
export const tokenUriWithNotes = (stored, members, svgB64, felts) => tokenUriWithLine(stored, members, svgB64, notesHtml(felts));

/** Parse a token_uri as a marketplace would (plain JSON data URI). */
export function parseTokenUri(uri) {
  if (!uri.startsWith(URI_PREFIX)) throw new Error('expected ' + URI_PREFIX);
  return JSON.parse(decodeURIComponent(uri.slice(URI_PREFIX.length)));
}

/** What the browser ends up rendering for animation_url (for tests and local previews). */
export function animationHtml(modules, tokenId, live, svg) {
  return pageHtml(modules) + inputsHtml(tokenId, live) + svg;
}

/** The notes page as the browser renders it. */
export function animationHtmlWithNotes(modules, felts, svg) {
  return pageHtml(modules) + notesHtml(felts) + svg;
}
