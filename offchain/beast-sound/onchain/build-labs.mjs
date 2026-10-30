import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const inputs = process.argv.slice(2);
if (inputs.length !== 2) throw new Error('usage: npm run build:labs -- <engine .min.js> <onchain-midi-player checkout>');
for (const page of ['drift-lab', 'editions-onchain', 'lab']) {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL(`./${page}-demo.mjs`, import.meta.url)), ...inputs], { stdio: 'inherit' });
  if (result.status !== 0) process.exit(result.status || 1);
}
