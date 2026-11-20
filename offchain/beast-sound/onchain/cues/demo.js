// The cue demo page (built by build-demo.mjs into public/onchain/cue-demo.html). DATA is inlined by
// the build: each Beast's Species Song MIDI (genesisMidi, unchanged), its cues (cues.js), its card art
// and the Beast synth settings. Plays through the pinned TinySynth engine, as onchain-midi-player does.
/* global DATA, WebAudioTinySynth, BeatSync, CueSync */
(function () {
  const $ = (id) => document.getElementById(id);
  const COLORS = CueSync.VOICE_COLORS;
  const b64bytes = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
  let cur = 0, synth = null, playing = false, cs = null, beat = null, mode = 'music';
  const fired = []; // [{ cue, at (ms) }] for the strip's glow
  const S = (window.DEMO_STATE = { fired: [], get cs() { return cs; }, get beat() { return beat; }, get synth() { return synth; }, get playing() { return playing; }, get mode() { return mode; }, get beast() { return cur; } });

  // ── audio: the pinned engine with the Beast timbres (as mega.html and onchain-midi-player) ──
  function ensure() {
    if (synth) return synth;
    synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
    const st = DATA.settings;
    if (st && synth.setSampleWave) {
      synth.setQuality(st.quality); synth.setMasterVol(st.master_vol / 100); synth.setVoices(st.voices);
      st.waves.forEach((w, i) => synth.setSampleWave('nS' + i, w));
      for (const [drum, slot, ops] of st.timbres) synth.setTimbre(drum, slot, ops.map((o) => ({ ...o })));
      synth.setReverbLev(st.reverb / 100);
    }
    return synth;
  }
  function start() {
    const s = ensure(), b = DATA.beasts[cur], midi = b64bytes(b.midi);
    s.getAudioContext().resume();
    s.stopMIDI();
    s.loadMIDI(midi.buffer);
    s.loopEnd = Math.ceil(s.maxTick / s.song.timebase) * s.song.timebase; // the page player's loop (player-core loopEndTicks)
    s.setLoop(1);
    s.locateMIDI(0);
    s.playMIDI();
    playing = true;
    $('play').textContent = '■ Stop'; $('play').classList.add('on');
  }
  function stop() {
    if (synth) synth.stopMIDI();
    playing = false;
    $('play').textContent = '▶ Play'; $('play').classList.remove('on');
  }

  // ── a Beast on the stage: art, BeatSync on CueSync's clock ──
  const cuesOf = (b) => ({ ...b.cues, notes: b.notes });
  function show(i) {
    const was = playing;
    if (was) stop();
    if (beat) beat.detach();
    if (cs) cs.detach();
    cur = i;
    const b = DATA.beasts[i];
    document.querySelectorAll('.pick button').forEach((el, k) => el.classList.toggle('on', k === i));
    const holder = $('art');
    holder.innerHTML = '';
    const img = document.createElement('img');
    img.alt = b.name;
    img.src = 'data:image/svg+xml;charset=utf-8,' + encodeURIComponent(b.svg);
    holder.appendChild(img);
    cs = CueSync.attach({ stage: $('stage'), art: holder, cues: cuesOf(b), synth: () => synth, mode, onCue, reduceMotion: matchMedia('(prefers-reduced-motion: reduce)').matches });
    beat = BeatSync.attach({ img, svg: b.svg, synth: cs.frameSynth });
    $('name').textContent = b.name;
    $('facts').innerHTML = [b.key, b.bpm + ' BPM', b.cues.sections.length + ' sections', b.cues.length / b.cues.bar + ' bars', beat ? beat.frames + '-frame GIF' : 'static art (no GIF): only the cue layer moves', b.shiny ? 'shiny (mega)' : 'regular']
      .map((x) => '<span>' + x + '</span>').join('');
    $('meters').innerHTML = b.cues.voices.map((v) => `<div class="meter" data-ch="${v.ch}"><i style="--c:${v.ch === 9 ? '#9aa0a6' : COLORS[v.ch % COLORS.length]}"></i><span>${v.name}</span></div>`).join('');
    const m = b.marker;
    $('marker').innerHTML = `<b>Onchain cue track (optional, not in the MIDI the Beast plays):</b> one extra MTrk of FF 06 markers adds <b>${m.bytes} bytes</b> to this ${m.midi}-byte file (${m.count} markers, +${(100 * m.bytes / m.midi).toFixed(1)}%); with a marker on every bar line, ${m.bytesBars} bytes.<code>${m.preview}</code>`;
    $('log').innerHTML = '';
    fired.length = 0;
    drawStrip();
    if (was) start();
  }

  // ── cue labels and the log ──
  const ORD = ['', 'first', 'second', 'third', 'fourth', 'fifth', 'sixth'];
  function describe(c, b) {
    const vname = (ch) => (b.cues.voices.find((v) => v.ch === ch) || { name: 'ch ' + (ch + 1) }).name;
    if (c.type === 'section') return ['section', `Section ${c.index + 1}` + (c.degree ? ` · theme on ${c.degree}` : '') + (c.index ? ` (${b.cues.sections[c.index].label})` : '')];
    if (c.type === 'entry') return ['entry', c.role === 'countersubject' ? 'Countersubject enters' : `Theme enters · ${vname(c.voice)}`];
    if (c.type === 'episode') return ['episode', 'Episode: the head motif in sequence'];
    if (c.type === 'cadence') return ['cadence', c.final ? 'Final cadence: settle, hold, loop' : `Half cadence into section ${c.section + 2}`];
    if (c.type === 'climax') return ['climax', `Climax · bar ${c.bar} (${vname(c.voice)})`];
    return null;
  }
  function onCue(c) {
    const b = DATA.beasts[cur];
    S.fired.push({ type: c.type, tick: c.tick, mode: cs ? cs.mode : mode });
    if (S.fired.length > 400) S.fired.splice(0, 200);
    if (c.type === 'bar') { $('bar').textContent = `bar ${c.n} / ${b.cues.length / b.cues.bar}`; return; }
    fired.push({ cue: c, at: performance.now() });
    const d = describe(c, b);
    if (!d) return;
    const li = document.createElement('li');
    li.className = d[0];
    const col = c.type === 'entry' ? COLORS[c.voice % COLORS.length] : '';
    li.innerHTML = `<i style="${col ? '--c:' + col : ''}"></i><span>${d[1]}</span><em>bar ${Math.floor(c.tick / b.cues.bar) + 1}</em>`;
    const log = $('log');
    log.prepend(li);
    while (log.children.length > 7) log.lastChild.remove();
    if (c.type !== 'bar') $('now').textContent = d[1];
  }

  // ── the timeline strip ──
  const strip = $('strip');
  function drawStrip() {
    const b = DATA.beasts[cur], cues = b.cues, dpr = window.devicePixelRatio || 1;
    const W = strip.clientWidth, voices = cues.voices.filter((v) => v.ch !== 9), lane = 13, top = 26, H = top + voices.length * lane + 22;
    if (strip.width !== Math.round(W * dpr) || strip.height !== Math.round(H * dpr)) { strip.width = Math.round(W * dpr); strip.height = Math.round(H * dpr); strip.style.height = H + 'px'; }
    const x = strip.getContext('2d');
    x.setTransform(dpr, 0, 0, dpr, 0, 0);
    x.clearRect(0, 0, W, H);
    const X = (t) => (t / cues.length) * W, now = performance.now();
    const glow = (c) => { const f = fired.find((e) => e.cue === c); return f ? Math.max(0, 1 - (now - f.at) / 700) : 0; };
    // sections, coloured by key area as the stage is
    for (const s of cues.sections) {
      x.fillStyle = `hsl(${(s.index * 97 + 210) % 360} 55% 32%)`;
      x.fillRect(X(s.start), 0, X(s.end) - X(s.start) - 1, 18);
      x.fillStyle = '#fff'; x.font = '600 11px system-ui,sans-serif';
      x.fillText(`${s.index + 1}${s.degree ? ' ' + s.degree : ''}${s.index ? ' · ' + s.label : ''}`, X(s.start) + 4, 13);
    }
    // bar lines
    x.fillStyle = 'rgba(255,255,255,.08)';
    for (let t = 0; t < cues.length; t += cues.bar) x.fillRect(X(t), top - 4, 1, H - top);
    // notes per voice, alpha by velocity
    voices.forEach((v, i) => {
      const y = top + i * lane;
      x.fillStyle = 'rgba(255,255,255,.04)'; x.fillRect(0, y, W, lane - 2);
      x.fillStyle = COLORS[v.ch % COLORS.length];
      for (const n of b.notes) if (n[1] === v.ch) { x.globalAlpha = 0.15 + 0.6 * (n[2] / 127) ** 2; x.fillRect(X(n[0]), y + 2, Math.max(1, X(n[4]) - 0.5), lane - 6); }
      x.globalAlpha = 1;
    });
    // cadences: a bracket under the section band
    for (const c of cues.cues.filter((q) => q.type === 'cadence')) {
      const end = c.final ? cues.length : (cues.sections.find((s) => c.tick >= s.start && c.tick < s.end) || { end: cues.length }).end, g = glow(c);
      x.fillStyle = c.final ? `rgba(140,200,255,${0.35 + 0.5 * g})` : `rgba(140,200,255,${0.18 + 0.5 * g})`;
      x.fillRect(X(c.tick), 19, X(end) - X(c.tick) - 1, 4);
      x.fillRect(X(c.tick), top - 4, X(end) - X(c.tick) - 1, H - top - 18);
    }
    // entries: a marker at the start of the voice's lane
    for (const c of cues.cues.filter((q) => q.type === 'entry')) {
      const i = voices.findIndex((v) => v.ch === c.voice);
      if (i < 0) continue;
      const y = top + i * lane + (lane - 2) / 2, px = X(c.tick), g = glow(c), r = 4 + 5 * g;
      x.fillStyle = '#fff'; x.strokeStyle = COLORS[c.voice % COLORS.length]; x.lineWidth = 2;
      x.beginPath();
      if (c.role === 'countersubject') { x.moveTo(px, y - r); x.lineTo(px + r, y); x.lineTo(px, y + r); x.lineTo(px - r, y); } else { x.moveTo(px, y - r); x.lineTo(px + r * 1.4, y); x.lineTo(px, y + r); }
      x.closePath(); x.fill(); x.stroke();
    }
    // climax: a star
    for (const c of cues.cues.filter((q) => q.type === 'climax')) {
      const px = X(c.tick), py = H - 10, g = glow(c), r = 6 + 6 * g;
      x.fillStyle = `rgba(255,214,90,${0.8 + 0.2 * g})`; x.beginPath();
      for (let k = 0; k < 10; k++) { const a = -Math.PI / 2 + (k * Math.PI) / 5, rr = k % 2 ? r * 0.45 : r; x.lineTo(px + rr * Math.cos(a), py + rr * Math.sin(a)); }
      x.closePath(); x.fill();
      if (W > 560) { x.fillStyle = 'rgba(255,214,90,.9)'; x.font = '600 10px system-ui,sans-serif'; x.fillText('climax', px + 10, py + 4); }
    }
    // final cadence label
    const fin = cues.cues.find((q) => q.type === 'cadence' && q.final);
    if (fin) { x.fillStyle = 'rgba(140,200,255,.95)'; x.font = '600 10px system-ui,sans-serif'; x.fillText(W > 560 ? 'final cadence' : 'final', Math.min(W - (W > 560 ? 70 : 26), X(fin.tick) + 3), H - 6); }
    // playhead
    const t = cs && cs.tick;
    if (t != null) { x.fillStyle = '#fff'; x.fillRect(X(t) - 1, 0, 2, H); }
  }

  // ── per-frame UI: meters and strip ──
  (function loop() {
    if (cs) {
      const e = cs.energy;
      document.querySelectorAll('.meter').forEach((m) => { m.style.setProperty('--e', (e[m.dataset.ch] || 0).toFixed(3)); });
      drawStrip();
    }
    requestAnimationFrame(loop);
  })();

  // ── controls ──
  $('pick').innerHTML = DATA.beasts.map((b, i) => `<button type="button" aria-label="${b.name}"><img alt="" src="data:image/svg+xml;charset=utf-8,${encodeURIComponent(b.svg)}"><span>${b.short}</span><small>${b.badge}</small></button>`).join('');
  document.querySelectorAll('.pick button').forEach((el, i) => { el.onclick = () => show(i); });
  $('play').onclick = () => (playing ? stop() : start());
  const setMode = (m) => {
    mode = m;
    if (cs) cs.setMode(m);
    $('m-tempo').classList.toggle('on', m === 'tempo'); $('m-music').classList.toggle('on', m === 'music');
    $('m-tempo').setAttribute('aria-pressed', m === 'tempo'); $('m-music').setAttribute('aria-pressed', m === 'music');
    $('mode-note').textContent = m === 'tempo' ? 'Today: the GIF steps one frame per eighth note. Nothing else follows the music.' : 'The structure drives the art: entries pulse, the climax hits, cadences settle, each voice’s velocity glows below.';
  };
  $('m-tempo').onclick = () => setMode('tempo');
  $('m-music').onclick = () => setMode('music');
  document.addEventListener('keydown', (ev) => {
    if (ev.metaKey || ev.ctrlKey || ev.target.tagName === 'BUTTON' && ev.key === ' ') return;
    if (ev.key === ' ') { ev.preventDefault(); playing ? stop() : start(); }
    else if (ev.key === 'm') setMode(mode === 'music' ? 'tempo' : 'music');
    else if (ev.key >= '1' && ev.key <= String(DATA.beasts.length)) show(+ev.key - 1);
  });
  addEventListener('resize', drawStrip);
  setMode('music');
  show(0);
})();
