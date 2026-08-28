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
#   effort.sh off        disable thinking (chat_template_kwargs.enable_thinking=false)
#   effort.sh LEVEL      thinking on, reasoning_effort=LEVEL (low|medium|high|max)
#
# Invoked via !`...` injection from command/effort.md: only stdout reaches the
# prompt there, so errors go to stdout and every path exits 0.
set -uo pipefail

EFFORT_FILE="$HOME/.config/opencode/effort.json"
DEFAULT="high"
LEVELS=(off low medium high max)

mkdir -p "$(dirname "$EFFORT_FILE")"

current() {
  local level=""
  if [[ -f "$EFFORT_FILE" ]]; then
    level=$(sed -n 's/.*"level": *"\([^"]*\)".*/\1/p' "$EFFORT_FILE" 2>/dev/null | head -1)
  fi
  case " ${LEVELS[*]} " in
    *" $level "*) echo "$level" ;;
    *) echo "$DEFAULT" ;;
  esac
}

ladder() {
  local cur out=""
  cur=$(current)
  for l in "${LEVELS[@]}"; do
    if [[ "$l" == "$cur" ]]; then out+="[$l]  "; else out+="$l  "; fi
  done
  echo "Reasoning effort: ${out% } (default: $DEFAULT)"
}

ARG="${1:-}"

if [[ -z "$ARG" || "$ARG" == "?" || "$ARG" == "show" ]]; then
  ladder
  echo "Set with: /effort off|low|medium|high|max"
  exit 0
fi

case " ${LEVELS[*]} " in
  *" $ARG "*) ;;
  *)
    echo "Invalid effort '$ARG' — use off|low|medium|high|max (or no arg to show current)."
    ladder
    exit 0
    ;;
esac

# Atomic write so the pacer never sees a partial file.
TMP="$EFFORT_FILE.tmp"
printf '{"level": "%s", "updatedAt": "%s"}\n' "$ARG" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" >"$TMP"
mv "$TMP" "$EFFORT_FILE"

echo "Reasoning effort set to '$ARG' for thinking models."
echo "Applies to the current session immediately (the pacer re-reads the setting per request)."
