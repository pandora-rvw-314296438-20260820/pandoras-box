# Pandora PostHog Phase 1

## Source and proof boundary

This additive candidate is reconciled against:

- repository: `pandora-rvw-314296438-20260820/pandoras-box`
- parent main: `c2cc635383b78d457d1731294a6f5b306d85f6be`
- parent tree: `d6d848a1d87b0e9e5561fceba200c4cad05fb4e8`
- runtime package: `mcpmaster@1.3.0-observability`
- Supabase control project: `jcyqixttuebxqqfkjonq` (`MCPMaster Meta Staging`)

It does not assert deployment or production verification.

## What Phase 1 adds

1. A strict CommonJS lifecycle-event builder for the ten Pandora outcome stages.
2. HMAC-SHA256 pseudonymization for actor, organization, and project identifiers.
3. Default-off capture with a separate production-approval requirement.
4. A migration that corrects the stale product-registry repository and installs the ten lifecycle contracts as `active=false`.
5. Focused security and privacy tests.

The existing eleven aggregate-only ProjectOS event contracts are not replaced or deactivated.

## Contract reconciliation

The original source-neutral bundle used `local` and `test`. The current database constraint accepts `development`, `preview`, `staging`, `production`, and `unknown`. The implementation maps `local` and `test` to `development`; it does not change the database constraint.

The original bundle specifies `schema_version=1.0.0`. The candidate emits that property and also emits numeric `event_schema_version=1` for compatibility with the current `projectos_product_signals` schema.

## Always forbidden

Prompts, user-content outputs, tool arguments/results, source code, credentials, authorization data, secrets, KYC/financial/health/legal documents, customer messages, direct identifiers, replay payloads, and unrestricted network bodies.

## Activation gates

Capture remains closed until all are proven:

1. Dedicated PostHog project or independently reviewed equivalent isolation.
2. Consent, IP, retention, residency, and person-profile controls.
3. Sanitizer and schema tests.
4. Exact-source CI at the candidate SHA.
5. Isolated non-production event readback.
6. Replay disabled by default and independently verified masking before any later enablement.
7. Kill-switch and rollback proof.
8. Independent privacy/security review.
9. Separate owner approval for production activation.

Feature flags, experiments, session replay, autocapture, network-body capture, and automatic canonical Memory promotion remain closed.

## Rollback

Before activation, rollback is source-only: remove the additive module, test, migration, and this document. If the inactive migration has been applied, preserve history and run:

```sql
UPDATE private.projectos_event_contracts
SET active = false,
    updated_at = now()
WHERE organization_id = '2270b266-59da-4c39-bfd9-9f8d08352af0'
  AND product_key = 'pandoras_box'
  AND event_name = ANY (ARRAY[
    'pandora_intent_received',
    'pandora_plan_accepted',
    'pandora_execution_started',
    'pandora_build_succeeded',
    'pandora_tests_passed',
    'pandora_deployment_created',
    'pandora_production_verified',
    'pandora_outcome_accepted',
    'pandora_execution_failed',
    'pandora_rollback_completed'
  ]::text[]);
```

Do not delete historical signals or overwrite recovery evidence.
