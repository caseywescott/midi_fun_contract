// Bundle entry for the onchain Beast Sound library (built by onchain/build.mjs, stored onchain once).
//
// Defines window.BeastSound: the layered v1 API (beast, music, midi, synth, play, fx) plus the flat
// API from the first release (compose, midi, play, stop…). See lib/index.js. On a Beast's
// token_uri page it also mounts the art and the ♪ / MIDI buttons (lib/page.js).
import { v1, flat } from './lib/index.js';
import { mountPage } from './lib/page.js';

window.BeastSound = { ...flat, v1 };
mountPage(window.BeastSound);
