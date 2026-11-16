// Build public/loot-lab.html: every track a Loot Dungeon Beast plays, to audition before launch.
// Species Song and Name Song are the Beasts v1.0.1 composer's; Sound Checks are src/loot_checks.js. The first two come from its JS reference (lab.js);
// Monthly Track Editions are src/loot_editions.js (Realm of Common Tones and Kingdom of Sweets
// harmony). Rounds are src/loot_rounds.js (canons over a chord loop). Drift is Casey Drift on Species
// Songs, Name Songs (by the name, as in Beasts v1.0.1), Rounds and editions. Sound effects: 0 regular, 1 mega.
// Instruments: the sample bank (16 kHz BRR, ten CC0 VSCO 2 instruments; midi_fun_contract branch
// feat/snes-brr-pipeline, onchain/snes/dist-16k/bank.min.js) by default, each channel's role mapped to a
// bank instrument; drums stay on TinySynth's chip kit. TinyChip presets remain a toggle.
//   node onchain/loot-lab.mjs <engine .min.js> <onchain-midi-player checkout> <midi_fun_contract checkout at v1.0.1> <bank.min.js>
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { join } from 'node:path';
import { build } from 'esbuild';
import { LOOT_BEASTS } from '../src/loot_beasts.js';
import { SPECIES } from '../src/loot_species.js';
import { STYLES } from '../src/loot_styles.js';

const here = fileURLToPath(new URL('.', import.meta.url));
// optional: the output name, then label/bank pairs to compare (local evaluation); the Instruments button
// cycles the sample bank, each extra bank, then TinyChip
const [engineFile, omp, ref, bankFile, outName = 'loot-lab.html', ...pairs] = process.argv.slice(2);
const extras = []; for (let i = 0; i + 1 < pairs.length; i += 2) extras.push([pairs[i], pairs[i + 1]]);
if (!engineFile || !omp || !ref || !bankFile) { console.error('usage: node onchain/loot-lab.mjs <engine .min.js> <onchain-midi-player checkout> <midi_fun_contract checkout> <bank.min.js>'); process.exit(2); }
const BSRC = join(ref, 'offchain/beast-sound');
const inline = (js) => js.replace(/<\/script/gi, '<\\/script');
const tiny = readFileSync(engineFile, 'utf8');
// the sample bank, its globals named for what they are
const clean = (f) => { const js = readFileSync(f, 'utf8').replace(/SnesBank/g, 'SampleBank').replace(/__snesSampler/g, '__sampleLayer').replace(/SNES sampler/g, 'Sampler').replace(/snes-brr-1/g, 'brr-1'); if (/snes/i.test(js)) throw new Error('bank script still names SNES'); return js; };
const bankJs = [clean(bankFile) + '\nwindow.Banks=[SampleBank];', ...extras.map(([, f]) => clean(f) + '\nwindow.Banks.push(SampleBank);')].join('\n');
// the page's sentences about its instruments: the sample bank's by default, or what the build says (LAB_INSTRUMENTS, LAB_CREDIT)
const INSTRUMENTS_NOTE = process.env.LAB_INSTRUMENTS || 'Instruments: a ten-instrument sample bank (harp, marimba, glockenspiel, strings, cello, flute, pizzicato, clarinet, timpani, piano) at 16 kHz, with the TinyChip presets one click away.';
const CREDIT_NOTE = process.env.LAB_CREDIT ?? 'Samples: VSCO 2 Community Edition by Versilian Studios (CC0).';
const INSTS = [process.env.LAB_BANK_LABEL || 'sample bank', ...extras.map(([label]) => label), 'TinyChip'];
const bundle = (await build({
  stdin: {
    contents: `import { engine } from ${JSON.stringify(BSRC + '/src/index.js')}; import { createEngineV11 } from ${JSON.stringify(BSRC + '/src/engine_v11.js')};
      import * as lab from ${JSON.stringify(BSRC + '/src/lab.js')};
      import * as ed from './src/loot_editions.js';
      import * as rd from './src/loot_rounds.js';
      import * as ck from './src/loot_checks.js';
      import { installSettings } from ${JSON.stringify(omp + '/player/settings.js')};
      window.BS = { engine, v11: createEngineV11(engine), lab, ed, rd, ck, installSettings };`,
    resolveDir: here + '..', loader: 'js',
  },
  nodePaths: [join(BSRC, 'node_modules')], bundle: true, minify: true, format: 'iife', platform: 'browser', write: false, logLevel: 'error',
})).outputFiles[0].text;

// the settings: a family's presets (mega adds the mega leads) for songs and Sound Checks; for an
// edition, the presets of the Beasts style it borrows its figures and palette from
const ST = await import(pathToFileURL(join(BSRC, 'onchain/tinychip/synth_settings.mjs')).href);
const { STYLES: BEAST_STYLES } = await import(pathToFileURL(join(BSRC, 'src/editions_lite.js')).href);
const FAMILY = ST.SETTINGS_VARIANTS.map((v) => ST.beastSynthSettings(undefined, ST.variantPrograms(v)));
const EDITION = STYLES.map((S) => { const src = BEAST_STYLES.findIndex((x) => x.key === S.source); return [0, 1, 2].map((t) => [false, true].map((m) => ST.editionSynthSettings(src, t, m))); });
const { loadBank } = await import(pathToFileURL(join(BSRC, 'onchain/tinychip/essentials.mjs')).href);
const bank = loadBank();
const NAMES = Object.fromEntries(bank.PRESETS.map((p, i) => [p.program ?? i, p.name]));
const BEASTS = LOOT_BEASTS.map((b) => ({ ...b, ...SPECIES.find((s) => s.id === b.id) }));
// the bank's instruments (MIDI programs) and the orchestration: an edition style's roles (lead,
// accompaniment, bass, pad; the descant plays the lead, the mega double a glockenspiel or flute), a
// song channel's instrument by family (channel 0 the theme, 4 the countersubject)
const BANK = { piano: 0, glockenspiel: 9, marimba: 12, cello: 42, pizzicato: 45, harp: 46, timpani: 47, strings: 48, clarinet: 71, flute: 73, organ: 19, pad: 89, violin: 40, guitar: 25, upright: 32, vibraphone: 11, latelybass: 38, ocarina: 79, drawbar: 16, horn: 60,
  oboe: 68, bassoon: 70, trumpet: 56, trombone: 57, bowedcello: 43, choir: 52, kalimba: 108, koto: 107 };
// options only some banks have: a bank without one plays the instrument it stands in for
const FALLBACK = { [BANK.organ]: BANK.strings, [BANK.pad]: BANK.strings, [BANK.violin]: BANK.strings, [BANK.guitar]: BANK.pizzicato, [BANK.upright]: BANK.cello, [BANK.vibraphone]: BANK.harp, [BANK.latelybass]: BANK.cello,
  [BANK.ocarina]: BANK.flute, [BANK.drawbar]: BANK.strings, [BANK.horn]: BANK.strings,
  [BANK.oboe]: BANK.clarinet, [BANK.bassoon]: BANK.cello, [BANK.trumpet]: BANK.clarinet, [BANK.trombone]: BANK.cello, [BANK.bowedcello]: BANK.cello, [BANK.choir]: BANK.strings, [BANK.kalimba]: BANK.harp, [BANK.koto]: BANK.harp };
// Each style's band is chosen for the track from these pools (lead, accompaniment, bass, pad), by Beast,
// edition and purchase, so the same style comes round with different instruments; the first of each pool
// is the style's original choice. The lead and the pad are never the same instrument. A bank without an
// optional instrument plays the one it stands in for (FALLBACK). A string lead is the violin (a quieter, softer
// take on the strings, which keep the pads); a bank without it plays its strings.
// The Kankyo bank's newer voices (oboe, bassoon, trumpet, trombones, bowed cello, choir, kalimba, koto) are added
// where they suit a style, after its original choices: a trumpet leads the marches and the fast styles, an oboe the
// pastoral and Eastern ones, the choir pads the slow and solemn ones, the kalimba and koto pluck the accompaniments;
// the bassoon plays only where a song's or round's cello melody may be swapped (ALIKE).
// Bass lines are played by the basses and cellos only, never the bassoon or the trombones (Casey).
const POOLS = {
  overworld: [['flute', 'ocarina', 'clarinet', 'trumpet'], ['guitar', 'pizzicato', 'marimba', 'kalimba'], ['cello', 'latelybass', 'upright'], ['horn', 'strings', 'drawbar', 'trombone']],
  field: [['ocarina', 'flute', 'clarinet', 'oboe'], ['harp', 'guitar', 'vibraphone', 'kalimba'], ['cello', 'upright', 'latelybass', 'bowedcello'], ['strings', 'pad', 'horn', 'choir']],
  lullaby: [['flute', 'ocarina', 'clarinet', 'oboe'], ['vibraphone', 'harp', 'piano', 'kalimba'], ['cello', 'upright', 'bowedcello'], ['pad', 'strings', 'horn', 'choir']],
  forest: [['clarinet', 'flute', 'ocarina', 'oboe'], ['marimba', 'guitar', 'harp', 'kalimba', 'koto'], ['pizzicato', 'upright', 'cello', 'latelybass'], ['drawbar', 'strings', 'horn', 'choir']],
  temple: [['clarinet', 'ocarina', 'horn', 'oboe'], ['harp', 'vibraphone', 'piano', 'koto'], ['cello', 'upright', 'latelybass'], ['organ', 'pad', 'strings', 'choir']],
  boss: [['violin', 'horn', 'clarinet', 'trumpet', 'bowedcello'], ['marimba', 'guitar', 'piano'], ['latelybass', 'cello'], ['organ', 'drawbar', 'strings', 'choir']],
  flowers: [['flute', 'violin', 'ocarina', 'oboe'], ['harp', 'vibraphone', 'piano', 'kalimba'], ['cello', 'upright', 'bowedcello'], ['horn', 'strings', 'pad', 'choir']],
  toymarch: [['glockenspiel', 'ocarina', 'flute', 'trumpet', 'kalimba'], ['pizzicato', 'guitar', 'marimba'], ['cello', 'upright', 'latelybass'], ['clarinet', 'horn', 'drawbar', 'trombone']],
  adagio: [['flute', 'violin', 'horn', 'clarinet', 'oboe', 'bowedcello'], ['piano', 'vibraphone', 'harp'], ['cello', 'upright', 'bowedcello'], ['pad', 'strings', 'organ', 'choir']],
  sugarplum: [['glockenspiel', 'vibraphone', 'flute', 'kalimba'], ['pizzicato', 'harp', 'guitar', 'kalimba'], ['clarinet', 'upright', 'cello'], ['strings', 'pad', 'drawbar', 'choir']],
  trepak: [['violin', 'clarinet', 'flute', 'trumpet'], ['guitar', 'pizzicato', 'marimba'], ['latelybass', 'upright', 'cello'], ['clarinet', 'horn', 'drawbar', 'trombone']],
  arabian: [['flute', 'clarinet', 'ocarina', 'oboe'], ['harp', 'guitar', 'piano', 'koto'], ['cello', 'upright', 'latelybass', 'bowedcello'], ['pad', 'strings', 'organ', 'choir']],
  speedrun: [['flute', 'violin', 'clarinet', 'trumpet'], ['marimba', 'guitar', 'piano', 'pizzicato', 'kalimba'], ['latelybass', 'upright', 'cello'], ['organ', 'strings', 'drawbar', 'trombone']],
  dash: [['flute', 'violin', 'ocarina', 'trumpet'], ['marimba', 'piano', 'guitar', 'pizzicato', 'koto'], ['latelybass', 'cello', 'upright'], ['strings', 'organ', 'horn', 'trombone']],
  punkrun: [['clarinet', 'violin', 'flute', 'trumpet'], ['guitar', 'piano', 'marimba'], ['cello', 'latelybass', 'upright'], ['drawbar', 'organ', 'strings', 'trombone']],
};
// a style's mix by instrument, as factors on the channel's volume (CC 7, whose level goes by its square): Punk
// Run's piano accompaniment is quieter and its violin louder (Casey, by ear)
const MIX = { punkrun: { piano: 0.75, violin: 1.27 } };
// an instrument that is turned down when it is a track's highest voice (by average pitch), in any kind of track:
// the vibraphone on top rings over everything (Casey, by ear)
const TOP_SOFT = { vibraphone: 0.72 };
// an instrument that is turned down when it plays the lead (an edition's lead and its second lead; a song's theme),
// as a CC 7 factor (the square root of the level's): the clarinet 20% and then 15% more (0.8 x 0.85 = 0.68), the
// trumpet 15% and then 20% three times (0.85 x 0.8^3 = 0.435), the oboe 30% and then 20% three times (0.358), the
// vibraphone 30%, the horn 20% twice (0.64) (Casey, by ear; on the vibraphone this comes on top of TOP_SOFT when it
// is also the top voice)
const LEAD_SOFT = { clarinet: 0.825, trumpet: 0.66, oboe: 0.599, vibraphone: 0.837, horn: 0.8 };
// and every lead, whatever plays it, down against the other instruments: 20%, then 25% more (0.8 x 0.75 = 0.6) on
// top (Casey, by ear; CC 7 factor, the square root of 0.6)
const LEAD_ALL = 0.775;
// then 7 steps of CC 7 off every lead after those factors (Casey: subtract another 15 off each lead volume, then
// add 5 back, then 3 more)
const LEAD_DROP = 7;
// an instrument turned down on every channel of a Name Song: the oboe 35%, then 40% and 20% more (0.65 x 0.6 x 0.8 =
// 0.312) (Casey, by ear; CC 7 factor, as above)
const NAME_SOFT = { oboe: 0.559 };
// a Name Song's lead (its theme, channel 1) comes from this pool, by species and name, so a species' names do not all
// share one lead (Casey: good variation of leads); the oboe is left out (turned down on Name Songs)
const NAME_LEADS = ['flute', 'ocarina', 'clarinet', 'violin', 'horn', 'trumpet'];
// songs and rounds: each channel's instrument may be exchanged for another of its kind, by species
const ALIKE = {
  // (a newer voice sits in one list of each kind only, so two channels of a song or round do not both draw it)
  melody: { flute: ['flute', 'ocarina'], clarinet: ['clarinet', 'horn', 'oboe'], strings: ['violin', 'horn', 'flute', 'trumpet'], glockenspiel: ['glockenspiel', 'vibraphone'], cello: ['cello', 'horn', 'bowedcello', 'bassoon'] },
  accomp: { harp: ['harp', 'vibraphone', 'guitar', 'kalimba', 'koto'], marimba: ['marimba', 'vibraphone', 'guitar'], piano: ['piano', 'vibraphone', 'harp'], pizzicato: ['pizzicato', 'guitar', 'harp'] },
  bass: { cello: ['cello', 'latelybass', 'upright', 'bowedcello'] }, pad: { strings: ['strings', 'pad', 'horn', 'drawbar', 'organ', 'choir'] }, keep: {},
};
const prog = (n) => { if (BANK[n] === undefined) throw new Error('no bank instrument ' + n); return BANK[n]; };
const pooled = (rows, kinds) => rows.map((r) => r.map((n, ch) => (ALIKE[kinds[ch]][n] ?? [n]).map(prog)));
const SONG = [
  ['flute', 'clarinet', 'harp', 'cello', 'glockenspiel', 'strings', 'harp', 'strings'],
  ['flute', 'strings', 'marimba', 'cello', 'clarinet', 'strings', 'marimba', 'strings'],
  ['strings', 'cello', 'piano', 'cello', 'clarinet', 'strings', 'piano', 'strings'],
];
const ROUND = [
  ['flute', 'clarinet', 'harp', 'pizzicato', 'cello', 'glockenspiel', 'harp'],
  ['clarinet', 'strings', 'marimba', 'harp', 'cello', 'flute', 'harp'],
  ['strings', 'clarinet', 'piano', 'marimba', 'cello', 'glockenspiel', 'harp'],
];
const SONG_KINDS = ['melody', 'melody', 'accomp', 'bass', 'melody', 'pad', 'accomp', 'pad'], ROUND_KINDS = ['melody', 'melody', 'accomp', 'accomp', 'bass', 'melody', 'keep'];
const ORCH = {
  pools: Object.fromEntries(STYLES.map((S) => [S.key, (POOLS[S.key] ?? []).map((pool) => pool.map(prog))])),
  mix: Object.fromEntries(Object.entries(MIX).map(([k, m]) => [k, Object.fromEntries(Object.entries(m).map(([n, f]) => [prog(n), f]))])),
  topSoft: Object.fromEntries(Object.entries(TOP_SOFT).map(([n, f]) => [prog(n), f])),
  leadSoft: Object.fromEntries(Object.entries(LEAD_SOFT).map(([n, f]) => [prog(n), f])),
  nameSoft: Object.fromEntries(Object.entries(NAME_SOFT).map(([n, f]) => [prog(n), f])), nameLeads: NAME_LEADS.map(prog), leadAll: LEAD_ALL, leadDrop: LEAD_DROP,
  bells: [BANK.glockenspiel, BANK.vibraphone], low: BANK.pizzicato, glock: BANK.glockenspiel, flute: BANK.flute, harp: BANK.harp,
  songKinds: SONG_KINDS, roundKinds: ROUND_KINDS, songPools: pooled(SONG, SONG_KINDS), roundPools: pooled(ROUND, ROUND_KINDS),
  song: SONG.map((r) => r.map(prog)),
  // a Round's channels by family: the four canon voices, the bass, the mega double, the harp glissando
  round: [
    ['flute', 'clarinet', 'harp', 'pizzicato', 'cello', 'glockenspiel', 'harp'],
    ['clarinet', 'strings', 'marimba', 'harp', 'cello', 'flute', 'harp'],
    ['strings', 'clarinet', 'piano', 'marimba', 'cello', 'glockenspiel', 'harp'],
  ].map((r) => r.map((n) => BANK[n])),
  names: Object.fromEntries(Object.entries(BANK).map(([k, v]) => [v, k])), fallback: FALLBACK,
};
if (Object.keys(POOLS).length !== STYLES.length || STYLES.some((S) => (POOLS[S.key] ?? []).length !== 4)) throw new Error('every style needs its four pools');
const DATA = { insts: INSTS, orch: ORCH, beasts: BEASTS, types: ['Magic', 'Hunter', 'Brute'], names: NAMES, family: FAMILY, edition: EDITION, styles: STYLES.map((s) => ({ key: s.key, label: s.label, desc: s.desc, home: s.home, ...(s.family ? { family: s.family } : {}) })) };

const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>Loot Dungeon Sound Lab</title>
<link rel="icon" href="data:,">
<meta name="description" content="Every track a Loot Dungeon Beast plays: Species Song, Round, Name Song, Sound Check and Monthly Track Editions in Realm and Sweets harmony, with Casey Drift.">
<style>
:root{--bg:#f4f1ea;--fg:#1c1a17;--mut:#6b655c;--card:#fff;--line:#e0dace;--acc:#8a2be2;--gold:#b8860b}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){--bg:#121016;--fg:#ece6f2;--mut:#9a92a8;--card:#1d1a24;--line:#2d2938;--acc:#b37bff;--gold:#e0b34a}}
:root[data-theme="dark"]{--bg:#121016;--fg:#ece6f2;--mut:#9a92a8;--card:#1d1a24;--line:#2d2938;--acc:#b37bff;--gold:#e0b34a}
*{box-sizing:border-box}body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,sans-serif}
main{max-width:1100px;margin:0 auto;padding:24px 16px 48px}h1{font-size:23px;margin:0 0 4px}p.sub{color:var(--mut);margin:0 0 16px;max-width:820px}
.tabs{display:grid;grid-template-columns:repeat(5,1fr);gap:8px;margin-bottom:14px}.tabs button{padding:10px 12px;border-radius:12px;border:2px solid var(--line);background:var(--card);color:var(--fg);text-align:left;cursor:pointer;font:inherit}
.tabs button b{display:block}.tabs button span{display:block;color:var(--mut);font-size:12.5px}.tabs button.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 12%,var(--card))}
@media(max-width:760px){.tabs{grid-template-columns:1fr 1fr}}
.card{background:var(--card);border:1px solid var(--line);border-radius:12px;padding:16px;margin-bottom:14px;min-width:0}
.row{display:grid;grid-template-columns:auto 1fr auto;gap:10px;align-items:center;margin-bottom:10px}.row .mid{text-align:center;min-width:0}.lbl{font-size:12px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em}
.val{font-weight:650;font-size:16px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap}.val small{font-weight:400;color:var(--mut);font-size:13px}.row.off{display:none}
button,input{font:inherit}button.nav{width:42px;height:42px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-size:17px;cursor:pointer}
.ctl{display:flex;gap:10px;flex-wrap:wrap}.ctl button{flex:1;min-width:110px;padding:10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);font-weight:600;cursor:pointer}.ctl button.go{background:var(--fg);color:var(--bg)}.ctl button.on{border-color:var(--gold);color:var(--gold)}
.banks{display:grid;grid-template-columns:repeat(auto-fill,minmax(210px,1fr));gap:8px;margin-top:12px}.banks label{display:flex;gap:12px;align-items:center;padding:14px 16px;border:2px solid var(--line);border-radius:12px;cursor:pointer;background:var(--bg)}.banks label.on{border-color:var(--acc);background:color-mix(in srgb,var(--acc) 14%,var(--card))}.banks input{width:24px;height:24px;flex:none;margin:0;accent-color:var(--acc)}.banks b{display:block;font-size:16px}.banks span span{display:block;font-size:12.5px;color:var(--mut)}
.age{display:block;font-size:13px;margin-top:10px}.age input{width:100%;margin-top:6px;accent-color:var(--acc)}.age.off{display:none}
#roll{width:100%;height:220px;display:block;border-radius:8px;background:color-mix(in srgb,var(--fg) 4%,var(--card))}
.legend{display:flex;flex-wrap:wrap;gap:4px 14px;margin-top:8px;font-size:12px;color:var(--mut)}.legend i{width:10px;height:10px;border-radius:3px;display:inline-block;margin-right:5px;vertical-align:-1px}
dl{display:grid;grid-template-columns:max-content minmax(0,1fr);gap:4px 12px;margin:0;font-size:13px}dt{color:var(--mut)}dd{margin:0;font-family:ui-monospace,monospace;font-size:12.5px;overflow-wrap:anywhere}
.note{font-size:12.5px;color:var(--mut);margin:8px 0 0}.kbd{font:11px ui-monospace,monospace;border:1px solid var(--line);border-radius:4px;padding:0 4px}
.styles{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:8px}.styles button{text-align:left;padding:8px 10px;border-radius:10px;border:1px solid var(--line);background:var(--bg);color:var(--fg);cursor:pointer;font:inherit}.styles button b{display:block;font-size:14px}.styles button span{font-size:12px;color:var(--mut)}.styles button.on{border-color:var(--acc)}
h2{font-size:13px;color:var(--mut);text-transform:uppercase;letter-spacing:.06em;margin:0 0 10px}
</style></head><body><main>
<h1>Loot Dungeon Sound Lab</h1>
<p class="sub">Every track the 30 Loot Dungeon Beasts play. Species Songs and Name Songs come from the Beasts composer unchanged. Sound Checks are new: the Beast's whole band warms up for ten bars in its key (an opening, three drills drawn from nine, a close), and every take is another routine. Rounds are new, a candidate to replace the Species Song's canon: the harmony comes first (a chord loop in the Beast's mode, in 4/4, 6/8 or 3/4 by family), one line is written over it for each voice, the lines end to end are the theme, and every voice plays that theme exactly, one loop apart. Each line has a shape and opens with the motif's rhythm, lines that step down across a chord change may hold over it as suspensions, and after a sequence canon in the middle the round comes back over a second loop. Monthly Track Editions are new: the edition engine with chromatic harmony after <i>Realm of Common Tones</i> (mode mixture, chromatic mediants, common-tone pivots) and <i>Kingdom of Sweets</i> (applied dominants, diminished sevenths, the Neapolitan and German sixth). Sound effects: regular or mega. ${INSTRUMENTS_NOTE} Beast ids, tiers and families are placeholders until the final list.</p>
<div class="tabs" role="tablist">
<button id="t-song"><b>Species Song</b><span>shared by every Beast of the species</span></button>
<button id="t-round"><b>Round</b><span>new: a canon over a chord loop</span></button>
<button id="t-name"><b>Name Song</b><span>a Beast with a special name</span></button>
<button id="t-check"><b>Sound Check</b><span>new: the band warms up</span></button>
<button id="t-edition"><b>Edition</b><span>a track bought from edition 1</span></button>
</div>
<div class="card">
<div class="row"><button class="nav" id="b-prev" aria-label="Previous Beast">◀</button><div class="mid"><div class="lbl">Beast</div><div class="val" id="b-val"></div></div><button class="nav" id="b-next" aria-label="Next Beast">▶</button></div>
<div class="row" id="row-n"><button class="nav" id="n-prev" aria-label="Previous name">−</button><div class="mid"><div class="lbl">Special name</div><div class="val" id="n-val"></div></div><button class="nav" id="n-next" aria-label="Next name">+</button></div>
<div class="row" id="row-e"><button class="nav" id="e-prev" aria-label="Previous edition">▲</button><div class="mid"><div class="lbl">Edition</div><div class="val" id="e-val"></div></div><button class="nav" id="e-next" aria-label="Next edition">▼</button></div>
<div class="row" id="row-p"><button class="nav" id="p-prev" aria-label="Previous purchase">−</button><div class="mid"><div class="lbl" id="p-lbl">Purchase</div><div class="val" id="p-val"></div></div><button class="nav" id="p-next" aria-label="Next purchase">+</button></div>
<div class="ctl"><button class="go" id="play">▶ Play</button><button id="stop">■ Stop</button><button id="mega">Mega: off</button></div>
<div class="banks" id="banks" role="radiogroup" aria-label="Instruments"></div>
<label class="age" id="row-d">Drift day <b id="d-val"></b> (1 = as written)<input type="range" id="day" min="1" max="400" value="1" aria-label="Drift day"></label>
<label class="age" id="row-v">Reverb <b id="v-val"></b>% (the sample banks; the chip presets keep their own 30)<input type="range" id="rev" min="0" max="100" value="50" aria-label="Reverb"></label>
</div>
<div class="card"><h2 id="title"></h2><dl id="readout"></dl></div>
<div class="card"><canvas id="roll" width="1600" height="440" aria-label="Notes"></canvas><div class="legend" id="legend"></div></div>
<div class="card" id="stylecard"><h2>Edition styles · one a month, in turn</h2><div class="styles" id="styles"></div></div>
<p class="note"><a href="/" style="color:var(--acc)">All pages</a> · <a href="/onchain/lab.html" style="color:var(--acc)">Beasts Lab</a> · <a href="/onchain/drift-lab.html" style="color:var(--acc)">Drift Lab</a></p>
<p class="note">Keys: <span class="kbd">space</span> play/stop, <span class="kbd">←</span> <span class="kbd">→</span> Beast, <span class="kbd">↑</span> <span class="kbd">↓</span> edition, <span class="kbd">[</span> <span class="kbd">]</span> purchase (a Round's 0 is the species' own), <span class="kbd">m</span> mega, <span class="kbd">1</span>-<span class="kbd">9</span> instruments. Block hashes for drift are simulated. ${CREDIT_NOTE}</p>
</main>
<script>${inline(tiny)}</script>
<script>${inline(bundle)}</script>
<script>${inline(bankJs)}</script>
<script>
const DATA = ${JSON.stringify(DATA)};
const KINDS = ['song', 'round', 'name', 'check', 'edition'];
const $ = (id) => document.getElementById(id), RD = BS.rd, CK = BS.ck, E = BS.engine, V = BS.v11, L = BS.lab, ED = BS.ed, U64 = (1n << 64n) - 1n, N = DATA.beasts.length, NSTYLE = DATA.styles.length;
const st = { kind: 'song', b: 0, name: 1, e: 1, p: 1, r: 0, c: 0, day: 1, mega: false, inst: 0, rev: 50 };
(function readUrl() {
  const q = new URLSearchParams(location.search), num = (k, lo, hi, d) => (q.has(k) ? Math.max(lo, Math.min(hi, Math.round(+q.get(k)) || 0)) : d);
  if (KINDS.includes(q.get('track'))) st.kind = q.get('track');
  st.b = num('b', 0, N - 1, 0); st.name = num('name', 1, L.NAME_COUNT, 1); st.e = num('e', 1, NSTYLE * 2, 1); st.p = num('p', 1, 1e6, 1); st.r = num('r', 0, 1e6, 0); st.c = num('c', 0, 1e6, 0); st.day = num('day', 1, 400, 1); st.mega = q.get('mega') === '1'; st.walk = q.get('walk') === '1' ? true : q.get('walk') === '0' ? false : null; st.inst = q.get('inst') === 'chip' ? DATA.insts.length - 1 : Math.max(0, Math.min(DATA.insts.length - 1, +(q.get('inst') || 0) || 0));
})();
let synth = null, playing = false, cur = null, layer = null, layerBank = -1, setProgram0 = null;
const isChip = () => st.inst === DATA.insts.length - 1;
// an optional instrument (organ, pad) in a bank that lacks it: that bank's strings
const padOf = (ch, p) => (DATA.orch.fallback[p] !== undefined && !Banks[st.inst].bank.instruments.some((i) => i.program === p) ? DATA.orch.fallback[p] : p);
const anchor = L.dayAnchor();
const beast = () => DATA.beasts[st.b];
function purchaseSeed(n) { let x = BigInt(n) * 0x9e3779b97f4a7c15n & U64; x ^= x >> 30n; x = x * 0xbf58476d1ce4e5b9n & U64; x ^= x >> 27n; x = x * 0x94d049bb133111ebn & U64; return x ^ (x >> 31n); }
const bOf = (x, named) => { const n = named ? L.nameFromVariant(st.name) : { prefix: 0, suffix: 0 }; return { id: x.id, prefix: n.prefix, suffix: n.suffix, level: 1, health: 100, shiny: st.mega ? 1 : 0, animated: 0, tier: x.tier, beast_type: x.type }; };
// the band: a style's four pools give this track's lead, accompaniment, bass and pad, by Beast, edition and
// purchase (the pad is not the lead's instrument; a bell lead is doubled by the flute, any other by the
// glockenspiel); a song's or a round's channels each take one of their pool by species
const mix = (a, b) => { let x = (Math.imul(a ^ 0x9e3779b9, 0x85ebca6b) ^ Math.imul(b + 0x7f4a7c15, 0xc2b2ae35)) >>> 0; x ^= x >>> 15; x = Math.imul(x, 0x2c1b3c6d) >>> 0; return (x ^ (x >>> 12)) >>> 0; };
// Drift moves the band, at the pace it moves everything else: each month (when the rhythm drifts) a new lead
// and bass, each week (when the channels rotate) a new accompaniment and pad, always another from the same
// pool, never the one the track was written with. Day 1 is as written.
const stepOf = (drift) => (drift ? { month: drift.rhythm !== null ? Number(BigInt(drift.rhythm) & 0xffffffffn) : null, week: drift.rotate !== null ? Number(BigInt(drift.rotate) & 0xffffffffn) : null } : { month: null, week: null });
const moved = (pool, i, h, salt) => (h === null || pool.length < 2 ? i : (i + 1 + mix(h, salt) % (pool.length - 1)) % pool.length);
function band(key, id, e, p, drift, low) {
  const P = DATA.orch.pools[key], { month, week } = stepOf(drift), when = [month, week, month, week];
  const pick = (r, avoid) => { const pool = P[r]; let i = moved(pool, mix(mix(id, e * 131 + r), p) % pool.length, when[r], 31 + r); if (pool[i] === avoid && pool.length > 1) i = (i + 1) % pool.length; return pool[i]; };
  // an accompaniment the composer wrote an octave lower is plucked short (pizzicato): a harp or a guitar rings
  // on down there and blurs
  const lead = pick(0), acc = low ? DATA.orch.low : pick(1, lead), bass = pick(2, lead), pad = pick(3, lead);
  // the descant (the lead's harmony and doubling, channel 1) is never the lead's own instrument (Casey): another
  // from the lead pool
  const others = P[0].filter((g) => g !== lead), descant = others.length ? others[mix(id, e * 389 + p) % others.length] : lead;
  // the second lead (a B or C tune's, on channel 8): the next instrument in the lead pool
  const second = P[0][(P[0].indexOf(lead) + 1 + mix(id, e * 977 + p) % Math.max(1, P[0].length - 1)) % P[0].length];
  return [lead, descant, acc, bass, pad, DATA.orch.bells.includes(lead) ? DATA.orch.flute : DATA.orch.glock, DATA.orch.harp, second];
}
// (a song's other melody voices, its theme's harmony and countersubject, are never the theme's instrument: the next in
// their pool)
const choose = (pools, kinds, id, salt, drift, song) => { const { month, week } = stepOf(drift); const out = pools.map((pool, ch) => pool[moved(pool, mix(mix(id, ch * 977 + 13), salt) % pool.length, kinds[ch] === 'melody' || kinds[ch] === 'bass' ? month : week, 57 + ch)]);
  if (song) for (let ch = 1; ch < out.length; ch++) if (kinds[ch] === 'melody' && out[ch] === out[0]) { const pool = pools[ch], i = pool.indexOf(out[ch]); out[ch] = pool.find((g, k) => k > i && g !== out[0]) ?? pool.find((g) => g !== out[0]) ?? out[ch]; }
  return out; };
// Name Songs and Rounds are written low (a Name Song's theme centres on D3, an octave and a half under a Species
// Song's): the lab plays Name Songs an octave up and Rounds a fifth up, which puts both in the editions'
// register, and plays both with quicker attacks and shorter releases so the low entries do not smear. This is
// the lab's playback only: the composer still writes them where it did.
// One voice keeps its own attack and release (Casey: on these, have one voice normal): the theme (channel 1) on a
// Name Song, the first canon voice on a Round, so a line still sings over the crisp parts.
const LIFT = { name: 12, round: 7 }, CRISP = { name: { attack: 0.4, attackMax: 0.03, release: 0.6, keep: [0] }, round: { attack: 0.4, attackMax: 0.03, release: 0.6, keep: [0] } };
function lifted(u8, by, vol) { // and, with vol (channel: factor, or { f: factor, d: steps taken off after it }), those channels' volume (CC 7) scaled
  if (!by && !vol) return u8;
  const out = u8.slice(); let i = 14; const ntr = (out[10] << 8) | out[11];
  for (let tr = 0; tr < ntr; tr++) {
    i += 4; const len = (out[i] << 24 | out[i + 1] << 16 | out[i + 2] << 8 | out[i + 3]) >>> 0; i += 4; const stop = i + len; let run = 0;
    while (i < stop) {
      let b; do { b = out[i++]; } while (b & 128);
      let s = out[i]; if (s & 128) i++; else s = run;
      if (s === 0xff) { i++; let l = 0; do { b = out[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; }
      if (s === 0xf0 || s === 0xf7) { let l = 0; do { b = out[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; continue; }
      run = s; const ty = s & 0xf0;
      if (ty === 0xc0 || ty === 0xd0) { i += 1; continue; }
      if (by && (ty === 0x80 || ty === 0x90 || ty === 0xa0) && (s & 15) !== 9) out[i] = Math.max(0, Math.min(127, out[i] + by));
      const v = vol && vol[s & 15]; if (v && ty === 0xb0 && out[i] === 7) out[i + 1] = Math.max(0, Math.min(127, Math.round(out[i + 1] * (v.f ?? v) - (v.d ?? 0))));
      i += 2;
    }
    i = stop;
  }
  return out;
}
// the track as it plays: with a sample bank, the highest voice is turned down if its instrument is one of topSoft
function track() {
  const tr = track0(); if (isChip()) return tr;
  const sum = {}; for (const n of notesOf(tr.midi).notes) if (n[3] !== 9 && n[3] !== 6) { const a = sum[n[3]] || (sum[n[3]] = [0, 0]); a[0] += n[2]; a[1]++; }
  const top = Object.keys(sum).sort((a, b) => sum[b][0] / sum[b][1] - sum[a][0] / sum[a][1])[0];
  const f = top === undefined ? 0 : DATA.orch.topSoft[padOf(+top, tr.orch[top % tr.orch.length])];
  return f ? { ...tr, midi: lifted(tr.midi, 0, { [top]: f }), topSoft: +top } : tr;
}
const LEAD_CH = [0, 7]; // an edition's lead and second lead (the descant has its own instrument)
function track0() {
  const x = beast(), day = st.day > 1 ? st.day : null;
  if (st.kind === 'edition') {
    const d = day ? L.drift2({ id: x.id, prefix: 0, suffix: 0 }, day, anchor) : null;
    const o = ED.editionMidi(x, st.mega, st.e, purchaseSeed(st.p), d, false, st.walk);
    const key = DATA.styles[(st.e - 1) % NSTYLE].key, orch = band(key, x.id, st.e, st.p, d, o.info.accompLow), mixOf = DATA.orch.mix[key];
    // the style's mix for the instruments this track drew (sample banks only: the chip presets keep their own)
    // and the lead's own turn-down (leadSoft) on the lead, descant and second-lead channels
    const vol = isChip() ? null : Object.fromEntries(orch.map((g, ch) => { const f = ((mixOf && mixOf[padOf(ch, g)]) || 1) * (LEAD_CH.includes(ch) ? (DATA.orch.leadSoft[padOf(ch, g)] || 1) * DATA.orch.leadAll : 1); return [ch, LEAD_CH.includes(ch) ? { f, d: DATA.orch.leadDrop } : f]; }).filter(([, f]) => f !== 1));
    return { midi: lifted(o.midi, 0, vol), info: o.info, settings: DATA.edition[(st.e - 1) % NSTYLE][x.type][st.mega ? 1 : 0], orch };
  }
  const settings = DATA.family[x.type * 2 + (st.mega ? 1 : 0)];
  if (st.kind === 'round') {
    const d = day ? L.drift2({ id: x.id, prefix: 0, suffix: 0 }, day, anchor) : null;
    const o = RD.roundMidi(x, st.mega, st.r ? purchaseSeed(st.r) : 0n, d);
    return { midi: lifted(o.midi, LIFT.round), info: o.info, settings, orch: choose(DATA.orch.roundPools[x.type], DATA.orch.roundKinds, x.id, 2, d) };
  }
  // a Name Song's band by species and name, its lead from NAME_LEADS; a Species Song's by species
  const named = st.kind === 'name', pools = named ? [DATA.orch.nameLeads, ...DATA.orch.songPools[x.type].slice(1)] : DATA.orch.songPools[x.type];
  const orch = choose(pools, DATA.orch.songKinds, x.id, named ? 1 + st.name * 7919 : 1, day && (st.kind === 'song' || named) ? L.drift2({ id: x.id, prefix: 0, suffix: 0 }, day, anchor) : null, true);
  if (st.kind === 'check') { const o = CK.soundCheckMidi(x, st.mega, st.c ? purchaseSeed(st.c) : 0n); return { midi: o.midi, info: o.info, settings, orch: choose(DATA.orch.roundPools[x.type], DATA.orch.roundKinds, x.id, 2, null) }; }
  const opts = { ...L.GENESIS_DEFAULTS, ...(st.kind === 'name' ? { name: st.name } : {}), ...(day ? { epoch: day, driftMode: 'v2', blockHashes: true } : {}) };
  const o = L.sampleTrackMidi(bOf(x, st.kind === 'name'), { species_count: 1 }, opts, E, V);
  // the theme's lead turn-down (leadSoft), and on a Name Song the nameSoft instruments on any channel
  const vol = isChip() ? null : Object.fromEntries(orch.map((g, ch) => { const q = padOf(ch, g); const f = (ch === 0 ? (DATA.orch.leadSoft[q] || 1) * DATA.orch.leadAll : 1) * ((st.kind === 'name' && DATA.orch.nameSoft[q]) || 1); return [ch, ch === 0 ? { f, d: DATA.orch.leadDrop } : f]; }).filter(([, f]) => f !== 1));
  return { midi: lifted(o.midi, LIFT[st.kind], vol && Object.keys(vol).length ? vol : null), info: o.info, settings, orch };
}
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;');
const COLORS = ['#8a2be2', '#e0742a', '#1f9d8c', '#c0392b', '#7f8c8d', '#2a7ae0', '#b8860b', '#888'];
function show() {
  for (const k of KINDS) $('t-' + k).classList.toggle('on', st.kind === k);
  $('row-n').classList.toggle('off', st.kind !== 'name'); $('row-e').classList.toggle('off', st.kind !== 'edition'); $('row-p').classList.toggle('off', st.kind !== 'edition' && st.kind !== 'round' && st.kind !== 'check');
  $('p-lbl').textContent = st.kind === 'check' ? 'Take' : 'Purchase';
  $('row-d').classList.toggle('off', st.kind === 'check'); // a Name Song drifts by its name, as in Beasts v1.0.1; a Sound Check never drifts
  const x = beast();
  $('b-val').innerHTML = x.id + '. ' + esc(x.name) + ' <small>tier ' + x.tier + ' ' + DATA.types[x.type] + '</small>';
  const nm = L.nameFromVariant(st.name); $('n-val').innerHTML = '#' + st.name + ' <small>prefix ' + nm.prefix + ', suffix ' + nm.suffix + '</small>';
  const g = ED.editionGenome(st.e), S = DATA.styles[g.style];
  $('e-val').innerHTML = st.e + ' · ' + esc(g.name) + ' <small>' + esc(S.label) + ' · ' + g.month + '</small>';
  $('p-val').innerHTML = st.kind === 'round' || st.kind === 'check' ? ((st.kind === 'round' ? st.r : st.c) ? '#' + (st.kind === 'round' ? st.r : st.c) : "the species' own <small>0</small>") : '#' + st.p;
  $('mega').textContent = 'Mega: ' + (st.mega ? 'on' : 'off'); $('mega').classList.toggle('on', st.mega);
  for (const el of $('banks').children) { const on = +el.dataset.k === st.inst; el.classList.toggle('on', on); el.firstChild.checked = on; }
  $('d-val').textContent = st.day; $('day').value = st.day;
  $('v-val').textContent = st.rev; $('rev').value = st.rev; $('row-v').classList.toggle('off', isChip());
  cur = track();
  const i = cur.info || {};
  const rows = st.kind === 'edition'
    ? [['Style', S.label + ' (' + i.family + ')'], ['Key', i.key], ['Meter / tempo', i.meter + ' · ' + i.bpm + ' BPM'], ['Form', i.form], ['A', i.progA], ['B', i.progB], ...(i.progC ? [['C', i.progC]] : []), ['Parts', i.parts.join(', ')], ['Intro', i.intro], ['Bass', i.bass], ['Drums', i.drums], ['Lead doubled', i.doubling], ['Last tune', i.lastTune], ['Second lead', i.secondLead], ['Taken faster', i.quicker ? i.quicker + '%' : 'no'], ['Accompaniment', i.accomp], ['Chords', i.chords], ['Glissandi', i.glissandi], ['Theme', i.theme], ['Ornaments', i.ornaments], ['Phrasing', i.phrasing], ['Length', i.seconds + ' s']]
    : st.kind === 'round' ? [['Key', i.key], ['Tempo', i.bpm + ' BPM'], ['Meter', i.meter], ['Form', i.form], ['Loop', i.loop + ' (' + i.loopBars + ' bars)'], ['Second loop', i.loopB], ['Voices', i.voices + ', entering ' + i.entries], ['Lines', i.shapes + ' · registers: ' + i.contour], ['Theme', i.themeBars + ' bars: ' + i.theme], ['Second theme', i.themeB], ['Motif rhythm', i.motifRhythm], ['Suspensions', i.suspensions], ['Glissandi', i.glissandi], ['Episode', i.episode], ['Cadence', i.cadence], ['Bass', i.bass], ['Percussion', i.percussion], ['Ornaments', i.ornaments], ['Drift', i.drift], ['Length', i.seconds + ' s']]
    : st.kind === 'check' ? [['Key', i.key], ['Tempo', i.bpm + ' BPM'], ['Opening', i.opening], ['Drills', i.drills], ['Close', i.close], ['Colour note', i.colour], ['Cadence', i.cadence], ['Band', i.band], ['Glissandi', i.glissandi], ['Length', i.seconds + ' s']]
    : [['Key', i.key], ['Voices', i.voices], ['Tempo', i.bpm ? i.bpm + ' BPM' : ''], ['Drift', st.day > 1 ? 'day ' + st.day : 'as written']];
  if (LIFT[st.kind]) rows.push(['Played', LIFT[st.kind] + ' semitones above the written key, with quicker attacks (in this lab)']);
  $('title').textContent = { song: x.name + "'s Species Song", round: x.name + "'s Round" + (st.r ? ' · purchase #' + st.r : ''), name: x.name + "'s Name Song", check: x.name + "'s Sound Check" + (st.c ? ' · take #' + st.c : ''), edition: g.name }[st.kind] + (st.mega ? ' · mega' : '');
  $('readout').innerHTML = rows.filter((r) => r[1] !== undefined && r[1] !== '').map(([a, b]) => '<dt>' + a + '</dt><dd>' + esc(b) + '</dd>').join('');
  $('styles').innerHTML = DATA.styles.map((s, k) => '<button data-k="' + k + '" class="' + (st.kind === 'edition' && g.style === k ? 'on' : '') + '"><b>' + (k + 1) + '. ' + esc(s.label) + '</b><span>' + (s.family ? s.family.split(' ')[0] : k < 6 ? 'Realm' : 'Sweets') + ' · ' + esc(s.desc) + '</span></button>').join('');
  for (const bt of $('styles').querySelectorAll('button')) bt.onclick = () => { st.kind = 'edition'; st.e = +bt.dataset.k + 1; change(); };
  roll(cur.midi);
  if (!isChip() && window.Banks && Banks[st.inst].need) Banks[st.inst].need(wanted()); // start preparing this track's sounds
  history.replaceState(null, '', '?' + new URLSearchParams({ track: st.kind, b: st.b, name: st.name, e: st.e, p: st.p, r: st.r, day: st.day, ...(st.mega ? { mega: 1 } : {}), ...(st.inst ? { inst: isChip() ? 'chip' : st.inst } : {}) }));
}
function notesOf(u8) {
  const notes = [], prog = {}; let end = 0, i = 14, ntr = (u8[10] << 8) | u8[11];
  for (let tr = 0; tr < ntr; tr++) {
    i += 4; const len = (u8[i] << 24 | u8[i + 1] << 16 | u8[i + 2] << 8 | u8[i + 3]) >>> 0; i += 4; const stop = i + len; let t = 0, run = 0; const on = {};
    while (i < stop) {
      let d = 0, b; do { b = u8[i++]; d = (d << 7) | (b & 127); } while (b & 128); t += d;
      let s = u8[i]; if (s & 128) i++; else s = run;
      if (s === 0xff) { const ty = u8[i++]; let l = 0; do { b = u8[i++]; l = (l << 7) | (b & 127); } while (b & 128); i += l; if (ty === 0x2f) end = Math.max(end, t); continue; }
      run = s; const ty = s & 0xf0, ch = s & 15;
      if (ty === 0xc0 || ty === 0xd0) { if (ty === 0xc0) prog[ch] = u8[i]; i += 1; continue; }
      const a = u8[i], v = u8[i + 1]; i += 2;
      if (ty === 0x90 && v) on[ch * 128 + a] = [t, v];
      else if (ty === 0x80 || ty === 0x90) { const k = ch * 128 + a; if (on[k] !== undefined) { notes.push([on[k][0], t, a, ch, on[k][1]]); delete on[k]; } }
    }
    i = stop;
  }
  return { notes, prog, end: Math.max(end, ...notes.map((n) => n[1])) };
}
const ROLES = { 0: 'lead', 1: 'descant', 2: 'accomp', 3: 'bass', 4: 'pad', 5: 'mega double', 6: 'harp glissando', 7: 'second lead' };
// a channel's instrument as it sounds: the bank's (the orchestration) or the TinyChip preset
const instName = (ch, prog) => (isChip() || !cur ? DATA.names[prog] || '' : DATA.orch.names[padOf(ch, cur.orch[ch % cur.orch.length])] || '');
let rollData = null;
function roll(midi) {
  rollData = notesOf(midi);
  const chans = [...new Set(rollData.notes.map((n) => n[3]))].sort((a, b) => a - b);
  $('legend').innerHTML = chans.map((ch) => '<span><i style="background:' + (ch === 9 ? 'var(--mut)' : COLORS[ch % 8]) + '"></i>' + (ch === 9 ? 'drums' : (st.kind === 'edition' ? ROLES[ch] : st.kind === 'round' ? (ch < 4 ? 'voice on ch' + (ch + 1) : ch === 4 ? 'bass' : ch === 6 ? 'harp glissando' : 'mega double') : st.kind === 'check' ? CK.PART_NAMES[ch] : 'ch' + (ch + 1)) + ' · ' + esc(instName(ch, rollData.prog[ch]))) + '</span>').join('');
  draw(-1);
}
function draw(play) {
  const c = $('roll'), x = c.getContext('2d'), W = c.width, H = c.height, d = rollData; x.clearRect(0, 0, W, H); if (!d || !d.notes.length) return;
  const tones = d.notes.filter((n) => n[3] !== 9), lo = Math.min(...tones.map((n) => n[2])) - 2, hi = Math.max(...tones.map((n) => n[2])) + 2, ph = H - 40, sx = W / d.end, fg = getComputedStyle(document.body).color;
  for (const [a, b, p, ch, v] of d.notes) {
    x.globalAlpha = 0.3 + 0.7 * v / 127;
    if (ch === 9) { x.fillStyle = fg; x.fillRect(a * sx, H - 30 + (p % 8) * 3, Math.max(2, (b - a) * sx * 0.5), 3); continue; }
    x.fillStyle = COLORS[ch % 8]; x.fillRect(a * sx, 4 + (hi - p) / (hi - lo) * ph, Math.max(2, (b - a) * sx - 1), Math.max(3, ph / (hi - lo) - 1));
  }
  x.globalAlpha = 1; if (play >= 0) { x.fillStyle = fg; x.fillRect((play % d.end) * sx, 0, 3, H); }
}
(function loop() { if (playing && synth && synth.tick2Time) draw(synth.playTick - (synth.playTime - synth.actx.currentTime) / synth.tick2Time); requestAnimationFrame(loop); })();
// the notes a track plays, as [program, note]: a bank that renders its sounds prepares these first
const wanted = () => { const seen = new Set(), out = []; if (!rollData || !cur) return out; for (const n of rollData.notes) { if (n[3] === 9) continue; const g = padOf(n[3], cur.orch[n[3] % cur.orch.length]), k = g * 128 + n[2]; if (!seen.has(k)) { seen.add(k); out.push([g, n[2]]); } } return out; };
let startTok = 0;
// play, from a tick when one is given; a rendering bank is given the moment it needs to have this track's sounds ready
function start(at) {
  if (!cur) return;
  const tok = ++startTok, bankNow = isChip() ? null : Banks[st.inst];
  if (bankNow && bankNow.need) { const w = bankNow.need(wanted()); if (w.pending) { playing = true; $('play').textContent = 'Preparing…'; w.then(() => { $('play').textContent = '▶ Play'; if (tok === startTok && playing) go(at); }); return; } }
  go(at);
}
function go(at) {
  if (!synth) synth = new WebAudioTinySynth({ quality: 1, useReverb: 1, voices: 64 });
  synth.getAudioContext().resume(); synth.stopMIDI();
  BS.installSettings(synth, cur.settings);
  if (!isChip()) synth.setReverbLev(st.rev / 100); // the settings carry the chip presets' reverb (30); the sample banks play in more
  if (layer && (isChip() || layerBank !== st.inst)) { synth.setProgram = setProgram0; layer.dispose(); layer = null; layerBank = -1; }
  if (!isChip() && !layer) { layer = Banks[st.inst].attach(synth, { maxVoices: 48 }); /* 24 was too few: a glissando over ringing chords needs 31, and a stolen voice clicks */ layerBank = st.inst; setProgram0 = synth.setProgram; synth.setProgram = (ch, p, ...r) => setProgram0.call(synth, ch, ch === 9 || !cur ? p : padOf(ch, cur.orch[ch % cur.orch.length]), ...r); }
  if (layer && layer.sampler.articulate) layer.sampler.articulate(CRISP[st.kind]);
  const m = cur.midi;
  synth.loadMIDI(m.buffer.slice(m.byteOffset, m.byteOffset + m.length));
  synth.setLoop(1); synth.setLoopEnd(synth.getPlayStatus().maxTick); synth.playMIDI(); playing = true;
  if (at != null && synth.locateMIDI) { try { synth.locateMIDI(at); } catch (e) {} }
}
function stop() { startTok++; $('play').textContent = '▶ Play'; if (synth) synth.stopMIDI(); playing = false; draw(-1); }
function change() { show(); if (playing) start(); }
const setKind = (k) => { st.kind = k; change(); };
for (const k of KINDS) $('t-' + k).onclick = () => setKind(k);
const step = (k, d) => { if (k === 'b') st.b = (st.b + d + N) % N; if (k === 'n') st.name = Math.max(1, Math.min(L.NAME_COUNT, st.name + d)); if (k === 'e') st.e = (st.e - 1 + d + NSTYLE * 2) % (NSTYLE * 2) + 1; if (k === 'p') { if (st.kind === 'round') st.r = Math.max(0, st.r + d); else if (st.kind === 'check') st.c = Math.max(0, st.c + d); else st.p = Math.max(1, st.p + d); } change(); };
$('b-prev').onclick = () => step('b', -1); $('b-next').onclick = () => step('b', 1);
$('n-prev').onclick = () => step('n', -1); $('n-next').onclick = () => step('n', 1);
$('e-prev').onclick = () => step('e', -1); $('e-next').onclick = () => step('e', 1);
$('p-prev').onclick = () => step('p', -1); $('p-next').onclick = () => step('p', 1);
$('play').onclick = () => start(); $('stop').onclick = stop; $('mega').onclick = () => { st.mega = !st.mega; change(); }; // the instrument sets: a label is a name, or name|note; choosing one while playing carries on from the same place
$('banks').innerHTML = DATA.insts.map((s, k) => { const [a, b] = s.split('|'); return '<label data-k="' + k + '"><input type="radio" name="bank"><span><b>' + (k + 1) + '. ' + esc(a) + '</b>' + (b ? '<span>' + esc(b) + '</span>' : '') + '</span></label>'; }).join('');
function pick(k) { if (k === st.inst || k < 0 || k >= DATA.insts.length) return; const at = playing && synth ? synth.playTick : null; st.inst = k; show(); if (playing) start(at); }
for (const el of $('banks').children) el.firstChild.onchange = () => pick(+el.dataset.k);
$('rev').oninput = () => { st.rev = +$('rev').value; $('v-val').textContent = st.rev; if (synth && !isChip()) synth.setReverbLev(st.rev / 100); };
$('day').oninput = () => { st.day = +$('day').value; show(); }; $('day').onchange = () => { if (playing) start(); };
document.addEventListener('keydown', (ev) => {
  if ((ev.target.tagName === 'INPUT' && ev.target.type !== 'radio') || ev.metaKey || ev.ctrlKey) return;
  if (ev.key === ' ') { ev.preventDefault(); playing ? stop() : start(); }
  else if (ev.key === 'ArrowLeft' || ev.key === 'ArrowRight') step('b', ev.key === 'ArrowRight' ? 1 : -1);
  else if (ev.key === 'ArrowUp' || ev.key === 'ArrowDown') { ev.preventDefault(); step('e', ev.key === 'ArrowDown' ? 1 : -1); }
  else if (ev.key === '[' || ev.key === ']') step('p', ev.key === ']' ? 1 : -1);
  else if (ev.key === 'm') { st.mega = !st.mega; change(); }
  else if (/^[1-9]$/.test(ev.key)) pick(+ev.key - 1);
});
show();
</script></body></html>`;
mkdirSync(new URL('../public/', import.meta.url), { recursive: true });
writeFileSync(new URL('../public/' + outName, import.meta.url), html);
console.log(outName, html.length, 'bytes');
