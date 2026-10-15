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
CHECK_OUTPUT
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
3. **Lazy lists ask the app for row text (`App.row`).** It's simple and fast: GTK built 205 row widgets for 10,000 rows. The limit for now: rows are text plus one tap, with no buttons inside rows.

**Next:** your Apple results. Then a bottom tab bar and real push navigation on iPhone, and controls inside list rows.
