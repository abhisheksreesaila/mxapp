"""Runs a .wasm built from Mojo in headless Chromium: instantiates it, calls its exported function
and prints what came back.   pixi run python scripts/wasm_run.py build/wasm/hello.wasm [function] [args…]"""
import base64
import sys
from pathlib import Path

from playwright.sync_api import sync_playwright

CHROMIUM = "/usr/bin/chromium"

wasm = Path(sys.argv[1]).read_bytes()
fn = sys.argv[2] if len(sys.argv) > 2 else "mojo_add"
args = [int(a) for a in sys.argv[3:]] or [2, 3]
page_html = f"""<!doctype html><script>
window.result = (async () => {{
  const bytes = Uint8Array.from(atob("{base64.b64encode(wasm).decode()}"), c => c.charCodeAt(0));
  window.printed = "";
  let memory = null;
  const imports = {{ env: {{
    mojo_write: (fd, ptr, len) => {{ window.printed += new TextDecoder().decode(new Uint8Array(memory.buffer, Number(ptr), Number(len))); }},
  }} }};
  const {{ instance }} = await WebAssembly.instantiate(bytes, imports);
  memory = instance.exports.memory;
  const names = Object.keys(instance.exports);
  const f = instance.exports[{fn!r}];
  if (!f) throw new Error('no export {fn}; exports: ' + names.join(','));
  const value = f(...{args!r});
  return {{ value: Number(value), exports: names.length, printed: window.printed }};
}})();
</script>"""
with sync_playwright() as p:
    browser = p.chromium.launch(executable_path=CHROMIUM, headless=True)
    page = browser.new_page()
    page.set_content(page_html)
    try:
        r = page.evaluate("window.result")
        print(f"WASM: hello {fn}({', '.join(map(str, args))}) = {r['value']} in Chromium {browser.version}, {r['exports']} exports, {len(wasm)} bytes"
              + (f"; printed: {r['printed'].strip()!r}" if r["printed"] else ""))
    except Exception as e:
        print("WASM FAILED:", str(e)[:400])
        sys.exit(1)
    finally:
        browser.close()
