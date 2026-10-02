// window.BeastSound: the onchain Beast Sound library.
//
// Layers, each usable alone or together (BeastSound.v1):
//   beast  token → traits → params + seed        music  params + seed → song
//   midi   song → Standard MIDI File              synth  instruments as data + drum kit
//   play   song → sound (handles, routable)       fx     song → song (transpose, layer, concat…)
// A song is { notes: [[time, duration, pitch, velocity, voice], ...] (480 ticks per beat), tempo_us }.
//
// BeastSound.compose(tokenId, live) is the whole Beast pipeline in one call; it equals
// music.generate(beast.params(traits, live), beast.seed(traits)) and the Cairo reference.
import * as beast from './beast.js';
import * as music from './music.js';
import * as midi from './midi.js';
import * as synth from './synth.js';
import * as fx from './fx.js';
import { play, context } from './player.js';

/** Token ID + live stats → song (with tokenId, traits and live attached). */
export function compose(tokenId, stats = {}) {
  const traits = beast.decode(tokenId);
  const live = beast.live(stats, traits);
  return { ...music.generate(beast.params(traits, live), beast.seed(traits)), tokenId: BigInt(tokenId), beast: traits, live };
}

/** Parse the token_uri inputs line "token,kills,scars,held,rank,count" and compose. */
export function fromInputs(line) {
  const [tokenId, adventurers_killed, scars, summit_held_seconds, rank, species_count] = String(line).split(',').map((s) => s.trim());
  return compose(tokenId, { adventurers_killed, scars, summit_held_seconds, rank, species_count });
}

export const v1 = { version: 'beast-sound/engine-v1', beast, music, midi, synth, play, context, fx, compose, fromInputs };

// Flat API kept from the first library release: one global player.
let current = null;
const listeners = new Set();
const notify = () => listeners.forEach((fn) => fn(!!current));
export const flat = {
  version: v1.version,
  compose, fromInputs,
  midi: midi.write,
  midiUrl: midi.url,
  decodeTokenId: beast.decode,
  play(song, opts) {
    if (current) current.stop();
    const h = play(song, opts);
    current = h;
    h.onEnd(() => { if (current === h) { current = null; notify(); } });
    notify();
    return h;
  },
  stop() { if (current) current.stop(); },
  isPlaying: () => !!current,
  onPlayingChange: (fn) => { listeners.add(fn); return () => listeners.delete(fn); },
};
