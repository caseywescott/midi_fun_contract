import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

for (const page of ['drift-lab', 'editions-onchain', 'lab']) {
  const result = spawnSync(process.execPath, [fileURLToPath(new URL(`./${page}-demo.mjs`, import.meta.url))], { stdio: 'inherit' });
  if (result.status !== 0) process.exit(result.status || 1);
}
