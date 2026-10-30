import { readFileSync } from 'node:fs';
import { spriteSheet } from './lab-sprites.mjs';

// Shared SVG definitions stay deduplicated in the generated pages; only the selected card expands.
export function loadLabCards() {
  const { source, fragments, cards, gifs } = JSON.parse(readFileSync(new URL('./fixtures/lab-cards.json', import.meta.url)));
  const sprites = Object.fromEntries(Object.keys(gifs).map((key) => {
    const { n, w, png } = spriteSheet(key, gifs);
    return [key, { n, w, png }];
  }));
  return { source, fragments, cards, sprites };
}
