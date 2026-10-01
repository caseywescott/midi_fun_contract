// poseidon_lite must equal @scure/starknet's poseidonHashMany everywhere the engine can reach.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { poseidonHashMany as reference } from '@scure/starknet';
import { poseidonHashMany as lite } from '../src/poseidon_lite.js';
import { createEngine } from '../src/engine.js';
import { genesisBeast } from '../src/index.js';

const P = 2n ** 251n + 17n * 2n ** 192n + 1n;

test('matches @scure/starknet on edge and random inputs', () => {
  const cases = [[], [0n], [1n], [P - 1n], [1n, 2n], [1n, 2n, 3n], Array.from({ length: 9 }, (_, i) => BigInt(i) * 0x123456789abcdefn)];
  let x = 0x9e3779b97f4a7c15n;
  for (let n = 0; n < 200; n++) {
    const len = n % 7;
    const v = [];
    for (let i = 0; i < len; i++) { x = (x * 6364136223846793005n + 1442695040888963407n) % P; v.push(x); }
    cases.push(v);
  }
  for (const v of cases) assert.equal(lite(v), reference(v), JSON.stringify(v.map(String)));
});

test('engine renders identical scores with either hash', () => {
  const a = createEngine({ poseidonHashMany: reference });
  const b = createEngine({ poseidonHashMany: lite });
  for (const id of [1, 26, 51, 75]) {
    for (const traits of [{}, { prefix: 33, suffix: 10, level: 126, health: 229 }]) {
      const beast = genesisBeast({ id, ...traits });
      for (const live of [{ adventurers_killed: 0, scars: 0, summit_held_seconds: 0, rank: 0, species_count: 1243 }, { adventurers_killed: 412, scars: 7, summit_held_seconds: 86400, rank: 3, species_count: 1243 }]) {
        assert.equal(b.render(beast, live).form.score_hash, a.render(beast, live).form.score_hash);
      }
    }
  }
});
