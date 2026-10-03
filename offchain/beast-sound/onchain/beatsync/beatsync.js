// BeatSync: lock a token's animated GIF art to the music, on the audio clock.
//
// Browsers give no control over a native GIF (no play, pause, seek or frame index), so its frames
// drift against the music. BeatSync takes the frame timing over: it finds the GIF inside the token's
// SVG, decodes its frames (a small LZW decoder, no dependencies), builds one copy of the SVG per frame
// with that frame as a PNG, stacks them over the original <img>, and on every animation frame shows
// the copy for the current audible position of the tinysynth player. Stopped, the original native
// GIF shows again. Sound and picture follow one clock, so they never drift, however long it loops.
//
//   BeatSync.attach({ img, svg, mode })   img: the page's art <img>; svg: the SVG text; mode:
//                                         'beat' (one frame per eighth note), 'native' (the GIF's own
//                                         frame delays, timed by the audio clock) or 'off'.
//                                         Returns { frames, delays, mode, setMode, shown } or null if
//                                         the SVG has no animated GIF.
//   BeatSync.decodeGif(bytes)             { width, height, frames: [{ delay (ms), rgba }] }
//   BeatSync.audibleTick(synth)           the tick being heard now, or null when stopped
(function (root) {
  // ── GIF decoding ─────────────────────────────────────────────────
  function lzw(minSize, data, count) {
    const clear = 1 << minSize, eoi = clear + 1;
    const prefix = new Int16Array(4096), suffix = new Uint8Array(4096), first = new Uint8Array(4096), stack = new Uint8Array(4097);
    for (let i = 0; i < clear; i++) { prefix[i] = -1; suffix[i] = i; first[i] = i; }
    const out = new Uint8Array(count);
    let size = minSize + 1, next = eoi + 1, prev = -1, acc = 0, bits = 0, pos = 0, o = 0;
    while (o < count) {
      while (bits < size) { if (pos >= data.length) return out; acc |= data[pos++] << bits; bits += 8; }
      const code = acc & ((1 << size) - 1);
      acc >>>= size; bits -= size;
      if (code === clear) { size = minSize + 1; next = eoi + 1; prev = -1; continue; }
      if (code === eoi) break;
      if (prev < 0) { out[o++] = suffix[code]; prev = code; continue; }
      let c = code, sp = 0;
      if (c >= next) { stack[sp++] = first[prev]; c = prev; }      // the code being defined (KwKwK)
      while (c >= clear) { stack[sp++] = suffix[c]; c = prefix[c]; }
      stack[sp++] = c;
      if (next < 4096) {
        prefix[next] = prev; suffix[next] = c; first[next] = first[prev];
        next++;
        if (next === 1 << size && size < 12) size++;
      }
      while (sp && o < count) out[o++] = stack[--sp];
      prev = code;
    }
    return out;
  }

  function decodeGif(b) {
    const w = b[6] | (b[7] << 8), h = b[8] | (b[9] << 8), flags = b[10];
    let p = 13, gct = null;
    if (flags & 0x80) { const n = 1 << ((flags & 7) + 1); gct = b.subarray(p, p + 3 * n); p += 3 * n; }
    const frames = [];
    let canvas = new Uint8ClampedArray(w * h * 4), gce = { delay: 0, transparent: -1, disposal: 0 };
    const skipBlocks = () => { while (b[p]) p += b[p] + 1; p++; };
    while (p < b.length) {
      const t = b[p++];
      if (t === 0x21) {
        const label = b[p++];
        if (label === 0xf9) {
          const pf = b[p + 1];
          gce = { disposal: (pf >> 2) & 7, delay: b[p + 2] | (b[p + 3] << 8), transparent: pf & 1 ? b[p + 4] : -1 };
          p += b[p] + 1;
          skipBlocks();
        } else skipBlocks();
      } else if (t === 0x2c) {
        const x = b[p] | (b[p + 1] << 8), y = b[p + 2] | (b[p + 3] << 8), fw = b[p + 4] | (b[p + 5] << 8), fh = b[p + 6] | (b[p + 7] << 8), lf = b[p + 8];
        p += 9;
        let ct = gct;
        if (lf & 0x80) { const n = 1 << ((lf & 7) + 1); ct = b.subarray(p, p + 3 * n); p += 3 * n; }
        const minSize = b[p++], data = [];
        while (b[p]) { const n = b[p++]; for (let i = 0; i < n; i++) data.push(b[p + i]); p += n; }
        p++;
        const index = lzw(minSize, data, fw * fh);
        // interlaced rows arrive in four passes: 0,8,16…  4,12…  2,6…  1,3,5…
        const rows = [];
        if (lf & 0x40) for (const [start, step] of [[0, 8], [4, 8], [2, 4], [1, 2]]) for (let r = start; r < fh; r += step) rows.push(r);
        const before = gce.disposal === 3 ? canvas.slice() : null;
        for (let i = 0; i < fw * fh; i++) {
          const c = index[i];
          if (c === gce.transparent || !ct) continue;
          const row = rows.length ? rows[Math.floor(i / fw)] : Math.floor(i / fw), col = i % fw;
          const px = x + col, py = y + row;
          if (px >= w || py >= h) continue;
          const o = (py * w + px) * 4;
          canvas[o] = ct[c * 3]; canvas[o + 1] = ct[c * 3 + 1]; canvas[o + 2] = ct[c * 3 + 2]; canvas[o + 3] = 255;
        }
        frames.push({ delay: (gce.delay || 10) * 10, rgba: canvas.slice() });
        if (gce.disposal === 2) {
          for (let r = y; r < Math.min(h, y + fh); r++) canvas.fill(0, (r * w + x) * 4, (r * w + Math.min(w, x + fw)) * 4);
        } else if (gce.disposal === 3) canvas = before;
        gce = { delay: 0, transparent: -1, disposal: 0 };
      } else break; // 0x3b trailer
    }
    return { width: w, height: h, frames };
  }

  // ── the tinysynth clock ──────────────────────────────────────────
  // tinysynth schedules ahead: playTick is the last tick sent, due at audio time playTime, and
  // tick2Time is seconds per tick. What is heard now is behind that by (playTime - now) / tick2Time.
  function audibleTick(s) {
    if (!s || !s.playing || !s.actx || !s.tick2Time) return null;
    const loop = s.loopEnd || s.maxTick;
    const t = s.playTick - (s.playTime - s.actx.currentTime) / s.tick2Time;
    return loop > 0 ? ((t % loop) + loop) % loop : Math.max(0, t);
  }

  function attach({ img, svg, mode = 'beat', synth = () => root.SOUND && root.SOUND.synth }) {
    const m = /data:image\/gif;base64,([A-Za-z0-9+/=]+)/.exec(svg || '');
    if (!m || !img) return null;
    const gif = decodeGif(Uint8Array.from(atob(m[1]), (c) => c.charCodeAt(0)));
    if (gif.frames.length < 2) return null;
    // one copy of the art per frame, the GIF swapped for that frame as a PNG, stacked over the original
    const layers = gif.frames.map((f) => {
      const cv = document.createElement('canvas');
      cv.width = gif.width; cv.height = gif.height;
      cv.getContext('2d').putImageData(new ImageData(f.rgba, gif.width, gif.height), 0, 0);
      const el = img.cloneNode();
      el.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(svg.replace(m[0], cv.toDataURL('image/png')));
      el.style.visibility = 'hidden';
      el.setAttribute('aria-hidden', 'true');
      img.parentNode.insertBefore(el, img.nextSibling);
      return el;
    });
    const delays = gif.frames.map((f) => f.delay), cycle = delays.reduce((a, d) => a + d, 0);
    const state = { mode, shown: -1 };
    const show = (k) => {
      if (k === state.shown) return;
      layers.forEach((el, i) => { el.style.visibility = i === k ? 'visible' : 'hidden'; });
      img.style.visibility = k < 0 ? 'visible' : 'hidden';
      state.shown = k;
    };
    const frameAt = (s, tick) => {
      if (state.mode === 'beat') return Math.floor(tick / (s.song.timebase / 8)) % layers.length; // eighth notes
      let ms = (tick * s.tick2Time * 1000) % cycle, k = 0;
      while (ms >= delays[k]) ms -= delays[k++];
      return k;
    };
    (function step() {
      const s = synth(), tick = state.mode === 'off' ? null : audibleTick(s);
      show(tick == null ? -1 : frameAt(s, tick));
      requestAnimationFrame(step);
    })();
    return {
      frames: layers.length, delays,
      get mode() { return state.mode; },
      setMode(next) { state.mode = next; },
      get shown() { return state.shown; },
    };
  }

  root.BeatSync = { attach, decodeGif, audibleTick };
})(typeof window !== 'undefined' ? window : globalThis);
