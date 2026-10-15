# Report: the components real apps need, and Pocket Expenses (goal 4)

**End goal (your words):** "continue with 2–4, 8, then … until 9 … and build a fancier app for all platforms, while I test on Apple."

**How far it got:** all 11 milestones pass. Nine new components now work on every host:
- Segmented and Radio
- TextArea
- Alert
- Tabs and NavBar (navigation)
- DatePicker
- Icon
- Grid
- LazyList: a long list that only builds the rows on screen

**Pocket Expenses** (`examples/expenses/app.mojo`) uses all of them. It runs on Linux and the web, where the checker drives it on both and requires identical results, and builds and signs for Mac and iPhone.

```
$ scripts/check
PASS  M1  Segmented + Radio: chosen on GTK and web, echoed, identical
PASS  M2  TextArea: two lines typed and echoed on GTK and web, identical
PASS  M3  Alert shown on screen while in the view; Cancel, Delete and Escape answered on GTK and web, identical
PASS  M4  Tabs switch sections; NavBar opens a screen and Back returns, on GTK and web, identical
PASS  M5  DatePicker set on GTK and web; event carried 2026-12-25; identical
PASS  M6  Icons: star, trash, gear shown with each platform's own icons
PASS  M7  Grid: 6 items in rows of 3 on GTK and web
PASS  M8  10,000-row list: scrolled to and tapped row 7500 on GTK and web; GTK made 410 row widgets in all (rows near the screen, re-made on each refresh), the web page held 30 rows
PASS  M9  Expenses app: add → history → detail → confirm delete → insights; GTK and web identical; Mac + iPhone build
PASS  M10  goal 3's M1–M8 still pass; kitchen builds for Mac + iPhone
PASS  M11  README covers every component and the expenses app; all paths exist
```

Screenshots: `docs/img/expenses-{Add,History,Insights}-{linux,web}.png`, `docs/img/kitchen-web.png`.

## Try it
```bash
scripts/build.sh expenses linux && build/expenses/linux/expenses
scripts/build.sh expenses web && pixi run python mojoui/hosts/web.py build/expenses/web     # http://127.0.0.1:5001
scripts/build.sh expenses mac          # then copy build/expenses/mac/ExpensesMojo-mac.zip to your Mac
apple/install_iphone.sh expenses       # iPhone
```
Your Apple test copy of last night's build is untouched in `../mojo-ui-apple-test`.

## 3 decisions worth your second look
1. **Navigation and modals stay declarative (GOAL assumptions).** An `Alert` shows while it's in `view()`. The current tab or screen is app state, and `NavBar` is just a title bar with Back. The pro: one simple model on every platform. The con: no native push/pop animation and no swipe-back on iPhone yet, and tabs are a segmented switcher at the top, not a bottom tab bar.
2. **D-42, htmx attribute inheritance is switched off for the web host.** It caused two silent bugs in two days, so the rule is now built in and can't recur.
3. **Lazy lists ask the app for row text (`App.row`).** It's simple, and only rows on screen exist: the web page holds 30 of 10,000. Hosts ask for the visible rows again after every update, so edits show; that refresh is proven on both. The limit for now: rows are text plus one tap, with no buttons inside rows. On GTK a refresh replaces only the ~200 rows near the screen, whatever the list's length.

**Next:** your Apple results. Then a bottom tab bar and real push navigation on iPhone, and controls inside list rows.

## Found and fixed along the way (two review rounds)
- **Escape on a GTK alert** left the app stuck. Escape now answers like Cancel on every host.
- **The web alert** blocked clicks but not the keyboard. It now sits above an inert page.
- **Web radio groups** shared one name, so picking a size unticked the tab.
- **Web list rows** inherited the wrong htmx target and silently did nothing. htmx inheritance is now off.
- **GTK row refresh** was a no-op. The reviewer proved it with a probe; it now replaces only the rows GTK has drawn, with a check on both hosts.
- **Amount parsing** could overflow and accepted commas anywhere. It now has unit tests.
