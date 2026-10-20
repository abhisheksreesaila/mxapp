"""Runs one command on the headless display (scripts/headless.py), so a GTK app never opens on the desktop.
  pixi run python scripts/hl.py env MOJOUI_TEST= MOJOUI_SHOT=build/x.png build/hello/linux/hello"""
import subprocess
import sys

import headless

headless.ensure()
sys.exit(subprocess.run(sys.argv[1:]).returncode)
