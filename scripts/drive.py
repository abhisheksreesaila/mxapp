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

DUMP = """() => [...document.querySelectorAll('#mojoui-root [data-kind], #mojoui-overlay [data-kind]')].map(e => {
  const k = e.dataset.kind;
  if (k === 'label') return 'LABEL: ' + e.textContent;
  if (k === 'button') return 'BUTTON: ' + e.textContent;
  if (k === 'field') return 'FIELD: ' + e.value;
  if (k === 'toggle') return 'TOGGLE: ' + e.querySelector('span').textContent + (e.querySelector('input').checked ? '=on' : '=off');
  if (k === 'dropdown') return 'DROPDOWN: ' + e.options[e.selectedIndex].text;
  if (k === 'slider') return 'SLIDER: ' + e.value;
  if (k === 'progress') return 'PROGRESS: ' + e.value;
  if (k === 'image') return 'IMAGE: ' + e.naturalWidth + 'x' + e.naturalHeight;
  const picked = () => { const i = e.querySelector('input:checked'); return i ? i.nextElementSibling.textContent : ''; };
  if (k === 'segmented') return 'SEGMENTED: ' + picked();
  if (k === 'tabs') return 'TABS: ' + picked();
  if (k === 'radio') return 'RADIO: ' + picked();
  if (k === 'textarea') return 'TEXTAREA: ' + e.value.split(String.fromCharCode(10)).join(String.fromCharCode(92) + 'n');
  if (k === 'alert') return 'ALERT: ' + e.querySelector('h3').textContent + ' | ' + e.querySelector('p').textContent + ' | '
    + [...e.querySelectorAll('button')].map(b => b.textContent).join(', ');
  if (k === 'nav') return 'NAV: ' + e.querySelector('h2').textContent + (e.dataset.back === '1' ? ' (back)' : '');
  if (k === 'date') return 'DATE: ' + e.value;
  if (k === 'icon') return 'ICON: ' + (e.querySelector('svg') ? e.dataset.icon : '?');
  if (k === 'grid') return 'GRID: ' + e.dataset.columns + ' columns, ' + e.children.length + ' items';
  if (k === 'list') { const r0 = e.querySelector('[data-row="0"]');
    return 'LIST: ' + e.querySelector('.rows').dataset.count + ' rows' + String.fromCharCode(10) + 'LISTROWS: ' + e.querySelectorAll('.row').length
      + (r0 ? String.fromCharCode(10) + 'LISTROW: ' + r0.textContent : ''); }
}).filter(Boolean).concat([...document.querySelectorAll('[data-tag]')].map(e => {
  const r = e.getBoundingClientRect();
  return 'BOX: ' + e.dataset.tag + ' ' + [r.x, r.y, r.width, r.height].map(v => v.toFixed(1)).join(' ');
})).join(String.fromCharCode(10))"""


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
    page.wait_for_function("() => [...document.images].every(i => i.complete)", timeout=10000)
    page.wait_for_timeout(50)


def step(page, s):
    verb, _, rest = s.partition(":")
    if verb == "tap":
        title, _, nth = rest.partition("@")
        page.locator("[data-kind=button]").filter(has_text=exact(title)).nth(int(nth or 0)).click()
    elif verb in ("type", "submit", "enter"):
        hint, _, text = rest.partition("=")
        field = page.locator(f"input[data-kind=field][placeholder={hint!r}]").first
        if verb in ("type", "enter"):
            field.fill(text)
        if verb in ("submit", "enter"):
            field.press("Enter")  # for "enter": straight after typing, no wait
    elif verb == "toggle":
        page.locator("[data-kind=toggle]").filter(has=page.locator("span", has_text=exact(rest))).first.locator("input").click()
    elif verb == "select":
        k, _, option = rest.partition("=")
        page.locator("select[data-kind=dropdown]").nth(int(k)).select_option(label=option)
    elif verb in ("segment", "tab", "radio"):
        k, _, option = rest.partition("=")
        kind = {"segment": "segmented", "tab": "tabs", "radio": "radio"}[verb]
        group = page.locator(f"[data-kind={kind}]").nth(int(k))
        group.locator("label").filter(has=page.locator("span", has_text=exact(option))).first.click()
    elif verb == "textarea":
        k, _, text = rest.partition("=")
        page.locator("textarea[data-kind=textarea]").nth(int(k)).fill(text.replace("\\n", "\n"))
    elif verb == "alert":
        if rest == "Escape":
            page.keyboard.press("Escape")  # the dialog's own cancel
        else:
            page.locator("dialog[data-kind=alert] button").filter(has_text=exact(rest)).first.click()
    elif verb == "back":
        page.locator("[data-kind=navback]").first.click()
    elif verb == "date":
        k, _, value = rest.partition("=")
        page.locator("input[data-kind=date]").nth(int(k)).fill(value)
    elif verb == "scroll":
        k, _, row = rest.partition("=")
        page.locator("[data-kind=list]").nth(int(k)).evaluate(
            "(e, row) => { e.scrollTop = row * Number(e.dataset.rowHeight); e.dispatchEvent(new Event('scroll')); }",
            int(row))
    elif verb == "row":
        k, _, row = rest.partition("=")
        page.locator("[data-kind=list]").nth(int(k)).locator(f'[data-row="{int(row)}"]').click()
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
