// TinyChip build switch.
//   true   the chip pack is stored onchain in the page, before the player (every token_uri has it)
//   false  the page ships without it; a client (site, wallet, game) can still inject
//          dist/tinychip.min.js before the first Play and the player will use it
export const TINYCHIP_ONCHAIN = true;
