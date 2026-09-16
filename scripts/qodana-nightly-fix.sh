#!/usr/bin/env bash
# scripts/qodana-nightly-fix.sh
# Called by Antigravity nightly scheduler to:
# 1. Pull latest changes (including auto-updated baseline.sarif.json from CI)
# 2. Check if there are NEW findings vs the previous baseline
# 3. Exit with summary so Antigravity knows what to fix

set -euo pipefail

REPO_DIR="/Users/mario/repositorios/gubernator"
cd "$REPO_DIR"

echo "=== Gubernator Qodana Nightly Fix Pipeline ==="
echo "Time: $(date)"
echo ""

# 1. Pull latest from GitHub (CI may have updated baseline.sarif.json)
echo "[1/4] Pulling latest changes from origin/main..."
git pull --ff-only origin main
echo "Current commit: $(git log -1 --oneline)"
echo ""

# 2. Check if baseline.sarif.json exists and has findings
if [ ! -f "baseline.sarif.json" ]; then
    echo "[SKIP] No baseline.sarif.json found. Run Qodana manually first."
    exit 0
fi

TOTAL=$(python3 -c "
import json
with open('baseline.sarif.json') as f:
    d = json.load(f)
results = d['runs'][0]['results']
print(len(results))
")

if [ "$TOTAL" -eq 0 ]; then
    echo "[OK] baseline.sarif.json has 0 findings. Nothing to fix!"
    exit 0
fi

echo "[2/4] Analyzing baseline.sarif.json ($TOTAL findings)..."
python3 -c "
import json
from collections import Counter

with open('baseline.sarif.json') as f:
    d = json.load(f)

results = d['runs'][0]['results']
rules = Counter(r.get('ruleId','?') for r in results)
print('Findings by rule:')
for rule, count in rules.most_common(15):
    print(f'  {count:4d}  {rule}')
"
echo ""

# 3. Check if there are uncommitted fixes already in progress
echo "[3/4] Checking working tree status..."
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "[INFO] Uncommitted changes found — skipping auto-fix to avoid conflicts."
    git status --short
    exit 1
fi

echo "[4/4] Ready for Antigravity to apply fixes."
echo ""
echo "SARIF location: $REPO_DIR/baseline.sarif.json"
echo "Total findings: $TOTAL"
