// A local preview of official Beasts V3 card output, driven by the lab's own MIDI and synth.
import { mount, cutout, midiNotes } from './vendor/onchain-midi-notes/notes.js';

const NS = 'http://www.w3.org/2000/svg';
// Beasts V3 beast_svg.cairo::get_tier_color; the tier comes from the captured card itself.
const TIER_COLORS = ['#ffffff', '#ff8800', '#8c00bf', '#0000ff', '#00ff00', '#ffffff'];
const clocks = new WeakMap();

// startTime is tick zero of the currently scheduled pass. Reading the audio clock, rather than
// accumulating animation frames, also recovers after a hidden tab. The bundled engine exposes it.
export function playbackSeconds(synth) {
  if (!synth) return 0;
  const ctx = synth.getAudioContext(), start = synth.getPlayStatus().startTime;
  if (!Number.isFinite(start)) return 0;
  const audible = ctx.currentTime - (ctx.outputLatency || 0);
  let state = clocks.get(synth);
  if (!state || state.song !== synth.song) {
    state = { song: synth.song, origin: start };
    clocks.set(synth, state);
  }
  // The sequencer schedules the next pass ahead of what the listener hears.
  if (start <= audible) state.origin = start;
  return Math.max(0, audible - state.origin);
}

export function createCardPreview(img, assets, clock) {
  let notes = null, key = '', url = '', playing = false;
  const redraw = () => notes?.draw();
  const resize = new ResizeObserver(redraw);
  resize.observe(img);
  img.addEventListener('load', redraw);
  window.addEventListener('scroll', redraw, true);
  const makeSvg = ({ id, shiny, name, frameBeats }, midi) => {
    const svg = assets.cards[id].replace(/\0([a-f0-9]{64})\0/g, (_, h) => assets.fragments[h]);
    const root = new DOMParser().parseFromString(svg, 'image/svg+xml').documentElement;
    const sp = assets.sprites[id + (shiny ? 's' : '')];
    const tempo = midiTempo(midi), beat = tempo / 1e6;
    const step = frameBeats ?? (beat < 0.4 ? 1 : 0.5);
    root.querySelector('title').textContent = name;
    const title = [...root.children].find((e) => e.localName === 'text');
    title.textContent = name;
    title.style.fontSize = Math.min(34, 210 / (name.length * 0.55)) + 'px';
    [...root.children].find((e) => e.localName === 'rect').setAttribute('fill', shiny ? 'url(#shinyRim)' : 'url(#gold)');
    const tier = Number([...root.querySelectorAll('text')].find((e) => e.textContent === 'TIER').nextElementSibling.textContent);
    root.querySelector('#logoPulse path').setAttribute('fill', shiny ? 'url(#logo_pastel_rainbow)' : (TIER_COLORS[tier] || TIER_COLORS[0]));
    // Keep the current renderer's frame and clipping, replacing only its GIF with the same
    // canonical GIF decoded to a sprite sheet so the existing tempo-sync controls still work.
    const fo = root.querySelector('foreignObject');
    const sprite = document.createElementNS(NS, 'svg');
    for (const attr of ['x', 'y', 'width', 'height']) sprite.setAttribute(attr, fo.getAttribute(attr));
    sprite.setAttribute('viewBox', `0 0 ${sp.w} ${sp.w}`);
    const sheet = document.createElementNS(NS, 'image');
    sheet.setAttribute('width', sp.n * sp.w); sheet.setAttribute('height', sp.w);
    sheet.setAttribute('href', 'data:image/png;base64,' + sp.png);
    sheet.style.imageRendering = 'pixelated';
    const animation = document.createElementNS(NS, 'animate');
    for (const [a, v] of Object.entries({ attributeName: 'x', values: Array.from({ length: sp.n }, (_, k) => -k * sp.w).join(';'), dur: sp.n * step * beat + 's', calcMode: 'discrete', repeatCount: 'indefinite' })) animation.setAttribute(a, v);
    sheet.append(animation); sprite.append(sheet); fo.replaceWith(sprite);
    const loops = { '2.2s': 4, '6s': 16, '3s': 8 };
    for (const a of root.querySelectorAll('animate, animateTransform')) {
      const beats = loops[a.getAttribute('dur')];
      if (beats) a.setAttribute('dur', beats * beat + 's');
      if (playing) a.setAttribute('begin', -clock() + 's');
    }
    if (matchMedia('(prefers-reduced-motion: reduce)').matches) {
      for (const a of root.querySelectorAll('animate, animateTransform')) a.remove();
    }
    const bg = root.querySelector('[data-notes-bg]');
    const box = ['x', 'y', 'width', 'height'].map((a) => +bg.getAttribute(a));
    const view = root.getAttribute('viewBox').split(/\s+/).map(Number);
    return { svg: cutout(new XMLSerializer().serializeToString(root)), box, view };
  };
  return {
    show(selection, midi) {
      notes?.remove();
      const nextKey = [selection.id, selection.shiny, selection.name, selection.frameBeats, midiTempo(midi)].join('|');
      const { svg, view, box } = makeSvg(selection, midi);
      if (key !== nextKey) {
        key = nextKey;
        const next = URL.createObjectURL(new Blob([svg], { type: 'image/svg+xml' }));
        img.src = next;
        if (url) URL.revokeObjectURL(url);
        url = next;
      }
      img.alt = selection.name + ' — Beasts V3 card with the selected track’s MIDI';
      const canvas = document.createElement('canvas');
      canvas.className = 'beast-midi-notes'; canvas.setAttribute('aria-hidden', 'true');
      canvas.style.pointerEvents = 'none';
      notes = mount(canvas, { midi, clock, img, view, box });
      if (playing) notes.play();
    },
    play() { playing = true; key = ''; notes?.play(); },
    stop() { playing = false; notes?.stop(); },
    redraw,
  };
}

function midiTempo(midi) { return midiNotes(midi).beat * 1e6; }
