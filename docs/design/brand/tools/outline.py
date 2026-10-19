"""Outline the word "omxplorer" in Inter (repo copy) to one SVG path, so the logo files need no font.
Run: pixi exec -s fonttools -s python=3.12 python outline.py"""
import json, pathlib
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.boundsPen import BoundsPen
FONTS = pathlib.Path(__file__).resolve().parents[4] / 'mojoui/hosts/static/fonts'
out = {}
for weight in ('SemiBold', 'Medium'):
  for word in ('omxplorer', 'mxplorer'):
      f = TTFont(FONTS / f'Inter-{weight}.ttf')
      gs, cmap, hmtx = f.getGlyphSet(), f.getBestCmap(), f['hmtx']
      upm = f['head'].unitsPerEm
      track = -0.025 * upm  # Inter display-style tightening
      pen = SVGPathPen(gs); bp = BoundsPen(gs); x = 0
      for ch in word:
          g = cmap[ord(ch)]
          t = (1, 0, 0, -1, x, 0)  # flip y: baseline at y=0, ascenders negative
          gs[g].draw(TransformPen(pen, t)); gs[g].draw(TransformPen(bp, t))
          x += hmtx[g][0] + track
      xmin, ymin, xmax, ymax = bp.bounds
      out[f'{weight}:{word}'] = dict(d=pen.getCommands(), upm=upm, xmin=xmin, xmax=xmax, top=ymin, bottom=ymax,
                         xh=f['OS/2'].sxHeight)
pathlib.Path(__file__).with_name('wordmark.json').write_text(json.dumps(out))
print({k: (v['xmin'], v['xmax'], v['top'], v['bottom'], v['xh']) for k, v in out.items()})
