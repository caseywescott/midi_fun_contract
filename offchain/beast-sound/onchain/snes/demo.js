// Shared by the live lab and offline audio verification. No demo data enters the onchain page.
export function demoSequence(bank) {
  const instruments = bank.instruments.filter((i, n, all) => all.findIndex((x) => x.sample === i.sample) === n && i.program !== undefined);
  const notes = [], sections = [];
  const registers = { harp: 60, marimba: 60, glockenspiel: 72, strings: 60, cello: 48, flute: 72 };
  for (const [index, inst] of instruments.entries()) {
    const at = index * 3.2, base = registers[inst.id] ?? inst.rootNote;
    sections.push({ time: at, label: inst.id });
    [0, 4, 7, 12].forEach((n, i) => notes.push({ id: inst.id, program: inst.program, channel: index, note: base + n, velocity: 108, time: at + i * 0.52, duration: i === 3 ? 0.85 : 0.42, pan: 0 }));
  }
  const byId = new Map(instruments.map((i) => [i.id, i]));
  const ensemble = instruments.length * 3.2 + 0.2;
  if (['harp', 'marimba', 'glockenspiel', 'strings', 'cello', 'flute'].every((id) => byId.has(id))) {
    sections.push({ time: ensemble, label: 'Pocket orchestra' });
    const add = (id, channel, note, time, duration, velocity, pan) => notes.push({ id, program: byId.get(id).program, channel, note, time: ensemble + time, duration, velocity, pan });
    const chords = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]];
    chords.forEach((chord, bar) => {
      const start = bar * 2;
      add('cello', 4, chord[0] - 12, start, 1.65, 92, -0.18);
      add('strings', 3, chord[1], start + 0.05, 1.55, 82, 0.35);
      for (let beat = 0; beat < 4; beat++) add(beat % 2 ? 'marimba' : 'harp', beat % 2 ? 1 : 0, chord[beat % 3], start + beat * 0.5, 0.38, 100, -0.35);
      add('flute', 5, chord[2] + 12, start + 0.5, 0.6, 92, 0.1);
      add('glockenspiel', 2, chord[1] + 24, start + 1.5, 0.4, 85, 0.25);
    });
  }
  notes.sort((a, b) => a.time - b.time || a.channel - b.channel);
  const duration = Math.max(0, ...notes.map((n) => n.time + n.duration)) + 1.8;
  return { notes, sections, duration };
}

export function scheduleDemo(sampler, ac, bank, destination = ac.destination, time = ac.currentTime + 0.05) {
  const sequence = demoSequence(bank), buses = new Map();
  for (const n of sequence.notes) {
    if (!buses.has(n.channel)) { const p = ac.createStereoPanner(); p.pan.value = n.pan; p.connect(destination); buses.set(n.channel, p); }
    buses.get(n.channel).pan.setValueAtTime(n.pan, time + n.time);
    sampler.noteOn({ ...n, time: time + n.time, destination: buses.get(n.channel) });
    sampler.noteOff(n.channel, n.note, time + n.time + n.duration);
  }
  return { ...sequence, start: time, dispose() { sampler.stop(); for (const p of buses.values()) p.disconnect(); } };
}
