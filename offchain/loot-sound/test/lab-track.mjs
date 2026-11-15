// Exercise the published lab's actual track(), band, seed and private-Beast wiring in Node.
import vm from 'node:vm';
export function loadLab(html) {
  const scripts = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)].map((m) => m[1]);
  const context = { window: {}, TextEncoder, TextDecoder, console };
  vm.runInNewContext(scripts[1], context);
  const page = scripts[3];
  const data = JSON.parse(page.match(/^const DATA = (.*);$/m)[1]);
  const seed = page.match(/^function purchaseSeed\(n\) .*$/m)[0];
  const beast = page.match(/^const bOf = .*$/m)[0];
  const music = page.slice(page.indexOf('const mix = (a, b) =>'), page.indexOf('const esc = '));
  const track = new Function('DATA', 'BS', 'st', `
    const { rd: RD, ck: CK, ed: ED, engine: E, v11: V, lab: L } = BS;
    const U64 = (1n << 64n) - 1n, NSTYLE = DATA.styles.length;
    const anchor = L.dayAnchor(), beast = () => DATA.beasts[st.b];
    ${seed}\n${beast}\n${music}\nreturn track();`);
  return { data, track: (state) => track(data, context.window.BS, state) };
}
