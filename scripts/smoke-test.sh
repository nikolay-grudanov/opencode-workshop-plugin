#!/usr/bin/env bash
# scripts/smoke-test.sh — A/B smoke test for the F-001 MCP fix.
#
# What it does:
#  1. Sanity check: F-001 fix is in place (grep for the throw string).
#  2. Bootstraps the smoke environment in /tmp/smoke-oswp/ if it doesn't exist.
#  3. Patches the user's opencode.json to use our plugin (with backup).
#  4. Runs `opencode run` against an MCP tool (fff_find_files via npx).
#  5. Greps for the F-001 error string — must be ZERO matches.
#  6. Queries Workshop API for the new run, verifies status=OK and spans present.
#  7. Restores the user's opencode.json from backup.
#
# Returns exit 0 on success, exit 1 on any failure.
#
# Requirements: bun or npm, opencode, raindrop, curl, jq, python3.
# Pre-condition: Workshop daemon running on http://localhost:5899.

set -euo pipefail

# --- config ---
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SMOKE_DIR="/tmp/smoke-oswp"
GLOBAL_OPENCODE_JSON="$HOME/.config/opencode/opencode.json"
GLOBAL_BACKUP="$SMOKE_DIR/opencode.json.backup-2026-07-09"
PLUGIN_NAME=$(node -e "process.stdout.write(require('$REPO_ROOT/package.json').name)")
PLUGIN_VERSION=$(node -e "process.stdout.write(require('$REPO_ROOT/package.json').version)")
PLUGIN_REF="$PLUGIN_NAME@$PLUGIN_VERSION"
EXPECTED_ERROR="tool.execute.after: result.output is required"
WORKSHOP_URL="${WORKSHOP_URL:-http://localhost:5899}"

# --- helpers ---
log()  { printf '[smoke-test] %s\n' "$*"; }
fail() { printf '[smoke-test] FAIL: %s\n' "$*" >&2; exit 1; }

# --- 1. Sanity check: F-001 fix is in place ---
log "Step 1: sanity check — F-001 fix must be in both bundles"
if grep -q "$EXPECTED_ERROR" "$REPO_ROOT/dist/index.js" "$REPO_ROOT/dist/index.cjs"; then
  fail "F-001 regression: '$EXPECTED_ERROR' throw is back in dist/. Aborting."
fi
log "  OK: no '$EXPECTED_ERROR' throw in dist/"

# --- 2. Bootstrap smoke environment (idempotent) ---
log "Step 2: bootstrap smoke env at $SMOKE_DIR"
mkdir -p "$SMOKE_DIR"
cd "$SMOKE_DIR"

# Stub files for fff-mcp to find
mkdir -p src tests
[ -f package.json ] || echo '{}' > package.json
[ -f README.md   ] || echo '# smoke' > README.md
[ -f src/main.ts ] || echo '// stub' > src/main.ts
[ -f tests/test1.py ] || echo '# stub' > tests/test1.py

# opencode.json pointing to our plugin
cat > opencode.json <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "model": "zai-coding-plan/glm-5.1",
  "small_model": "zai-coding-plan/glm-5.1",
  "plugin": ["$PLUGIN_REF"],
  "mcp": {
    "fff": {
      "type": "local",
      "command": ["fff-mcp"],
      "enabled": true
    }
  },
  "permission": {
    "read": {"*": "allow"},
    "edit": {"*": "allow"},
    "bash": {"*": "allow"},
    "external_directory": {"*": "allow"}
  }
}
EOF

mkdir -p .opencode
cat > .opencode/raindrop.json <<'EOF'
{"local_workshop_url":"http://127.0.0.1:5899/v1","debug":false}
EOF

# --- 3. Backup user's opencode.json and switch to our plugin ---
log "Step 3: backup $GLOBAL_OPENCODE_JSON → $GLOBAL_BACKUP"
if [ -f "$GLOBAL_OPENCODE_JSON" ]; then
  cp "$GLOBAL_OPENCODE_JSON" "$GLOBAL_BACKUP"
  # Switch plugin list to ours (use python3 for safe JSON edit)
  python3 -c "
import json, sys
p = '$GLOBAL_OPENCODE_JSON'
with open(p) as f: cfg = json.load(f)
cfg['plugin'] = ['$PLUGIN_REF']
with open(p, 'w') as f: json.dump(cfg, f, indent=2)
"
  trap 'log "Restoring $GLOBAL_OPENCODE_JSON from $GLOBAL_BACKUP"; cp "$GLOBAL_BACKUP" "$GLOBAL_OPENCODE_JSON"' EXIT
else
  log "  (no $GLOBAL_OPENCODE_JSON to back up)"
fi

# --- 4. Run opencode against the MCP tool ---
log "Step 4: run opencode against fff_find_files MCP tool"
cd "$SMOKE_DIR"
# Save full log to file (for debugging), but only show last 20 lines on stdout
RAINDROP_WRITE_KEY=local-noop RAINDROP_DEBUG=true \
  timeout 90 opencode run --model zai-coding-plan/glm-5.1 \
  "Find files in this directory using fuzzy search. List package.json and README.md paths. Use fff_find_files tool." \
  >"$SMOKE_DIR/last-run.log" 2>&1 || true
tail -20 "$SMOKE_DIR/last-run.log"

# --- 5. Grep for the F-001 error ---
log "Step 5: check for F-001 error in last run"
# Known limitation: OpenCode 1.17.x does not pipe plugin debug logs to stdout
# even with RAINDROP_DEBUG=true (they go to an internal logger). We rely on
# the grep below as the primary check, and the Workshop run check (Step 6)
# as a backup. If neither catches a regression, you need to look at
# ~/.local/share/opencode/log/ manually.
if grep -q "$EXPECTED_ERROR" "$SMOKE_DIR/last-run.log"; then
  fail "F-001 regression: '$EXPECTED_ERROR' appeared in opencode output. See $SMOKE_DIR/last-run.log"
fi
log "  OK: no F-001 error in last run"

# --- 6. Query Workshop for the new run ---
log "Step 6: query Workshop for the new run"
NEW_RUN_ID=$(curl -fsS --max-time 5 "$WORKSHOP_URL/api/runs?limit=1" | \
             python3 -c "import json,sys; d=json.load(sys.stdin); print(d[0]['id'] if d else '')")
if [ -z "$NEW_RUN_ID" ]; then
  fail "No runs in Workshop — plugin didn't stream anything"
fi
log "  Newest run: $NEW_RUN_ID"
OUTLINE=$(curl -fsS --max-time 5 "$WORKSHOP_URL/api/runs/$NEW_RUN_ID/outline")
echo "$OUTLINE" | python3 -m json.tool | head -30

# Check status and span count
STATUS=$(echo "$OUTLINE" | python3 -c "import json,sys; print(json.load(sys.stdin)['run']['status'])")
SPAN_COUNT=$(echo "$OUTLINE" | python3 -c "import json,sys; print(json.load(sys.stdin)['run']['span_count'])")
if [ "$STATUS" != "OK" ]; then
  fail "Workshop run status=$STATUS (expected OK). See $SMOKE_DIR/last-run.log"
fi
if [ "$SPAN_COUNT" -lt 2 ]; then
  fail "Workshop run span_count=$SPAN_COUNT (expected ≥2)"
fi
log "  OK: status=$STATUS, span_count=$SPAN_COUNT"

log "ALL CHECKS PASSED"
