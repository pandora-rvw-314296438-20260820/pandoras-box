#!/usr/bin/env bash
# Full Pandora skill-system evaluation suite. Run from the repository root.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 1
rc=0
for check in structure invariants routing; do
  echo "════════ $check ════════"
  python3 ".claude/skills/evals/check_${check}.py" || rc=1
  echo
done
echo "════════ SUITE: $([ $rc -eq 0 ] && echo PASS || echo FAIL) ════════"
exit $rc
