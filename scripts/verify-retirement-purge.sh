#!/usr/bin/env bash
set -euo pipefail

node --test \
  test/retired-control-plane-zero-trace.test.js \
  test/pandora-universal-architecture-contract.test.js \
  test/supabase-migration-parity.test.js \
  test/schema-foundation-baseline.test.js \
  test/supabase-r040-migration-history-receipts.test.js \
  test/supabase-r040-migration-history-remainder.test.js \
  test/provider-idempotency-allowlist-regression.test.js \
  test/provider-mutation-http-contract.test.js

npm run check
