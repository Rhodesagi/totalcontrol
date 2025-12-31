#!/bin/bash
set -euo pipefail

# TotalControl - Resume session with memory
export THINK_BRANCH=totalcontrol
export CODEX_THINK_BRANCH="${CODEX_THINK_BRANCH:-$THINK_BRANCH}"

workdir="/home/priv/claudes/totalcontrol"
resume_id="ca78a4d7-2a57-4ea8-91d1-3c3706c8a6b8"

CLAUDE_BIN="${CLAUDE_BIN:-}"
if [[ -z "$CLAUDE_BIN" ]]; then
  if [[ -x "$HOME/.local/bin/claude" ]]; then
    CLAUDE_BIN="$HOME/.local/bin/claude"
  else
    CLAUDE_BIN="$(command -v claude || true)"
  fi
fi
if [[ -z "$CLAUDE_BIN" ]]; then
  echo "Error: 'claude' not found. Set CLAUDE_BIN to the full path." >&2
  exit 1
fi

cd "$workdir"

set +e
"$CLAUDE_BIN" --dangerously-skip-permissions --resume "$resume_id"
status=$?
if [[ "$status" -ne 0 ]]; then
  "$CLAUDE_BIN" --dangerously-skip-permissions --session-id "$resume_id"
  status=$?
fi
set -e
exit "$status"
