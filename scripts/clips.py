"""Record omxplorer's launch clips (docs/launch/posts.md): the native window and the browser, from a separate build folder.

  pixi run python scripts/clips.py [native|web|all]      → build/clips/sentence-gtk.mp4, sentence-web.mp4 (+ stills)

native: GTK on the private headless display through scripts/live.py (real XTest input); only the ask field, because a
popover's shadow draws black on Xvfb (no compositor). web: headless Chromium, where a word's
popover is HTML: tap "Sum", pick Average (frames from Chromium's screencast, timed into a video by ffmpeg). Both open build/data/orders_1m.csv. Copies the builds to build/clips first,
so a check running from build/ never sees its binary change mid-run.
"""
import os
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "build/clips"
DATA = ROOT / "build/data/orders_1m.csv"
SIZE = (1742, 876)
WEB = (1742, 1100)  # (the browser's board scrolls the chart under the fold at 876)

NATIVE = ";".join([
    "wait:5000", "click:1352,819", "wait:2500",  # Import → Create table
    "click:737,75", "wait:1500",  # toolbar Chart
    "drag:537,761,1390,761", "wait:1200", "move:900,300", "wait:600",  # the chart's corner: as wide as the table
    "record:{out}/sentence-gtk.mp4", "wait:1500",
    "click:280,507", "wait:300", "type:by product, largest first, top 5", "wait:500", "key:Return", "wait:2200",
    "click:280,507", "wait:300", "type:median", "wait:500", "key:Return", "wait:2200",
    "click:280,507", "wait:300", "type:sum by month, every month, in data order, as a line", "wait:500", "key:Return", "wait:2800",
    "shot:{out}/sentence-gtk.png", "stoprecord",
])


def native():
    shutil.rmtree(OUT / "gtk", ignore_errors=True)
    shutil.copytree(ROOT / "build/omxplorer/linux", OUT / "gtk")
    r = subprocess.run([sys.executable, str(ROOT / "scripts/live.py"), str(OUT / "gtk/omxplorer"), NATIVE.format(out=OUT),
                        "--size", f"{SIZE[0]}x{SIZE[1]}", "--env", f"OMX_OPEN={DATA}", "--env", f"OMX_DOCUMENTS={OUT / 'docs'}"],
                       cwd=ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        sys.exit("native: " + (r.stdout + r.stderr)[-800:])
    print(f"native: {OUT / 'sentence-gtk.mp4'}")


def web():
    from playwright.sync_api import sync_playwright
    sys.path.insert(0, str(ROOT / "scripts"))
    from drive import free_port, settle, CHROMIUM
    shutil.rmtree(OUT / "web", ignore_errors=True)
    shutil.copytree(ROOT / "build/omxplorer/web", OUT / "web")
    port = free_port()
    env = dict(os.environ, OMX_OPEN=str(DATA), OMX_DOCUMENTS=str(OUT / "docs"))
    server = subprocess.Popen([sys.executable, str(ROOT / "mojoui/hosts/web.py"), str(OUT / "web"), str(port)], cwd=ROOT, env=env,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    url = f"http://127.0.0.1:{port}/"
    try:
        for _ in range(600):
            try:
                urllib.request.urlopen(url + "static/htmx.min.js", timeout=1)
                break
            except OSError:
                time.sleep(0.1)
        with sync_playwright() as p:
            browser = p.chromium.launch(executable_path=CHROMIUM, headless=True)
            warm = browser.new_page(viewport={"width": SIZE[0], "height": SIZE[1]})  # (the file opens before the recording starts)
            warm.goto(url)
            settle(warm)
            warm.close()
            page = browser.new_page(viewport={"width": WEB[0], "height": WEB[1]})
            page.goto(url)
            settle(page)
            page.get_by_role("button", name="Create table", exact=True).click()
            settle(page)
            page.locator("[data-tag='toolbar'] >> text=Chart").first.click()
            settle(page)
            chart = page.locator(".board > .object[data-tag='chart0']").bounding_box()
            table = page.locator(".board > .object[data-tag='table']").bounding_box()
            page.mouse.move(chart["x"] + chart["width"] - 4, chart["y"] + chart["height"] - 4)  # the chart's corner: as wide as the table
            page.mouse.down()
            page.mouse.move(table["x"] + table["width"] - 4, chart["y"] + chart["height"] - 4, steps=12)
            page.mouse.up()
            settle(page)
            page.mouse.move(900, 300)
            page.wait_for_timeout(800)
            frames = []  # (jpeg bytes, seconds): one each time the page repaints
            cdp = page.context.new_cdp_session(page)

            def frame(f):
                import base64
                frames.append((base64.b64decode(f["data"]), f["metadata"]["timestamp"]))
                cdp.send("Page.screencastFrameAck", {"sessionId": f["sessionId"]})
            cdp.on("Page.screencastFrame", frame)
            cdp.send("Page.startScreencast", {"format": "jpeg", "quality": 90, "maxWidth": WEB[0], "maxHeight": WEB[1]})
            page.wait_for_timeout(1200)
            page.locator("[data-tag='ask']").click()
            page.keyboard.type("by product, largest first, top 5", delay=40)
            page.keyboard.press("Enter")
            settle(page)
            page.wait_for_timeout(1500)
            page.locator("[data-tag='word-0-0']").click()  # the sentence's "Sum": its choices
            settle(page)
            page.wait_for_timeout(1200)
            page.locator(".popover >> text=Average").first.click()
            settle(page)
            page.wait_for_timeout(1500)
            page.locator("[data-tag='word-0-6']").click()  # "bars": a line
            settle(page)
            page.wait_for_timeout(900)
            page.locator(".popover >> text=a line").first.click()
            settle(page)
            page.wait_for_timeout(1800)
            page.screenshot(path=str(OUT / "sentence-web.png"))
            cdp.send("Page.stopScreencast")
            browser.close()
        to_video(frames, OUT / "sentence-web.mp4")
        print(f"web: {OUT / 'sentence-web.mp4'} ({len(frames)} frames)")
    finally:
        server.terminate()


def to_video(frames, path):
    """Screencast frames (sent only on a repaint) into a 30 fps video: each frame lasts until the next one."""
    work = OUT / "frames"
    shutil.rmtree(work, ignore_errors=True)
    work.mkdir()
    lines = []
    for k, (data, at) in enumerate(frames):
        (work / f"{k:05d}.jpg").write_bytes(data)
        lines.append(f"file '{k:05d}.jpg'")
        lines.append(f"duration {max(frames[k + 1][1] - at, 1 / 30) if k + 1 < len(frames) else 1.0:.4f}")
    lines.append(f"file '{len(frames) - 1:05d}.jpg'")  # (the concat demuxer's last frame needs naming twice)
    (work / "list.txt").write_text("\n".join(lines) + "\n")
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "concat", "-safe", "0", "-i", str(work / "list.txt"), "-vf", "fps=30,format=yuv420p",
                    "-c:v", "libx264", "-crf", "20", "-preset", "veryfast", str(path)], check=True)
    shutil.rmtree(work)


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    what = sys.argv[1] if len(sys.argv) > 1 else "all"
    if what in ("native", "all"):
        native()
    if what in ("web", "all"):
        web()
