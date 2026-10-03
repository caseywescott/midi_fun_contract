// The pinned webaudio-tinysynth.js that is minified into the page: the Provable Games fork, which
// carries the changes the page needs (fractional MIDI tempo, loopEnd, no GUI; see NOTICE). Its sha256
// is pinned, so a changed file fails the build instead of shipping something unreviewed. PATCHES is
// for local changes on top of the fork; each `from` must match exactly once, and the result must
// hash to PATCHED_SHA256.
import { createHash } from 'node:crypto';

export const UPSTREAM = {
  repo: 'https://github.com/Provable-Games/webaudio-tinysynth',
  commit: 'b70ba90d63c5ea657cb67ca98de90d7f778c29bd', // main, 2026-10-02
  file: 'webaudio-tinysynth.js',
  sha256: 'abb2d0fb828ada86b692547560102035cf486fc1fac60ca190b5851235c1ee23',
  license: 'Apache-2.0',
};

export const PATCHES = [];

export const PATCHED_SHA256 = 'abb2d0fb828ada86b692547560102035cf486fc1fac60ca190b5851235c1ee23';

const sha256 = (s) => createHash('sha256').update(s).digest('hex');

export function patchTinySynth(upstreamSource) {
  if (sha256(upstreamSource) !== UPSTREAM.sha256) throw new Error('webaudio-tinysynth.js does not match the pinned checksum');
  let src = upstreamSource;
  for (const p of PATCHES) {
    const at = src.indexOf(p.from);
    if (at < 0 || src.indexOf(p.from, at + 1) >= 0) throw new Error(`patch ${p.name}: expected exactly one match`);
    src = src.slice(0, at) + p.to + src.slice(at + p.from.length);
  }
  if (sha256(src) !== PATCHED_SHA256) throw new Error(`patched TinySynth checksum ${sha256(src)} != ${PATCHED_SHA256}`);
  return src;
}
