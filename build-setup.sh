#!/usr/bin/env bash
#
# build-setup.sh — pack the live SAIA config into setup-saia-opencode.sh
#
# Reads the current opencode.jsonc, saia-gwdg-plugin.js, and prompts/*.md and
# emits a single self-contained installer that can be copied to other devices.
# Rerun this after ANY change to those files, and commit both.
#
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

DELIM="${OC_DELIM_OVERRIDE:-__OC_FILE_EOF__}"
OUT="setup-saia-opencode.sh"
MANIFEST=(
  opencode.jsonc
  saia-gwdg-plugin.js
  reload-models.sh
  usage.sh
  prompts/auto.md
  prompts/coder.md
  prompts/debugger.md
  prompts/researcher.md
  prompts/solo.md
)

# ── Sanity checks ────────────────────────────────────────────────────
for f in "${MANIFEST[@]}"; do
  if [[ ! -f "$f" ]]; then
    echo "ERROR: missing source file: $f" >&2
    exit 1
  fi
  if grep -qF "$DELIM" "$f"; then
    echo "ERROR: delimiter '$DELIM' occurs in $f — pick a different delimiter" >&2
    exit 1
  fi
  if [[ -n "$(tail -c 1 "$f")" ]]; then
    echo "ERROR: $f lacks a trailing newline (heredoc packing would add one)" >&2
    exit 1
  fi
done

COMMIT="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
DIRTY=""
git diff --quiet HEAD -- "${MANIFEST[@]}" 2>/dev/null || DIRTY="-dirty"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

TMP_OUT="$(mktemp "$OUT.XXXXXX")"
trap 'rm -f "$TMP_OUT"' EXIT

# ── Header (interpolates the stamp) ──────────────────────────────────
cat >"$TMP_OUT" <<OC_GEN_HEADER
#!/usr/bin/env bash
#
# setup-saia-opencode.sh — GENERATED FILE, DO NOT EDIT.
# Regenerate with: ./build-setup.sh  (in the opencode config repo)
# Source: opencode-config commit $COMMIT$DIRTY, packed $STAMP
#
# Installs the GWDG SAIA setup for opencode: provider + plugin, and optional
# agents (solo, auto, coder, coder2, researcher, debugger) with their prompts.
# Use flags or interactive prompts to choose which agents to install.
#
# Usage: [GWDG_API_KEY=... GWDG_API_KEYS_EXTRA=key2,key3] bash setup-saia-opencode.sh [OPTIONS]
#
OC_GEN_HEADER

# ── Static installer body ────────────────────────────────────────────
cat >>"$TMP_OUT" <<'OC_GEN_BODY'
set -euo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
DATA_DIR="$HOME/.local/share/opencode"   # the plugin hardcodes this path
AUTH_FILE="$DATA_DIR/auth.json"
BACKUP_DIR=""
ASSUME_YES=0
FORCE_KEY=0
INSTALL_SOLO=2
INSTALL_AUTO=2
OPENCODE_MISSING=0

usage() {
  cat <<'USAGE'
Usage: [GWDG_API_KEY=... GWDG_API_KEYS_EXTRA=key2,key3] bash setup-saia-opencode.sh [OPTIONS]

Installs the GWDG SAIA setup for opencode:
  - opencode.jsonc, saia-gwdg-plugin.js, prompts/*.md into ~/.config/opencode
  - API key into ~/.local/share/opencode/auth.json (chmod 600)
  - optional extra failover keys (GWDG_API_KEYS_EXTRA, comma-separated) into
    ~/.local/share/opencode/saia-gwdg-keys.json (chmod 600) — the plugin
    switches to the next key when the active one's rate budget is exhausted
  - offers to install opencode itself if missing
  - optional agents: solo (default workhorse), auto (orchestrator)
    (default: prompt interactively unless --yes is passed)

Options:
  -y, --yes        answer yes to prompts (e.g. installing opencode)
       --solo      install the solo agent (default: ask)
       --auto      install the auto agent (default: ask)
       --no-solo   skip the solo agent (default: ask)
       --no-auto   skip the auto agent (default: ask)
       --force-key replace an existing saia-gwdg API key
  -h, --help       show this help

The API key is taken from the GWDG_API_KEY environment variable if set,
otherwise prompted for interactively. Files that would be overwritten are
backed up to ~/.config/opencode.bak-<timestamp>/ first.
USAGE
}

for arg in "$@"; do
  case "$arg" in
    -y|--yes) ASSUME_YES=1 ;;
    --force-key) FORCE_KEY=1 ;;
    --solo) INSTALL_SOLO=1 ;;
    --auto) INSTALL_AUTO=1 ;;
    --no-solo) INSTALL_SOLO=0 ;;
    --no-auto) INSTALL_AUTO=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ $ASSUME_YES -eq 1 ]]; then
  # If --yes is passed but no explicit agent flags, default to skip both
  # Only override if user has not explicitly chosen with --solo/--no-solo/--auto/--no-auto
  if [[ $INSTALL_SOLO -eq 2 ]]; then
    INSTALL_SOLO=0
  fi
  if [[ $INSTALL_AUTO -eq 2 ]]; then
    INSTALL_AUTO=0
  fi
fi

# Final defaults for any remaining "ask" (2) values - prompt if terminal available
if [[ $INSTALL_SOLO -eq 2 ]]; then
  if [[ $ASSUME_YES -eq 1 ]]; then
    INSTALL_SOLO=0
  elif [[ -t 0 ]]; then
    read -r -p "Install the 'solo' agent? [y/N] " reply
    if [[ $reply == [yY]* ]]; then
      INSTALL_SOLO=1
    else
      INSTALL_SOLO=0
    fi
  else
    INSTALL_SOLO=0
  fi
fi

if [[ $INSTALL_AUTO -eq 2 ]]; then
  if [[ $ASSUME_YES -eq 1 ]]; then
    INSTALL_AUTO=0
  elif [[ -t 0 ]]; then
    read -r -p "Install the 'auto' agent? [y/N] " reply
    if [[ $reply == [yY]* ]]; then
      INSTALL_AUTO=1
    else
      INSTALL_AUTO=0
    fi
  else
    INSTALL_AUTO=0
  fi
fi

log() { printf '%s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

confirm() {
  if [[ $ASSUME_YES -eq 1 ]]; then return 0; fi
  if [[ ! -t 0 ]]; then return 1; fi
  local reply
  read -r -p "$1 [y/N] " reply
  [[ $reply == [yY]* ]]
}

ensure_opencode() {
  export PATH="$HOME/.opencode/bin:$PATH"
  if command -v opencode >/dev/null 2>&1; then
    log "opencode found: $(command -v opencode) ($(opencode --version 2>/dev/null || echo '?'))"
    return 0
  fi
  if confirm "opencode is not installed. Run the official installer now (curl -fsSL https://opencode.ai/install | bash)?"; then
    curl -fsSL https://opencode.ai/install | bash
    export PATH="$HOME/.opencode/bin:$PATH"
    command -v opencode >/dev/null 2>&1 || die "opencode still not found after install"
    log "opencode installed: $(command -v opencode)"
  else
    OPENCODE_MISSING=1
    log "Skipping opencode install — config files will still be installed; verification will be skipped."
  fi
}

ensure_path_in_shellrc() {
  local line='export PATH="$HOME/.opencode/bin:$PATH"'
  local rc
  case "${SHELL##*/}" in
    zsh)  rc="$HOME/.zshrc" ;;
    bash) rc="$HOME/.bashrc" ;;
    *)    rc="$HOME/.profile" ;;
  esac
  if ! grep -qxF "$line" "$rc" 2>/dev/null; then
    printf '\n# added by setup-saia-opencode.sh\n%s\n' "$line" >> "$rc"
    log "Added opencode to PATH in $rc (source it or restart your shell)"
  else
    log "PATH entry already present in $rc"
  fi
}

backup_existing() {  # $1 = backup-relative path, $2 = existing file
  if [[ -z "$BACKUP_DIR" ]]; then
    BACKUP_DIR="$HOME/.config/opencode.bak-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    log "Backing up existing files to $BACKUP_DIR"
  fi
  mkdir -p "$BACKUP_DIR/$(dirname "$1")"
  cp -p "$2" "$BACKUP_DIR/$1"
}

write_file() {  # $1 = path relative to CONFIG_DIR; content on stdin
  local rel="$1" dest="$CONFIG_DIR/$1" tmp
  mkdir -p "$(dirname "$dest")"
  tmp="$(mktemp)"
  cat >"$tmp"
  if [[ -e "$dest" ]] && cmp -s "$tmp" "$dest"; then
    rm -f "$tmp"
    log "  unchanged: $dest"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    backup_existing "$rel" "$dest"
  fi
  mv "$tmp" "$dest"
  chmod 644 "$dest"
  log "  wrote: $dest"
}


ensure_opencode

if [[ $OPENCODE_MISSING -eq 0 ]]; then
  ensure_path_in_shellrc
fi

log "Installing SAIA config to $CONFIG_DIR"
OC_GEN_BODY

# ── Embedded config files ────────────────────────────────────────────
# Write the full opencode.jsonc (we'll filter at install time)
printf '\nwrite_file "opencode.jsonc" <<\'"'"'%s'"'"'\n' "$DELIM" >>"$TMP_OUT"
cat opencode.jsonc >>"$TMP_OUT"
printf '%s\n' "$DELIM" >>"$TMP_OUT"

# Always embed all prompt files; cleanup_disabled_prompts removes disabled prompt files
printf '\nwrite_file "prompts/solo.md" <<\'"'"'%s'"'"'\n' "$DELIM" >>"$TMP_OUT"
cat prompts/solo.md >>"$TMP_OUT"
printf '%s\n' "$DELIM" >>"$TMP_OUT"

printf '\nwrite_file "prompts/auto.md" <<\'"'"'%s'"'"'\n' "$DELIM" >>"$TMP_OUT"
cat prompts/auto.md >>"$TMP_OUT"
printf '%s\n' "$DELIM" >>"$TMP_OUT"

printf '\nwrite_file "prompts/coder.md" <<\'"'"'%s'"'"'\n' "$DELIM" >>"$TMP_OUT"
cat prompts/coder.md >>"$TMP_OUT"
printf '%s\n' "$DELIM" >>"$TMP_OUT"

# coder2 uses the same prompt as coder (prompts/coder.md)
# Note: no coder2.md file exists - coder2 agent references prompts/coder.md

printf '\nwrite_file "prompts/researcher.md" <<\'"'"'%s'"'"'\n' "$DELIM" >>"$TMP_OUT"
cat prompts/researcher.md >>"$TMP_OUT"
printf '%s\n' "$DELIM" >>"$TMP_OUT"

printf '\nwrite_file "prompts/debugger.md" <<\'"'"'%s'"'"'\n' "$DELIM" >>"$TMP_OUT"
cat prompts/debugger.md >>"$TMP_OUT"
printf '%s\n' "$DELIM" >>"$TMP_OUT"

cat >>"$TMP_OUT" <<'__OC_EMBED_RELOAD'
write_file "reload-models.sh" <<'__OC_FILE_EOF__'
#!/usr/bin/env bash
# reload-models.sh — force-refresh the GWDG model list cache
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
CACHE="$HOME/.cache/opencode/saia-gwdg-models.json"
mkdir -p "$(dirname "$CACHE")"
mv -f "$CACHE" "$CACHE.backup" 2>/dev/null || true
echo "Fetching fresh model list from SAIA..."
echo "Run 'opencode models' to verify (1 API request of your rate budget)."
__OC_FILE_EOF__
__OC_EMBED_RELOAD

cat >>"$TMP_OUT" <<'__OC_EMBED_USAGE'
write_file "usage.sh" <<'__OC_FILE_EOF__'
#!/usr/bin/env bash
# usage.sh — report SAIA request budget and per-model token usage
set -euo pipefail
CACHE="$HOME/.cache/opencode/saia-gwdg-models.json"
BUDGET_FILE="$HOME/.cache/opencode/saia-gwdg-budget.json"
echo "# SAIA Usage Report ($(date +%Y-%m-%dT%H:%M:%S))"
echo "---"
if [[ -f "$CACHE" ]]; then
  echo "Model list cached: $(stat -c %y "$CACHE" 2>/dev/null || stat -f %Sm "$CACHE" 2>/dev/null || echo 'unknown time')"
else
  echo "Model list: not cached"
fi
if [[ -f "$BUDGET_FILE" ]]; then
  echo ""
  echo "Budget status from last response:"
  cat "$BUDGET_FILE"
else
  echo ""
  echo "Budget status: unknown (awaiting first response)"
fi
__OC_FILE_EOF__
__OC_EMBED_USAGE

# ── Footer: API key + verification ───────────────────────────────────
cat >>"$TMP_OUT" <<'OC_GEN_FOOTER'

setup_auth_key() {
  mkdir -p "$DATA_DIR"
  if [[ -f "$AUTH_FILE" ]] && grep -q '"saia-gwdg"' "$AUTH_FILE" && [[ $FORCE_KEY -eq 0 ]]; then
    log "Existing saia-gwdg API key kept (use --force-key to replace)."
    return 0
  fi
  local key="${GWDG_API_KEY:-}"
  if [[ -z "$key" ]]; then
    if [[ -t 0 ]]; then
      read -r -s -p "Enter your GWDG/SAIA API key (Academic Cloud portal): " key
      echo
    else
      die "No GWDG_API_KEY set and no terminal to prompt — export GWDG_API_KEY and rerun."
    fi
  fi
  if [[ -z "$key" ]]; then die "No API key provided."; fi
  if [[ -f "$AUTH_FILE" ]]; then
    backup_existing "auth.json" "$AUTH_FILE"
  fi
  if command -v python3 >/dev/null 2>&1; then
    # merge into any existing auth.json (it may hold other providers' keys)
    ( umask 077; KEY="$key" AUTH_FILE="$AUTH_FILE" python3 - <<'PYEOF'
import json, os
path = os.environ["AUTH_FILE"]
try:
    with open(path) as fh:
        data = json.load(fh)
    if not isinstance(data, dict):
        data = {}
except Exception:
    data = {}
data["saia-gwdg"] = {"type": "api", "key": os.environ["KEY"]}
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
PYEOF
    )
  else
    if [[ -f "$AUTH_FILE" ]]; then
      die "python3 not found and $AUTH_FILE already exists — add this entry manually: {\"saia-gwdg\": {\"type\": \"api\", \"key\": \"...\"}}"
    fi
    if [[ "$key" == *[\"\\]* ]]; then
      die "API key contains a quote or backslash — write $AUTH_FILE manually."
    fi
    ( umask 077; printf '{\n  "saia-gwdg": {\n    "type": "api",\n    "key": "%s"\n  }\n}\n' "$key" >"$AUTH_FILE" )
  fi
  chmod 600 "$AUTH_FILE"
  log "API key written to $AUTH_FILE (chmod 600)."
}

setup_extra_keys() {
  local extra="${GWDG_API_KEYS_EXTRA:-}" keys_file="$DATA_DIR/saia-gwdg-keys.json"
  if [[ -z "$extra" ]]; then
    if [[ -f "$keys_file" ]]; then
      log "Existing extra-keys file kept: $keys_file (set GWDG_API_KEYS_EXTRA to replace)."
    fi
    return 0
  fi
  command -v python3 >/dev/null 2>&1 \
    || die "python3 required to write $keys_file — create it manually: {\"keys\": [\"key2\", ...]}"
  if [[ -f "$keys_file" ]]; then
    backup_existing "saia-gwdg-keys.json" "$keys_file"
  fi
  ( umask 077; EXTRA="$extra" KEYS_FILE="$keys_file" python3 - <<'PYEOF'
import json, os
keys = [k.strip() for k in os.environ["EXTRA"].split(",") if k.strip()]
path = os.environ["KEYS_FILE"]
tmp = path + ".tmp"
with open(tmp, "w") as fh:
    json.dump({"keys": keys}, fh, indent=2)
    fh.write("\n")
os.replace(tmp, path)
print(f"{len(keys)} extra failover key(s) written to {path}")
PYEOF
  )
  chmod 600 "$keys_file"
}

# Fix plugin path to absolute (resolves against CONFIG_DIR)
fix_plugin_path() {
  local input="$CONFIG_DIR/opencode.jsonc"
  
  if [[ ! -f "$input" ]]; then
    return 0
  fi
  
  if ! command -v python3 >/dev/null 2>&1; then
    log "  python3 not found - cannot fix plugin path, skipping"
    return 0
  fi
  
  ( umask 077; python3 - "$input" "$CONFIG_DIR" <<'PYEOF'
import json, os, sys
input_path = sys.argv[1]
config_dir = sys.argv[2]

with open(input_path) as fh:
    data = json.load(fh)

plugin = data.get("plugin", [])
changed = False
for i, p in enumerate(plugin):
    if p == "./saia-gwdg-plugin.js" or p == "saia-gwdg-plugin.js":
        plugin[i] = os.path.join(config_dir, "saia-gwdg-plugin.js")
        changed = True

if changed:
    data["plugin"] = plugin
    tmp = input_path + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(data, fh, indent=2)
        fh.write("\n")
    os.replace(tmp, input_path)
    log("  fixed plugin path: " + plugin[i])

PYEOF
  )
}

# Filter opencode.jsonc based on agent selection
filter_opencode_jsonc() {
  local input="$CONFIG_DIR/opencode.jsonc"
  
  if [[ ! -f "$input" ]]; then
    return 0
  fi
  
  if ! command -v python3 >/dev/null 2>&1; then
    log "  python3 not found - cannot filter opencode.jsonc, skipping agent filtering"
    return 0
  fi
  
  ( umask 077; python3 - "$input" "$INSTALL_SOLO" "$INSTALL_AUTO" <<'PYEOF'
import json, re, sys
input_path = sys.argv[1]
install_solo = int(sys.argv[2])
install_auto = int(sys.argv[3])

# Strip JSONC comments (// line comments) before parsing
with open(input_path) as fh:
    lines = fh.readlines()

# Only strip // comments that appear at the start of a line (after optional whitespace)
# URLs in JSON strings like https:// are not stripped because // is not at line start
cleaned = []
for line in lines:
    stripped = re.sub(r'^(\s*)//.*$', r'\1', line)
    cleaned.append(stripped)
content = '\n'.join(cleaned)

data = json.loads(content)

agent = data.get("agent", {})

# Remove unused agent blocks based on flags
if install_solo == 0 and "solo" in agent:
    del agent["solo"]
if install_auto == 0:
    for a in ["auto", "coder", "coder2", "researcher"]:
        if a in agent:
            del agent[a]
if install_solo == 0 and "debugger" in agent:
    del agent["debugger"]

# Clean up empty agent dict
if not agent:
    del data["agent"]
else:
    data["agent"] = agent

# Write filtered config
with open(input_path + ".tmp", "w") as fh:
    json.dump(data, fh, indent=2)
    fh.write("\n")
import os
os.replace(input_path + ".tmp", input_path)

PYEOF
  )
  chmod 644 "$input"
  log "  filtered: $input (solo=$INSTALL_SOLO, auto=$INSTALL_AUTO)"
}

# Clean up prompt files that are disabled
cleanup_disabled_prompts() {
  # Only remove solo and debugger when neither orchestrator is installed
  # (auto also uses @debugger for Phase 3 validation)
  if [[ $INSTALL_SOLO -eq 0 ]] && [[ $INSTALL_AUTO -eq 0 ]]; then
    rm -f "$CONFIG_DIR/prompts/solo.md"
    rm -f "$CONFIG_DIR/prompts/debugger.md"
    log "  removed (disabled): prompts/solo.md"
    log "  removed (disabled): prompts/debugger.md"
  fi
  
  if [[ $INSTALL_AUTO -eq 0 ]]; then
    rm -f "$CONFIG_DIR/prompts/auto.md"
    rm -f "$CONFIG_DIR/prompts/coder.md"
    rm -f "$CONFIG_DIR/prompts/researcher.md"
    log "  removed (disabled): prompts/auto.md"
    log "  removed (disabled): prompts/coder.md"
    log "  removed (disabled): prompts/researcher.md"
  fi
}

verify() {
  if [[ $OPENCODE_MISSING -eq 1 ]]; then
    log ""
    log "opencode is not installed — skipping verification."
    log "After installing opencode, verify with: opencode models | grep '^saia-gwdg/'"
    return 0
  fi
  log ""
  log "Verifying (fetches the GWDG model list — 1 request of the shared rate budget)..."
  local out count
  if out="$(opencode models 2>&1)" && grep -q '^saia-gwdg/' <<<"$out"; then
    count="$(grep -c '^saia-gwdg/' <<<"$out")"
    log "SUCCESS: $count saia-gwdg models available."
    if [[ -n "$BACKUP_DIR" ]]; then
      log "Previous files were backed up to $BACKUP_DIR"
    fi
    log ""
    if [[ $INSTALL_SOLO -eq 1 ]] && [[ $INSTALL_AUTO -eq 1 ]]; then
      log "Next steps: run 'opencode', press Tab until the 'solo' agent (default"
      log "workhorse) or 'auto' (orchestrator for big tasks) is selected, and give"
      log "it a task. Subagents: @coder, @coder2, @researcher, @debugger."
    elif [[ $INSTALL_SOLO -eq 1 ]]; then
      log "Next steps: run 'opencode', select the 'solo' agent (default workhorse),"
      log "and give it a task. Subagent: @debugger."
    elif [[ $INSTALL_AUTO -eq 1 ]]; then
      log "Next steps: run 'opencode', select the 'auto' agent (orchestrator for"
      log "big tasks), and give it a task. Subagents: @coder, @coder2, @researcher"
      log "(debugger only when needed)."
    else
      log "Next steps: run 'opencode' with the built-in agents (build, plan)."
      log "Install solo/auto later to get full functionality."
    fi
    log "Force-refresh the weekly model cache with /reload_models."
  else
    {
      echo "FAILED: no saia-gwdg models listed."
      echo "Troubleshooting:"
      echo "  - Invalid or expired API key (the plugin fails silently)."
      echo "  - GWDG rate limit exhausted (30 req/min, 200/hour per key) — wait and retry."
      echo "  - Stale cache: rm ~/.cache/opencode/saia-gwdg-models.json and retry."
    } >&2
    exit 1
  fi
}

chmod 755 "$CONFIG_DIR/reload-models.sh" "$CONFIG_DIR/usage.sh"
setup_auth_key
setup_extra_keys
filter_opencode_jsonc
fix_plugin_path
cleanup_disabled_prompts
verify
OC_GEN_FOOTER

# ── Finalize ─────────────────────────────────────────────────────────
bash -n "$TMP_OUT"
chmod +x "$TMP_OUT"
mv "$TMP_OUT" "$OUT"
trap - EXIT
echo "Wrote $OUT ($(wc -c <"$OUT") bytes, source $COMMIT$DIRTY, packed $STAMP)"
if [[ -n "$DIRTY" ]]; then
  echo "WARNING: manifest files have uncommitted changes — installer packs the dirty working tree" >&2
fi
