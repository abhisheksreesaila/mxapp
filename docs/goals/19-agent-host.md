# GOAL 19: the agent host: every omxapp app as MCP tools, read from the tree (the kit and omxplorer, driven by an agent)

**End goal (owner's words, 2026-10-17):** "what about agentic world. how do we make this agent native?" → the agent is a fifth host, "yah I agree, please proceed". An MCP server over any app's web module turns the current screen into tools (the tag names the tool, the tooltip describes it, the message is the call), lets the agent act, read what's on screen (a canvas's content as text where the app offers it) and look (a canvas as a PNG). Proven on the kit and omxplorer by a client in the checker; Claude Code is pointed at it with one command. No LLM runs in the checks.

## Milestones
| # | Milestone | Proof (`scripts/check`) |
|---|---|---|
| M1 | The agent host drives the kit | `mojoui/hosts/agent.py build/kit/web` speaks MCP over stdio (initialize, tools/list, tools/call, ping, tools/list_changed). `tools/list` has `screen`, `act`, `read`, `render` and one tool per actionable node (menu items as `file-save`, tagged views by tag, others by a slug of their text; tooltips are descriptions; disabled items are absent). The checker's client: `file-save` → the status reads "Saved kit.omx"; `open-dialog` → a Dialog "Settings" is on screen and its radios and checkboxes are tools; `graphite` → `screen` says the design is Graphite; `render` of the canvas returns a PNG of the asked size; `act` with a `secondary` gesture on the canvas → the context menu's items are tools; `sort-z-a` → "Sorted Z→A"; GTK run with the same steps prints the same status lines |
| M2 | omxplorer by an agent | the sample opens from the Start screen's tool; `data-sort-largest-first` sorts; `read` of the grid returns its visible rows as text (a new `App.describe(canvas, first, count)` with a default, so no other app changes) and the first row's revenue is the largest; `render` of the grid is a PNG; the status bar's Sum/Average/Count are in `screen` |
| M3 | A fifth host | `docs/components.md` has an "Agent (MCP)" column with every kind the host reads; `scripts/agent.sh <app>` prints the one Claude Code command; `docs/agent.md` says what the tools are and what an agent can't do (nothing a person couldn't) |
| M4 | Nothing regressed | goal 18's checks (every earlier goal's inside them) still pass; the matrix is current |

## Done means
`scripts/check` prints PASS for M1–M4; push to `origin` after. `docs/report.md` is short and says what an agent can and can't do today.

## Out of bounds
Calling an LLM anywhere in the checks (the client is a script); running Claude Code non-interactively; AG-UI and generative UI (after MX frame: the operations log is their state); reading a grid's cells on apps other than omxplorer; no deploying, no paid services, no secrets, nothing outside this repo; `../mojo-ui-apple-test` stays untouched.

## Assumptions
- D-160: the agent is a host. The MCP server reads the same `mojoui_app` module the web host serves, so an app changes nothing to become agent-driveable.
- D-161: MCP is hand-written JSON-RPC over stdio in `agent.py` (no SDK dependency: the protocol is small, the checker's client proves it).
- D-162: tool names come from the tree: the tag, else a slug of the text; a menu item is `<menu>-<item>`; duplicates get `-2`, `-3`.
- D-163: `App.describe(canvas, first, count) -> String` (default "") is how an app offers a canvas's content to an agent; omxplorer returns the grid's shown rows as tab-separated text.
- D-164: the tool list changes with the screen: after every call the server sends `notifications/tools/list_changed`.
- Budget: the evening (about 80 turns).
