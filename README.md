# claude-notify

Cross-platform notification hook for Claude Code sessions. Sends notifications to your OS notification center and an optional desktop dashboard app when Claude needs your attention.

## Features

- **OS notifications** with sound (macOS, Linux, Windows)
- **Desktop dashboard** integration via HTTP POST to `localhost:9717`
- **Client detection** — identifies VS Code, Cursor, iTerm2, Terminal
- **Project-aware** — uses the project directory name as notification title
- **Zero dependencies** beyond `jq` and `curl` (both standard on most systems)

## Install

```bash
# From the claude-notify repo, install into your project:
./install.sh /path/to/your/project

# Or install into the current directory:
cd /path/to/your/project
/path/to/claude-notify/install.sh
```

This copies `notify.sh` into `.claude/hooks/` and adds the `Notification` hook entry to `.claude/settings.json`.

## Configuration

| Environment variable | Default | Description |
|---|---|---|
| `CLAUDE_NOTIFY_PORT` | `9717` | Port for the desktop dashboard app |

## How it works

When Claude Code triggers a `Notification` event (e.g., asking a question), this hook:

1. Parses the JSON payload from stdin (`title`, `message`, `notification_type`)
2. Sends an OS notification with sound
3. POSTs to the desktop dashboard app (fire-and-forget — won't block if the app isn't running)

The notification title defaults to the project directory name (e.g., "Nogal"), and the message contains the actual prompt from Claude.
