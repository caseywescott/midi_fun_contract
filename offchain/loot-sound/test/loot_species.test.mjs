import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { LOOT_BEASTS, LOOT_FIRST, LOOT_COUNT, lootBeast, musicalId } from '../src/loot_beasts.js';
import { SPECIES } from '../src/loot_species.js';

test('canonical 78-107 allocation matches names, families and tiers', () => {
  const names = 'Koschei Dybbuk Siren Pontianak Poltergeist Leshy Tengu Kikimora Kodama Brownie Nuckelavee Simurgh Akhlut Peryton Alicanto Bonnacon Wulver Strix Enfield Kamaitachi Surtr Gashadokuro Talos Aspidochelone Antaeus Fomorian Humbaba Buggane Bugbear Domovoi'.split(' ');
  assert.equal(LOOT_FIRST, 78);
  assert.equal(LOOT_COUNT, 30);
  assert.equal(LOOT_BEASTS.length, names.length);
  names.forEach((name, k) => {
    const expected = { id: 78 + k, name, tier: Math.floor((k % 10) / 2) + 1, type: Math.floor(k / 10) };
    assert.deepEqual(lootBeast(78 + k), expected);
    assert.equal(musicalId(78 + k), 76 + k);
    const theme = SPECIES[k];
    assert.deepEqual([theme.id, theme.tier, theme.type], [expected.id, expected.tier, expected.type]);
  });
});

test('adjacent Beasts and invalid IDs have no Loot alias', () => {
  for (const id of [0, 76, 77, 108, 2 ** 32 - 1, 78.5, NaN]) {
    assert.equal(lootBeast(id), undefined);
    assert.throws(() => musicalId(id), /not a Loot Beast/);
  }
});

test('published lab contains the current catalogue and generated themes', () => {
  const html = readFileSync(new URL('../public/loot-lab.html', import.meta.url), 'utf8');
  const data = JSON.parse(html.match(/^const DATA = (.*);$/m)[1]);
  assert.deepEqual(data.beasts, LOOT_BEASTS.map((b, k) => ({ ...b, ...SPECIES[k] })));
});
