#!/usr/bin/env bash
#
# effort.sh — set the SAIA reasoning effort for thinking models.
#
# Writes ~/.config/opencode/effort.json, which the plugin's pacer re-reads on
# every request, so the change applies to the CURRENT session immediately
# (no restart). Missing file => default "high".
#
# Usage:
#   effort.sh            print the current level
#   effort.sh off        disable thinking (chat_template_kwargs.thinking=false)
#   effort.sh high       thinking on, reasoning_effort="high"
#   effort.sh max        thinking on, reasoning_effort="max"
#
set -euo pipefail

EFFORT_FILE="$HOME/.config/opencode/effort.json"
DEFAULT="high"

mkdir -p "$(dirname "$EFFORT_FILE")"

current() {
  if [[ -f "$EFFORT_FILE" ]]; then
    python3 -c "import json,sys; print(json.load(open('$EFFORT_FILE')).get('level','$DEFAULT'))" 2>/dev/null \
      || echo "$DEFAULT"
  else
    echo "$DEFAULT"
  fi
}

ARG="${1:-}"

if [[ -z "$ARG" || "$ARG" == "?" || "$ARG" == "show" ]]; then
  echo "Reasoning effort: $(current) (default: $DEFAULT)"
  echo "Set with: effort.sh off|high|max"
  exit 0
fi

case "$ARG" in
  off|high|max) ;;
  *)
    echo "ERROR: invalid effort '$ARG' — use off|high|max (or no arg to show current)" >&2
    exit 1
    ;;
esac

# Atomic write so the pacer never sees a partial file.
TMP="$EFFORT_FILE.tmp"
printf '{"level": "%s", "updatedAt": "%s"}\n' "$ARG" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMP"
mv "$TMP" "$EFFORT_FILE"

echo "Reasoning effort set to '$ARG' for thinking models."
echo "Applies to the current session immediately (the pacer re-reads the setting per request)."
