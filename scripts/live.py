"""Drive a GTK app with real input (XTest) on the private headless display, like a person would.

The MOJOUI_TEST steps call the host's handlers directly; this sends real pointer and key events through X,
so GTK's own gestures, focus and timing run as they do on the desktop.

  pixi run python scripts/live.py <exe> "<commands>" [--size 1742x876] [--env K=V ...]
Commands, separated by ';':
  wait:MS            let the app run for MS milliseconds
  move:X,Y           move the pointer (window coordinates)
  click:X,Y          press and release button 1 there (shift+click:X,Y holds Shift)
  drag:X1,Y1,X2,Y2   press at 1, move in 12 steps over ~200 ms to 2, release
  key:NAME           press and release a key (X keysym names; Shift+Down, Control+c)
  shot:PATH          save the screen (the window's area) as a PNG
The app's stdout (TRACE: lines with MOJOUI_TRACE=1) is printed at the end.
"""
import os
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import headless  # noqa: E402
from Xlib import X, XK, display  # noqa: E402
from Xlib.ext import xtest  # noqa: E402
from PIL import Image  # noqa: E402


def main():
    args = sys.argv[1:]
    exe, commands = args[0], args[1]
    size, extra = "1742x876", {}
    i = 2
    while i < len(args):
        if args[i] == "--size":
            size = args[i + 1]
            i += 2
        elif args[i] == "--env":
            k, v = args[i + 1].split("=", 1)
            extra[k] = v
            i += 2
        else:
            i += 1
    headless.ensure()
    env = dict(os.environ, MOJOUI_WINDOW=size, **extra)
    env.pop("MOJOUI_TEST", None)
    log = open(Path("build") / "live.log", "w")
    app = subprocess.Popen([exe], env=env, stdout=log, stderr=subprocess.STDOUT)
    d = display.Display(os.environ["DISPLAY"])
    w, h = (int(n) for n in size.split("x"))
    time.sleep(2.5)  # the window maps and lays out

    def move(x, y):
        xtest.fake_input(d, X.MotionNotify, x=int(x), y=int(y))
        d.sync()

    def button(down):
        xtest.fake_input(d, X.ButtonPress if down else X.ButtonRelease, 1)
        d.sync()

    def keycode(name):
        return d.keysym_to_keycode(XK.string_to_keysym(name))

    def key(combo):
        parts = combo.split("+")
        mods = [keycode({"Shift": "Shift_L", "Control": "Control_L", "Alt": "Alt_L"}[m]) for m in parts[:-1]]
        for m in mods:
            xtest.fake_input(d, X.KeyPress, m)
        k = keycode(parts[-1])
        xtest.fake_input(d, X.KeyPress, k)
        xtest.fake_input(d, X.KeyRelease, k)
        for m in reversed(mods):
            xtest.fake_input(d, X.KeyRelease, m)
        d.sync()

    for cmd in commands.split(";"):
        if not cmd:
            continue
        verb, _, rest = cmd.partition(":")
        nums = [float(n) for n in rest.split(",")] if verb in ("move", "click", "shift+click", "drag") else []
        if verb == "wait":
            time.sleep(float(rest) / 1000)
        elif verb == "move":
            move(*nums)
        elif verb in ("click", "shift+click"):
            if verb == "shift+click":
                xtest.fake_input(d, X.KeyPress, keycode("Shift_L"))
            move(*nums)
            time.sleep(0.05)
            button(True)
            time.sleep(0.05)
            button(False)
            if verb == "shift+click":
                xtest.fake_input(d, X.KeyRelease, keycode("Shift_L"))
                d.sync()
            time.sleep(0.25)
        elif verb == "drag":
            x1, y1, x2, y2 = nums
            move(x1, y1)
            time.sleep(0.05)
            button(True)
            for s in range(1, 13):
                move(x1 + (x2 - x1) * s / 12, y1 + (y2 - y1) * s / 12)
                time.sleep(0.016)
            time.sleep(0.05)
            button(False)
            time.sleep(0.25)
        elif verb == "key":
            key(rest)
            time.sleep(0.2)
        elif verb == "shot":
            raw = d.screen().root.get_image(0, 0, w, h, X.ZPixmap, 0xFFFFFFFF)
            Image.frombytes("RGB", (w, h), raw.data, "raw", "BGRX").save(rest)
        else:
            print("live: unknown command " + cmd)
    app.terminate()
    try:
        app.wait(timeout=5)
    except subprocess.TimeoutExpired:
        app.kill()
    log.close()
    print(open(Path("build") / "live.log").read())


if __name__ == "__main__":
    main()
