// Canonical Loot Dungeon species allocation. IDs 76 and 77 belong to other Beasts.
// Ten species per family (0 magic, 1 hunter, 2 brute), two per tier.
export const LOOT_FIRST = 78, LOOT_COUNT = 30;
const NAMES = ["Koschei", "Dybbuk", "Siren", "Pontianak", "Poltergeist", "Leshy", "Tengu", "Kikimora", "Kodama", "Brownie", "Nuckelavee", "Simurgh", "Akhlut", "Peryton", "Alicanto", "Bonnacon", "Wulver", "Strix", "Enfield", "Kamaitachi", "Surtr", "Gashadokuro", "Talos", "Aspidochelone", "Antaeus", "Fomorian", "Humbaba", "Buggane", "Bugbear", "Domovoi"];
export const LOOT_BEASTS = NAMES.map((name, k) => ({
  id: LOOT_FIRST + k,
  name,
  tier: Math.floor((k % 10) / 2) + 1,
  type: Math.floor(k / 10),
}));
export const lootBeast = (id) => Number.isInteger(id) && id >= LOOT_FIRST && id < LOOT_FIRST + LOOT_COUNT
  ? LOOT_BEASTS[id - LOOT_FIRST] : undefined;

// Preserve the soundtrack authored at provisional IDs 76-105. Public IDs stay 78-107.
export function musicalId(id) {
  if (!lootBeast(id)) throw new RangeError('not a Loot Beast');
  return id - LOOT_FIRST + 76;
}
