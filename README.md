# Todoist for Omarchy

**What's due and what needs doing, in the Omarchy bar.** Tasks in one popup — add, edit and complete without leaving the desktop.

The bar shows a count of tasks due and turns urgent when something is overdue. Left click opens the panel.

## Features

- Tasks due today, tomorrow, or the next seven days, overdue ones first
- Edit a task in place — `e` fills the add field with the task's own line
- Completing a task is a click on its circle — the row itself is not a hit target
- Quick-add field — type a title, hit enter, it lands due today
- **Undo window** — a completion is held for a few seconds before it is sent
- Fully keyboard driven, with an in-panel shortcut list
- Label colours come from Todoist; due state follows your Omarchy theme
- Offline writes are queued and replayed on the next successful sync

## Requirements

| Dependency | Required | Why |
|---|---|---|
| Omarchy 4 (Quattro) with Quickshell | yes | the shell that hosts the plugin |
| `python3` | yes | the CLI; standard library only, no pip packages |
| A Todoist account | yes | free accounts work |

No external Python packages, no build step, nothing compiled.

## Install

```bash
omarchy plugin add https://github.com/mdetweil/omarchy-todoist.git --enable
```

Then click the widget in the bar. It shows a plug icon until connected, and clicking it opens a setup card:

1. Open `todoist.com/app/settings/integrations`
2. Find **API token** and copy it
3. Paste it into the field and press Connect

The token is stored in `~/.local/state/omarchy/todoist/session.json` at mode 0600. Nothing else touches it.

If you prefer the terminal:

```bash
~/.config/omarchy/plugins/io.github.mdetweil.todoist/bin/omarchy-todoist login --token -
```

`--token -` prompts with input hidden, keeping the credential out of shell history.

## Removal

```bash
omarchy plugin remove io.github.mdetweil.todoist
```

To also remove the cached data and token:

```bash
omarchy-todoist logout
rm -rf ~/.local/state/omarchy/todoist
```

## CLI

```bash
omarchy-todoist login [--token T]           # store API token
omarchy-todoist sync [--scope tasks|full]   # refresh the cache
omarchy-todoist add "Pay rent" --due today [--priority 0|1|3|5] [--tags work,ops]
omarchy-todoist update <taskId> [--title T] [--due D] [--priority P] [--tags a,b]
omarchy-todoist complete <taskId>
omarchy-todoist reopen <taskId>
omarchy-todoist delete <taskId>
omarchy-todoist status                      # cache state as JSON
omarchy-todoist logout
```

Every command prints JSON on stdout and errors on stderr.

## Quick add syntax

```
Renew the TLS cert #work !1 tomorrow
```

| Syntax | Does |
|---|---|
| `#label` | attaches a Todoist label |
| `!1` `!2` `!3` | priority: high, medium, low |
| `!high` `!med` `!low` | same, spelled out |
| trailing `today` / `tomorrow` / `YYYY-MM-DD` | sets the due date |

Press `e` on the selected task to fill the field with the line that would have created it. Edit and press enter to save; escape cancels.

## Settings

| Key | Default | What it does |
|---|---|---|
| `syncInterval` | `5 minutes` | `2 minutes`, `5 minutes`, `15 minutes`, `1 hour`, or `Only when opened` |
| `horizon` | `Today` | `Today`, `Tomorrow`, or `Next 7 days` |
| `includeOverdue` | `true` | Count and list work that is already late |
| `showTasks` | `true` | Show the task section |
| `maxTasks` | `12` | Rows before the list is capped with "+N more" |
| `barLabel` | `Count` | `Count`, `Next` (next task's title), or `Icon`. Right-click to cycle. |
| `undoSeconds` | `6` | How long a completion is held before sending. `0` disables undo. |

## Keys and clicks

| Where | Input | Action |
|---|---|---|
| Bar | left | open the panel |
| Bar | middle | sync now |
| Bar | right | cycle the label: counts → next task → icon only |
| Panel | click circle | complete the task |
| Panel | click title | cycle the range (Today → Tomorrow → 7 days) |
| Panel | `Open in Todoist ›` | open the web app and close the panel |
| Panel | `↑` `↓` | move between tasks |
| Panel | `enter` | complete the selected task |
| Panel | `u` | undo the held action |
| Panel | `a` | focus the quick-add field |
| Panel | `e` | edit the selected task |
| Panel | `r` | sync now |
| Panel | `g` / `G` | first / last row |
| Panel | `v` / `V` | cycle the range forward / back |
| Panel | `?` | show or hide the shortcut list |
| Panel | `esc` | back out one layer, then close |

IPC, for keybindings:

```bash
omarchy-shell io.github.mdetweil.todoist toggle
omarchy-shell io.github.mdetweil.todoist sync
omarchy-shell io.github.mdetweil.todoist cycleLabel
```

## Tests

```bash
node --test tests/model.test.js
```

`Model.js` holds all logic that can be wrong without being visibly wrong — timezone handling, overdue sorting, due filtering — and runs under Node with no QML required.

## About the API

This plugin uses [Todoist REST API v1](https://developer.todoist.com/api/v1/), authenticated with a personal API token passed as a Bearer header. No private or undocumented endpoints are used.

## Licence

MIT — see [LICENSE](LICENSE).

Unofficial and unaffiliated: not endorsed by or supported by Doist.
