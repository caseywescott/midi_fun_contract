// The 30 Loot Dungeon Beasts: the final list (Casey, 16 November 2026, with the art in Loot_Beasts_Final):
// species ids 78-107, 10 per family (0 Magic, 1 Hunter, 2 Brute), two per tier within each family. The id,
// tier and family reach the music (key, theme, drift); the names are labels.
const LIST = [
  [78, 'Koschei', 0, 1], [79, 'Dybbuk', 0, 1], [80, 'Siren', 0, 2], [81, 'Pontianak', 0, 2], [82, 'Poltergeist', 0, 3],
  [83, 'Leshy', 0, 3], [84, 'Tengu', 0, 4], [85, 'Kikimora', 0, 4], [86, 'Kodama', 0, 5], [87, 'Brownie', 0, 5],
  [88, 'Nuckelavee', 1, 1], [89, 'Simurgh', 1, 1], [90, 'Akhlut', 1, 2], [91, 'Peryton', 1, 2], [92, 'Alicanto', 1, 3],
  [93, 'Bonnacon', 1, 3], [94, 'Wulver', 1, 4], [95, 'Strix', 1, 4], [96, 'Enfield', 1, 5], [97, 'Kamaitachi', 1, 5],
  [98, 'Surtr', 2, 1], [99, 'Gashadokuro', 2, 1], [100, 'Talos', 2, 2], [101, 'Aspidochelone', 2, 2], [102, 'Antaeus', 2, 3],
  [103, 'Fomorian', 2, 3], [104, 'Humbaba', 2, 4], [105, 'Buggane', 2, 4], [106, 'Bugbear', 2, 5], [107, 'Domovoi', 2, 5],
];
export const LOOT_FIRST = 78, LOOT_COUNT = 30;
export const LOOT_BEASTS = LIST.map(([id, name, type, tier]) => ({ id, name, tier, type }));
export const lootBeast = (id) => LOOT_BEASTS[id - LOOT_FIRST];
