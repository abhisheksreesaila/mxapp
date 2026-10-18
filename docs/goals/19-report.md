# Goal 19 report: the agent host: every omxapp app as MCP tools

**End goal:** the agent is a fifth host. Without changing an app, an agent sees its screen as tools (the tag names the tool, the tooltip describes it, the message is the call), acts, reads, and looks.

## How far it got
`scripts/check` (`build/check-goal19.log`):

| # | Milestone | Result |
|---|---|---|
| M1 | The agent host drives the kit: tools from the tree, the dialog's tools while it is open, the design, a PNG of the canvas, the context menu after a right click, the sort; GTK and the web show the same status after the same steps | PASS |
| M2 | omxplorer by an agent: the sample, Data > Sort largest first, the grid's rows as text (`App.describe`), a picture of the grid | PASS |
| M3 | A fifth host: the Agent column in `docs/components.md`, `scripts/agent.sh`, `docs/agent.md` | PASS |
| M4 | Goal 18's checks (goals 3–17 inside them) and the matrix | PASS |

## 30-second demo
```
scripts/agent.sh omxplorer                                  # prints the one `claude mcp add …` command
pixi run python scripts/agent_client.py build/omxplorer/web screen
pixi run python scripts/agent_client.py build/omxplorer/web open-the-sample
pixi run python scripts/agent_client.py build/omxplorer/web data-sort-largest-first
pixi run python scripts/agent_client.py build/omxplorer/web read name=grid count=5
```
In Claude Code after `claude mcp add`: "open the sample in omxplorer, sort by revenue largest first, and tell me the top order" works with the tools alone: no screenshots, no accessibility scraping.

## What an agent can and can't do today
- Can: everything a person can click, type, tick, pick or press on any omxapp app, by name; read every text on screen; read omxplorer's grid rows; see any canvas as a PNG. A wrong name comes back as an error that lists the right ones.
- Can't: read cells on apps that don't `describe` their canvases; drag Board objects; generate UI (AG-UI, after MX frame).
- No LLM ran in the checks: `scripts/agent_client.py` is a plain MCP client.

## Three decisions worth a second look
- **D-160** the agent is a host over the web module: nothing per app. The cost: an app must build for the web to be agent-driveable (every example does).
- **D-162** tool names from tags, text and menu paths, dialog content prefixed by its title: stable names an agent can plan with. Untagged duplicates still get `-2` (the Start screen's two "Open" buttons).
- **D-164** the tool list follows the screen, `list_changed` after every call: an agent can only do what a person could do right now.

## What's next
Point Claude Code at omxplorer and watch a real agent use it; tag the untagged buttons it stumbles on. Then AG-UI once MX frame lands: the operations log as the shared state, generative cards from kit components.
