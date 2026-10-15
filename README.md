# mojo-ui

Write an app once in Mojo; run it natively on Linux, Mac, iPhone and the web.
A long-term, experimental side project, built slowly, one verified step at a time.

**Start here:** `CLAUDE.md` (briefing for Claude Code), then `ROADMAP.md`, `SPEC.md`, `EXPERIMENTS.md`.

## Try what works today (Linux)
```bash
pip install mojo          # Mojo 1.1
./scripts/m0_linux.sh     # Mojo <-> C both ways, static build with no Mojo runtime, iPhone object check
```

## Next steps
- **Main track:** M1, the "Hello, Name" core with tests (SPEC §5, §9).
- **iPhone track:** `ios-xtool/README.md`: build the SwiftUI + Mojo app from Linux with xtool and run it on your iPhone.

## Visuals
Open `docs/visual-guide.html` in a browser for the architecture diagrams.
