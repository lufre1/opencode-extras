#!/usr/bin/env bash
#
# reload-models.sh — force-refresh the SAIA model list cache.
#
# Fetches /v1/models from GWDG (1 request of the shared rate budget) and
# rewrites ~/.cache/opencode/saia-gwdg-models.json with a fresh fetchedAt,
# so the plugin's weekly TTL restarts. Invoked by the /reload_models command
# or manually. The refreshed list takes effect at the NEXT opencode launch.
#
set -euo pipefail

AUTH_FILE="$HOME/.local/share/opencode/auth.json"
CACHE_FILE="$HOME/.cache/opencode/saia-gwdg-models.json"

KEY="$(python3 -c "
import json
print(json.load(open('$AUTH_FILE'))['saia-gwdg']['key'])
" 2>/dev/null)" || { echo "ERROR: could not read saia-gwdg key from $AUTH_FILE" >&2; exit 1; }

BODY="$(curl -sS --fail --max-time 60 https://chat-ai.academiccloud.de/v1/models \
  -H "Authorization: Bearer $KEY")" \
  || { echo "ERROR: /v1/models fetch failed — cache left untouched" >&2; exit 1; }

mkdir -p "$(dirname "$CACHE_FILE")"
BODY="$BODY" CACHE_FILE="$CACHE_FILE" python3 - <<'PYEOF'
import json, os, time
body = json.loads(os.environ["BODY"])
models = body["data"]
if not isinstance(models, list) or not models:
    raise SystemExit("ERROR: /v1/models returned no models — cache left untouched")
cache = os.environ["CACHE_FILE"]
tmp = cache + ".tmp"
with open(tmp, "w") as fh:
    json.dump({"fetchedAt": int(time.time() * 1000), "models": models}, fh)
os.replace(tmp, cache)
ready = sum(1 for m in models if m.get("status") == "ready")
print(f"Refreshed SAIA model cache: {len(models)} models, {ready} ready.")
print("Restart opencode to load the refreshed list (models are injected at startup).")
PYEOF
