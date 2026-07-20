---
description: Force-refresh the SAIA model list cache (1 API request; restart opencode afterwards)
---
Run this exact command with the bash tool and report its output verbatim: bash "${XDG_CONFIG_HOME:-$HOME/.config}/opencode/scripts/reload-models.sh". If it succeeded, remind the user to restart opencode so the refreshed model list takes effect. Requires bash permission — run from the solo or build agent, not auto.
