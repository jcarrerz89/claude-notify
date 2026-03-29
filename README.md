# claude-notify

Cross-platform notification system for Claude Code. When Claude needs your attention, you get an OS notification and a live desktop dashboard — with a one-click button to jump back to the right editor window.

---

## How it works

```
Claude Code session
       │
       │ Notification event
       ▼
 hooks/notify.sh
       │
       ├──► OS notification center  (macOS / Linux / Windows)
       │
       └──► POST /notify → dashboard app on localhost:9717
                               │
                               ▼
                      dashboard/ (Tauri app)
                      Shows message, project, client badge
                      "Open VS Code" button → focuses your editor
```

The hook and the dashboard are independent — the dashboard is optional. If it isn't running, the hook fires the OS notification and exits cleanly.

---

## Repository structure

```
claude-notify/
├── hooks/
│   └── notify.sh          Cross-platform notification hook
├── dashboard/             Tauri desktop app (macOS/Linux/Windows)
│   ├── src/
│   │   └── index.html     Frontend UI (vanilla HTML/CSS/JS)
│   └── src-tauri/
│       ├── src/
│       │   ├── lib.rs     HTTP server (axum) + Tauri commands
│       │   └── main.rs    Entry point
│       ├── Cargo.toml     Rust dependencies
│       └── tauri.conf.json
├── lib/
│   ├── colors.sh          ANSI colors + log_* helpers
│   └── notepad.sh         Cross-worktree notes (discoveries/blockers/conventions)
├── worktree               Git worktree manager for parallel feature development
├── install.sh             Installs the hook into any Claude Code project
└── .gitignore
```

---

## Quick start

### 1. Install the notification hook into your project

```bash
git clone https://github.com/jcarrerz89/claude-notify.git
cd claude-notify
./install.sh /path/to/your/project
```

This copies `hooks/notify.sh` into `<project>/.claude/hooks/` and wires the `Notification` event in `.claude/settings.json`.

Or install into the current directory:

```bash
cd /path/to/your/project
/path/to/claude-notify/install.sh
```

### 2. (Optional) Run the dashboard

```bash
cd dashboard
cargo tauri dev       # development
cargo tauri build     # production .app bundle
```

The dashboard listens on `http://localhost:9717`. Open it before starting a Claude Code session and it will receive notifications automatically.

---

## Notification hook (`hooks/notify.sh`)

Triggered by Claude Code's `Notification` event. Receives a JSON payload via stdin:

```json
{ "title": "...", "message": "...", "notification_type": "..." }
```

**What it does:**

1. Derives the project name from `$CLAUDE_PROJECT_DIR` (e.g. `nogal` → `Nogal`)
2. Detects the client environment (VS Code, Cursor, iTerm2, Terminal)
3. Fires an OS notification with sound
4. POSTs to the dashboard (fire-and-forget, 1s timeout — won't block if dashboard is down)

**OS support:**

| Platform | Method |
|---|---|
| macOS | `osascript` with Ping sound |
| Linux | `notify-send` (fallback: `zenity`) |
| Windows | PowerShell `MessageBox` |

**Environment variables:**

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_NOTIFY_PORT` | `9717` | Dashboard port |
| `CLAUDE_PROJECT_DIR` | `$(pwd)` | Set automatically by Claude Code |

---

## Dashboard app (`dashboard/`)

A Tauri 2 desktop app built with Rust (axum) + vanilla HTML/CSS/JS.

**Features:**
- Real-time notification feed (kept in memory, max 200)
- Unread badge count
- Client badges: VS Code, Cursor, Windsurf, Terminal
- Project path display
- "Open [client]" button — focuses the originating editor window via `osascript` or CLI
- Mark all read / Clear all
- Pulsing status indicator while listening

**Stack:**

| Layer | Technology |
|---|---|
| Desktop shell | Tauri 2 |
| HTTP server | axum 0.8 on `127.0.0.1:9717` |
| Frontend | Vanilla HTML/CSS/JS |
| Serialization | serde + serde_json |
| Timestamps | chrono |
| CORS | tower-http |

**API:**

| Method | Path | Description |
|---|---|---|
| `GET` | `/` | Health check → `devkit-dashboard ok` |
| `POST` | `/notify` | Receive a notification (called by the hook) |

**Notification payload schema:**

```json
{
  "title": "MyProject",
  "message": "Claude needs your input...",
  "source": "hook",
  "client": "vscode",
  "client_app": "Visual Studio Code",
  "client_path": "/Users/you/projects/myproject"
}
```

**Build requirements:** Rust toolchain + Tauri CLI (`cargo install tauri-cli`)

---

## Working on multiple features (`worktree`)

The `worktree` script manages git worktrees so you can develop multiple features in parallel, each in its own directory with its own Claude Code session.

```bash
# Start a new feature branch + worktree
./worktree new feature/dashboard-v2

# List active worktrees
./worktree list

# Re-sync .claude/ config into all worktrees (after settings changes)
./worktree sync

# Clean up when the feature is merged
./worktree remove feature/dashboard-v2
```

Worktrees are created at `../claude-notify-worktrees/<branch>/`. Each one gets `.claude/settings.json` copied and `commands/` symlinked so Claude Code works correctly inside it.

---

## Shared notes across worktrees (`lib/notepad.sh`)

When working across multiple worktrees, use the notepad to share live discoveries, blockers, and conventions between Claude sessions.

```bash
source lib/notepad.sh
export PROJECT_DIR="$(pwd)"

notepad_init "dashboard-v2"
notepad_append "dashboard-v2" "discoveries" "axum CORS must stay permissive — hook sends from shell, no Origin header"
notepad_append "dashboard-v2" "blockers"    "Tauri window focus fails on macOS Sonoma when app is in background > 5min"
notepad_read   "dashboard-v2"               # inject into a Claude prompt
```

Notes are stored in `.devkit/notepad/` (gitignored) and scoped per feature name.

---

## Development

**Requirements:**

- bash, jq, curl
- Rust toolchain (for dashboard only)
- Tauri CLI: `cargo install tauri-cli` (for dashboard only)

**Running tests / linting the hook:**

```bash
bash -n hooks/notify.sh   # syntax check
shellcheck hooks/notify.sh
```

**Developing the dashboard:**

```bash
cd dashboard
cargo tauri dev
```

Changes to `src/index.html` hot-reload. Changes to `src-tauri/src/` require a Rust recompile.
