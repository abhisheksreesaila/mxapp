// Checks Flint specs (one "FLINT: {json}" per line on stdin) with Flint itself: each compiles through
// Flint's Vega-Lite backend (assembleVegaLite throws on input it can't use), then Vega-Lite → Vega →
// an SVG (written to svg/<n>.svg). Prints one line per chart and "VALID n/m".
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
    const spec = assembleVegaLite(input);
    const warnings = spec._warnings || [];
    for (const k of Object.keys(spec)) if (k.startsWith('_')) delete spec[k];
    const view = new vega.View(vega.parse(vl.compile(spec).spec), { renderer: 'none' });
    const svg = await view.toSVG();
    writeFileSync(`svg/${n}.svg`, svg);
    ok++;
    console.log(`OK  ${name} (${svg.length} bytes of SVG${warnings.length ? ', ' + warnings.length + ' warnings' : ''})`);
  } catch (e) {
    console.log(`BAD ${name}: ${e}`);
  }
}
console.log(`VALID ${ok}/${lines.length}`);
