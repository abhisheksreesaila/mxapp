"""Drive a mojoui web app in headless Chromium with the same steps as the GTK test mode.

  pixi run python scripts/drive.py build/gallery/web "type:Your name=Ada;toggle:Notifications"

Starts mojoui/hosts/web.py on a free port, performs each step on the real page
(clicks, typing, Return, ticking, choosing, sliding), then prints every control's
state as the browser reports it (LABEL/BUTTON/FIELD/TOGGLE/DROPDOWN/SLIDER/PROGRESS).
"""

import re
import socket
import subprocess
import sys
import time
import urllib.request
from pathlib import Path
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parent.parent
CHROMIUM = "/usr/bin/chromium"

DUMP = """() => [...document.querySelectorAll('#mojoui-root [data-kind]')].map(e => {
  const k = e.dataset.kind;
  if (k === 'label') return 'LABEL: ' + e.textContent;
  if (k === 'button') return 'BUTTON: ' + e.textContent;
  if (k === 'field') return 'FIELD: ' + e.value;
  if (k === 'toggle') return 'TOGGLE: ' + e.querySelector('span').textContent + (e.querySelector('input').checked ? '=on' : '=off');
  if (k === 'dropdown') return 'DROPDOWN: ' + e.options[e.selectedIndex].text;
  if (k === 'slider') return 'SLIDER: ' + e.value;
  if (k === 'progress') return 'PROGRESS: ' + e.value;
}).filter(Boolean).join('\\n')"""


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


def exact(text):
    return re.compile("^" + re.escape(text) + "$")


def settle(page):
    """Wait for HTMX's delayed triggers to fire and its requests to finish."""
    page.wait_for_timeout(250)
    page.wait_for_function("() => !document.querySelector('.htmx-request')", timeout=10000)
    page.wait_for_timeout(50)


def step(page, s):
    verb, _, rest = s.partition(":")
    if verb == "tap":
        title, _, nth = rest.partition("@")
        page.locator("[data-kind=button]").filter(has_text=exact(title)).nth(int(nth or 0)).click()
    elif verb in ("type", "submit"):
        hint, _, text = rest.partition("=")
        field = page.locator(f"input[data-kind=field][placeholder={hint!r}]").first
        if verb == "type":
            field.fill(text)
        else:
            field.press("Enter")
    elif verb == "toggle":
        page.locator("[data-kind=toggle]").filter(has=page.locator("span", has_text=exact(rest))).first.locator("input").click()
    elif verb == "select":
        k, _, option = rest.partition("=")
        page.locator("select[data-kind=dropdown]").nth(int(k)).select_option(label=option)
    elif verb == "slide":
        k, _, value = rest.partition("=")
        page.locator("input[data-kind=slider]").nth(int(k)).fill(value)
    else:
        raise ValueError(f"unknown step {s}")
    settle(page)


def web_run(module_dir, steps, shot=None):
    """Returns (result, output) like a process run: result.returncode is 0 on success."""
    from playwright.sync_api import sync_playwright

    port = free_port()
    server = subprocess.Popen([sys.executable, str(ROOT / "mojoui/hosts/web.py"), str(module_dir), str(port)],
                              cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    url = f"http://127.0.0.1:{port}/"
    try:
        for _ in range(100):
            try:
                urllib.request.urlopen(url, timeout=1)
                break
            except OSError:
                if server.poll() is not None:
                    return SimpleNamespace(returncode=1), "server died:\n" + server.stdout.read()
                time.sleep(0.1)
        with sync_playwright() as p:
            browser = p.chromium.launch(executable_path=CHROMIUM, headless=True)
            page = browser.new_page(viewport={"width": 900, "height": 900})
            errors = []
            page.on("pageerror", lambda e: errors.append(str(e)))
            page.goto(url)
            settle(page)
            for s in [s for s in steps.split(";") if s]:
                step(page, s)
            out = "NATIVE: Chromium " + browser.version + "\n" + page.evaluate(DUMP) + "\n"
            if shot:
                page.screenshot(path=shot, full_page=True)
                out += f"SHOT: {shot}\n"
            if errors:
                out += "PAGE ERRORS: " + "; ".join(errors) + "\n"
            browser.close()
        return SimpleNamespace(returncode=1 if errors else 0), out
    finally:
        server.terminate()
        server.wait(timeout=10)


if __name__ == "__main__":
    shot = sys.argv[3] if len(sys.argv) > 3 else None
    r, out = web_run(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else "", shot=shot)
    print(out, end="")
    sys.exit(r.returncode)
