// Patches applied to the pinned upstream webaudio-tinysynth.js before it is minified into the page.
// Each `from` must match exactly once, and the result must hash to PATCHED_SHA256, so a changed
// upstream file or patch fails the build instead of shipping something unreviewed.
import { createHash } from 'node:crypto';

export const UPSTREAM = {
  repo: 'https://github.com/g200kg/webaudio-tinysynth',
  commit: '3d75aee4b3f43cbd932265e7d60201fd5b770397', // 2022-12-20, master
  file: 'webaudio-tinysynth.js',
  sha256: 'dd2b1d95d64499dfc3c292858e8c2d6525dc0bcdc345a900b7db207dffaae38c',
  license: 'Apache-2.0',
};

export const PATCHES = [
  {
    // MIDI tempo is microseconds per quarter note. Upstream floors 60e6 / tempo to whole BPM,
    // so 455,000 us (131.87 BPM) plays at 131 BPM and drifts 0.7% (about 0.4 s a minute).
    name: 'fractional-tempo',
    from: 'var val = Math.floor(60000000 / Get3(s, i + 3));',
    to: 'var val = 60000000 / Get3(s, i + 3);',
  },
  {
    // Upstream loops by jumping straight from the last event back to the first. With `loopEnd`
    // (ticks) set, the next pass starts at loopEnd instead, so a loop can be whole bars long.
    name: 'loop-end',
    from: '                  e=this.song.ev[this.playIndex=0];\n                  this.playTick=e.t;\n',
    to: '                  e=this.song.ev[this.playIndex=0];\n'
      + '                  if(this.loopEnd)\n'
      + '                    this.playTime+=(Math.max(this.loopEnd,this.playTick)-this.playTick+e.t)*this.tick2Time;\n'
      + '                  this.playTick=e.t;\n',
  },
];

export const PATCHED_SHA256 = 'c20c90a1fd924f2ce5c106a736007abcd0dc320407a99c2ee3a6f0179eabf2d0';

const sha256 = (s) => createHash('sha256').update(s).digest('hex');

export function patchTinySynth(upstreamSource) {
  if (sha256(upstreamSource) !== UPSTREAM.sha256) throw new Error('webaudio-tinysynth.js does not match the pinned upstream checksum');
  let src = upstreamSource;
  for (const p of PATCHES) {
    const at = src.indexOf(p.from);
    if (at < 0 || src.indexOf(p.from, at + 1) >= 0) throw new Error(`patch ${p.name}: expected exactly one match`);
    src = src.slice(0, at) + p.to + src.slice(at + p.from.length);
  }
  if (sha256(src) !== PATCHED_SHA256) throw new Error(`patched TinySynth checksum ${sha256(src)} != ${PATCHED_SHA256}`);
  return src;
}
