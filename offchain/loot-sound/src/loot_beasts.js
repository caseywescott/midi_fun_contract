// The 30 Loot Dungeon Beasts. PLACEHOLDER until Provable Games sends the real list: species ids
// 76-105, 10 per family (0 magic, 1 hunter, 2 brute) and two per tier within each family. Only the
// id, tier and family reach the music; the names are labels.
export const LOOT_FIRST = 76, LOOT_COUNT = 30;
export const LOOT_BEASTS = Array.from({ length: LOOT_COUNT }, (_, k) => ({
  id: LOOT_FIRST + k,
  name: 'Loot Beast ' + (LOOT_FIRST + k),
  tier: Math.floor((k % 10) / 2) + 1,
  type: Math.floor(k / 10),
}));
export const lootBeast = (id) => LOOT_BEASTS[id - LOOT_FIRST];
