"""Screenshots the mockups (PNG beside each HTML) and the index page. Run: pixi run python docs/design/brand/tools/shoot.py"""
import pathlib, sys
from playwright.sync_api import sync_playwright
OUT = pathlib.Path(__file__).resolve().parents[1]
with sync_playwright() as p:
    b = p.chromium.launch(executable_path='/usr/bin/chromium')
    pg = b.new_page(viewport={'width': 1280, 'height': 720}, device_scale_factor=2)
    for f in sorted((OUT / 'mockups').glob('*.html')):
        pg.goto(f.as_uri()); pg.wait_for_timeout(300)
        pg.screenshot(path=str(f.with_suffix('.png')))
    pg = b.new_page(viewport={'width': 1400, 'height': 900})
    pg.goto((OUT / 'index.html').as_uri()); pg.wait_for_timeout(500)
    pg.screenshot(path=sys.argv[1] if len(sys.argv) > 1 else '/tmp/brand-index.png', full_page=True)
    b.close()
