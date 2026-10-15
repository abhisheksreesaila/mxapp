// Checks Flint specs (one "FLINT: {json}" per line on stdin) with Flint itself: each compiles through
// Flint's Vega-Lite backend (assembleVegaLite throws on input it can't use; any warning also fails),
// then Vega-Lite → Vega → an SVG (svg/<n>.svg) that must show the data's labels. (flint-chart 0.5.1
// on npm has no validateChart export yet; D-77.) Prints one line per chart and "VALID n/m".
// Run from build/flint after: npm install flint-chart vega vega-lite
import { assembleVegaLite } from 'flint-chart';
import * as vl from 'vega-lite';
import * as vega from 'vega';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';

const lines = readFileSync(0, 'utf8').split('\n').filter(l => l.startsWith('FLINT: '));
mkdirSync('svg', { recursive: true });
let ok = 0;
for (const [n, line] of lines.entries()) {
  const input = JSON.parse(line.slice(7));
  const name = `${input.chart_spec.chartType}: ${input.chart_spec.title || ''}`;
  try {
    const columns = new Set(Object.keys(input.data.values[0] || {}));  // every encoded field must be in the data
    for (const [channel, enc] of Object.entries(input.chart_spec.encodings)) {
      const field = typeof enc === 'string' ? enc : enc.field;
      if (field && !columns.has(field)) throw new Error(`encoding ${channel} names "${field}", which isn't in the data`);
    }
    const spec = assembleVegaLite(input);
    const warnings = spec._warnings || [];
    for (const k of Object.keys(spec)) if (k.startsWith('_')) delete spec[k];
    const view = new vega.View(vega.parse(vl.compile(spec).spec), { renderer: 'none' });
    const svg = await view.toSVG();
    writeFileSync(`svg/${n}.svg`, svg);
    // Flint's own warnings fail the spec, and the picture must show the data's labels.
    const labels = input.data.values.map(r => Object.values(r).find(v => typeof v === 'string')).filter(Boolean);
    const missing = labels.slice(0, 3).filter(l => !svg.includes(l.replace(/&/g, '&amp;').replace(/"/g, '&quot;')));
    if (warnings.length) throw new Error('Flint warnings: ' + JSON.stringify(warnings).slice(0, 300));
    if (missing.length) throw new Error('labels missing from the SVG: ' + missing.join(', '));
    ok++;
    console.log(`OK  ${name} (${svg.length} bytes of SVG, labels shown, no warnings)`);
  } catch (e) {
    console.log(`BAD ${name}: ${e}`);
  }
}
console.log(`VALID ${ok}/${lines.length}`);
