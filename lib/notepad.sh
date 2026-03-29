#!/bin/bash
# =============================================================================
# notepad.sh — Cross-feature wisdom accumulation
# =============================================================================
#
# During multi-worktree development, record live discoveries, blockers, and
# conventions so Claude sessions across worktrees share context.
#
# Categories:
#   discoveries — non-obvious findings about the codebase
#   blockers    — issues blocking progress that other worktrees should know about
#   conventions — patterns/conventions found that all sessions should follow
#
# Usage:
#   source lib/notepad.sh
#   notepad_init "my-feature"
#   notepad_append "my-feature" "discoveries" "axum CORS must be permissive for notify hook"
#   notepad_read "my-feature"   # formatted content for prompt injection
#
# =============================================================================

: "${PROJECT_DIR:?PROJECT_DIR not set — source notepad.sh from the repo root}"

NOTEPAD_BASE_DIR="$PROJECT_DIR/.devkit/notepad"

notepad_init() {
  local feature="$1"
  [ -z "$feature" ] && { log_error "notepad_init: feature name required"; return 1; }

  feature=$(echo "$feature" | tr ' /' '--')
  local dir="$NOTEPAD_BASE_DIR/$feature"
  mkdir -p "$dir"

  for category in discoveries blockers conventions; do
    local file="$dir/${category}.md"
    if [ ! -f "$file" ]; then
      echo "# $(echo "$category" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')" > "$file"
      echo "" >> "$file"
    fi
  done
}

notepad_append() {
  local feature="$1"
  local category="$2"
  local entry="$3"

  [ -z "$feature" ] || [ -z "$category" ] || [ -z "$entry" ] && {
    log_error "notepad_append: requires feature, category, entry"
    return 1
  }

  case "$category" in
    discoveries|blockers|conventions) ;;
    *) log_error "notepad_append: invalid category '$category' (use: discoveries|blockers|conventions)"; return 1 ;;
  esac

  feature=$(echo "$feature" | tr ' /' '--')
  local file="$NOTEPAD_BASE_DIR/$feature/${category}.md"

  [ -f "$file" ] || notepad_init "$feature"

  local role="${AGENT_ROLE:-unknown}"
  local timestamp
  timestamp=$(date +%Y-%m-%d\ %H:%M)

  echo "- [$timestamp] ($role) $entry" >> "$file"
}

notepad_read() {
  local feature="$1"
  local max_lines="${2:-20}"

  [ -z "$feature" ] && return 0

  feature=$(echo "$feature" | tr ' /' '--')
  local dir="$NOTEPAD_BASE_DIR/$feature"
  [ -d "$dir" ] || return 0

  local output=""
  for category in discoveries blockers conventions; do
    local file="$dir/${category}.md"
    if [ -f "$file" ] && [ -s "$file" ]; then
      local content
      content=$(grep '^- ' "$file" 2>/dev/null | tail -n "$max_lines")
      if [ -n "$content" ]; then
        output+="### $(echo "$category" | awk '{print toupper(substr($0,1,1)) substr($0,2)}')"$'\n'
        output+="$content"$'\n'$'\n'
      fi
    fi
  done

  [ -n "$output" ] && echo "$output"
}

notepad_read_category() {
  local feature="$1"
  local category="$2"
  local max_lines="${3:-20}"

  [ -z "$feature" ] || [ -z "$category" ] && return 0

  feature=$(echo "$feature" | tr ' /' '--')
  local file="$NOTEPAD_BASE_DIR/$feature/${category}.md"
  [ -f "$file" ] || return 0

  grep '^- ' "$file" 2>/dev/null | tail -n "$max_lines"
}

notepad_clear() {
  local feature="$1"
  [ -z "$feature" ] && return 0

  feature=$(echo "$feature" | tr ' /' '--')
  local dir="$NOTEPAD_BASE_DIR/$feature"
  [ -d "$dir" ] && rm -rf "$dir"
}
