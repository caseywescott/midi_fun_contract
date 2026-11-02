// Compile the actual MidiSoundPage with a candidate bank in a temporary workspace.
// node onchain/snes/measure-cairo.mjs [manifest.json]
// node onchain/snes/measure-cairo.mjs --stress-bytes 20480  (synthetic size probe only)
import { cpSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { execFileSync } from 'node:child_process';
import { build } from 'esbuild';
import { buildBank, bundleBank, cairoData } from './build.mjs';
import { storedSegment } from '../page.js';
import { DEFAULT_ENVELOPE } from './bank.js';
const here = fileURLToPath(new URL('.', import.meta.url)), root = resolve(here, '../../../..');
const dir = mkdtempSync(join(tmpdir(), 'snes-cairo-'));
try {
  let bank, brrBytes;
  if (process.argv[2] === '--stress-bytes') {
    const requested = Number(process.argv[3]);
    if (!Number.isInteger(requested) || requested < 9 || requested > 65536) throw new Error('stress bytes must be 9–65536');
    const bytes = new Uint8Array(Math.floor(requested / 9) * 9);
    let seed = 0x12345678;
    for (let i = 0; i < bytes.length; i++) { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; bytes[i] = i % 9 ? seed & 255 : 0x90; }
    bytes[bytes.length - 9] |= 1;
    bank = { format: 'BSBRR1', samples: [{ rate: 16000, loopStart: null, data: Buffer.from(bytes).toString('base64') }], instruments: [{ id: 'size-test-only', program: 0, sample: 0, rootNote: 60, tuneCents: 0, volume: 0.5, envelope: DEFAULT_ENVELOPE, credit: { author: 'Test', license: 'Test only', source: 'Synthetic size probe' } }] };
    brrBytes = bytes.length;
  } else {
    const result = buildBank(process.argv[2] ?? resolve(here, 'manifest.json'));
    bank = result.bank; brrBytes = result.report.brrBytes;
  }
  const runtime = await bundleBank(bank);
  const player = await build({ entryPoints: [resolve(here, 'player-src.js')], bundle: true, minify: true, write: false, target: 'es2020' });
  const tiny = readFileSync(resolve(here, '../dist/tinysynth.min.js'), 'utf8').trim();
  const stored = storedSegment([tiny, runtime, player.outputFiles[0].text.trim()].join('\n'));
  mkdirSync(join(dir, 'core'), { recursive: true });
  for (const name of ['midi', 'midi_contracts']) cpSync(join(root, 'core', name), join(dir, 'core', name), { recursive: true, filter: (p) => !p.split('/').at(-1).startsWith('._') });
  const manifest = readFileSync(join(root, 'Scarb.toml'), 'utf8').replace(/members = \[[\s\S]*?\]/, 'members = ["core/midi", "core/midi_contracts"]');
  writeFileSync(join(dir, 'Scarb.toml'), manifest);
  for (const name of ['Scarb.lock', '.tool-versions']) cpSync(join(root, name), join(dir, name));
  writeFileSync(join(dir, 'core/midi_contracts/src/page/page_data.cairo'), cairoData(stored));
  execFileSync('scarb', ['build', '-p', 'midi_contracts'], { cwd: dir, stdio: ['ignore', 'inherit', 'inherit'] });
  const casm = JSON.parse(readFileSync(join(dir, 'target/dev/midi_contracts_MidiSoundPage.compiled_contract_class.json')));
  const sierra = JSON.parse(readFileSync(join(dir, 'target/dev/midi_contracts_MidiSoundPage.contract_class.json')));
  const report = { brrBytes, pageStoredBytes: stored.length, pageDataWords: stored.length / 31, casmFelts: casm.bytecode.length, sierraFelts: sierra.sierra_program.length, configuredCasmLimit: 81920, casmHeadroom: 81920 - casm.bytecode.length, gasMeasured: false };
  console.log(JSON.stringify(report, null, 2));
  if (report.casmHeadroom < 0) process.exitCode = 1;
} finally { rmSync(dir, { recursive: true, force: true }); }
