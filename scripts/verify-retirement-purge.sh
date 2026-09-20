#!/usr/bin/env bash
set -euo pipefail

npm run build

node --test \
  test/retired-control-plane-zero-trace.test.js \
  test/pandora-universal-architecture-contract.test.js \
  test/pandora-execution-provider-policy.test.js \
  test/supabase-r040-migration-history-receipts.test.js \
  test/supabase-r040-migration-history-remainder.test.js \
  test/provider-idempotency-allowlist-regression.test.js \
  test/provider-mutation-http-contract.test.js
