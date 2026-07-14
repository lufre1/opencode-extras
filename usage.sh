#!/usr/bin/env bash
#
# usage.sh — print the SAIA request budget and per-model token usage.
#
# Data sources (both maintained automatically):
#   ~/.cache/opencode/saia-gwdg-budget.json  — pacer snapshot of the
#       x-ratelimit-remaining-* headers, rewritten on every SAIA response
#   ~/.local/share/opencode/opencode.db      — opencode's message store
#
# Free when run directly in a terminal. The /usage command in opencode
# splices this output into a prompt, so there it costs 1 SAIA request.
#
set -euo pipefail

exec python3 - <<'PYEOF'
import json
import sqlite3
from datetime import datetime, timezone
from pathlib import Path

BUDGET_PATH = Path.home() / ".cache/opencode/saia-gwdg-budget.json"
DB_PATH = Path.home() / ".local/share/opencode/opencode.db"

# Bucket limits and LOW thresholds mirror saia-gwdg-plugin.js.
LIMITS = {"minute": 30, "hour": 200, "day": 1000, "month": 3000}
LOW_THRESHOLDS = {"hour": 40, "day": 50, "month": 60}


def human(n):
    for unit, div in (("B", 1e9), ("M", 1e6), ("k", 1e3)):
        if n >= div:
            return f"{n / div:.1f}{unit}"
    return str(int(n))


def budget_section():
    print("SAIA request budget (remaining/limit)")
    try:
        snap = json.loads(BUDGET_PATH.read_text())
        remaining = snap["remaining"]
        updated = datetime.fromisoformat(snap["updatedAt"].replace("Z", "+00:00"))
    except (OSError, ValueError, KeyError):
        print("  no budget snapshot yet — it appears after the first SAIA request")
        return
    print("  " + "   ".join(
        f"{bucket}: {remaining.get(bucket, '?')}/{limit}"
        for bucket, limit in LIMITS.items()))
    low = [b for b, threshold in LOW_THRESHOLDS.items()
           if isinstance(remaining.get(b), (int, float)) and remaining[b] < threshold]
    status = ("LOW (" + ", ".join(f"{b} < {LOW_THRESHOLDS[b]}" for b in low) + ")"
              if low else "HEALTHY")
    age_min = (datetime.now(timezone.utc) - updated).total_seconds() / 60
    freshness = (f"as of {age_min:.0f} min ago"
                 if age_min < 90
                 else f"STALE, {age_min / 60:.1f} h old — buckets have likely reset since")
    print(f"  status: {status}   snapshot: {freshness} (updates on every request)")


def collect(db, since_ms):
    per_model = {}
    for (data,) in db.execute(
            "SELECT data FROM message WHERE time_created >= ?", (since_ms,)):
        try:
            msg = json.loads(data)
        except ValueError:
            continue
        if msg.get("role") != "assistant" or msg.get("providerID") != "saia-gwdg":
            continue
        tokens = msg.get("tokens") or {}
        row = per_model.setdefault(msg.get("modelID") or "?", [0, 0, 0, 0])
        row[0] += 1
        row[1] += tokens.get("input") or 0
        row[2] += tokens.get("output") or 0
        row[3] += tokens.get("reasoning") or 0
    return per_model


def usage_table(title, per_model):
    print(f"\n{title}")
    if not per_model:
        print("  (none)")
        return
    width = max(len("total"), *(len(m) for m in per_model))
    print(f"  {'model':<{width}}  {'requests':>8}  {'input':>8}  "
          f"{'output':>8}  {'reasoning':>9}")
    totals = [0, 0, 0, 0]
    for model, row in sorted(per_model.items(), key=lambda kv: -kv[1][0]):
        print(f"  {model:<{width}}  {row[0]:>8}  {human(row[1]):>8}  "
              f"{human(row[2]):>8}  {human(row[3]):>9}")
        totals = [a + b for a, b in zip(totals, row)]
    print(f"  {'total':<{width}}  {totals[0]:>8}  {human(totals[1]):>8}  "
          f"{human(totals[2]):>8}  {human(totals[3]):>9}")


budget_section()
midnight = datetime.now().replace(hour=0, minute=0, second=0, microsecond=0)
month_start = midnight.replace(day=1)
try:
    db = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True, timeout=3)
    try:
        usage_table(f"Usage today (since {midnight:%Y-%m-%d %H:%M})",
                    collect(db, midnight.timestamp() * 1000))
        usage_table(f"Usage this month (since {month_start:%Y-%m-%d})",
                    collect(db, month_start.timestamp() * 1000))
    finally:
        db.close()
except sqlite3.Error as exc:
    print(f"\nUsage history unavailable (opencode.db: {exc})")
PYEOF
