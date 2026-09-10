#!/usr/bin/env bash
# Manage PROJECT_TODO.md — add, list, view, complete tasks
# Usage: ./scripts/todo.sh [view|list|add "task"|complete <pattern>]
set -e

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TODO_FILE="$REPO_ROOT/PROJECT_TODO.md"

view() {
  if [[ -f "$TODO_FILE" ]]; then
    cat "$TODO_FILE"
  else
    echo "PROJECT_TODO.md not found at $TODO_FILE"
    exit 1
  fi
}

add() {
  local task="$1"
  if [[ -z "$task" ]]; then
    echo "Usage: todo add \"task description\""
    exit 1
  fi
  if [[ ! -f "$TODO_FILE" ]]; then
    echo "PROJECT_TODO.md not found at $TODO_FILE"
    exit 1
  fi
  # Append before the "Quick reference" section if it exists, else at end
  if grep -q "## Quick reference" "$TODO_FILE"; then
    local tmp
    tmp=$(mktemp)
    awk -v task="$task" '
      /^## Quick reference/ && !done { print "- [ ] " task; print ""; done=1 }
      { print }
    ' "$TODO_FILE" > "$tmp"
    mv "$tmp" "$TODO_FILE"
  else
    echo "" >> "$TODO_FILE"
    echo "- [ ] $task" >> "$TODO_FILE"
  fi
  echo "Added: $task"
}

complete_task() {
  local pattern="$1"
  if [[ -z "$pattern" ]]; then
    echo "Usage: todo complete <pattern>"
    echo "Example: todo complete agentgateway"
    exit 1
  fi
  if [[ ! -f "$TODO_FILE" ]]; then
    echo "PROJECT_TODO.md not found at $TODO_FILE"
    exit 1
  fi
  if grep -q "\- \[ \].*$pattern" "$TODO_FILE"; then
    if [[ "$(uname)" == "Darwin" ]]; then
      sed -i '' "/$pattern/s/\- \[ \]/\- [x]/" "$TODO_FILE"
    else
      sed -i "/$pattern/s/\- \[ \]/\- [x]/" "$TODO_FILE"
    fi
    echo "Marked complete: $pattern"
  else
    echo "No unchecked task matching '$pattern' found"
    exit 1
  fi
}

case "${1:-view}" in
  view|list) view ;;
  add) add "${2:-}" ;;
  complete) complete_task "${2:-}" ;;
  *)
    echo "Usage: $0 [view|list|add \"task\"|complete <pattern>]"
    exit 1
    ;;
esac
