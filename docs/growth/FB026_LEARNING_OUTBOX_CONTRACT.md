# FB-026 verified learning outbox contract

## Boundary and evidence

This repair hardens the database transport from a verified Operations learning row
to review-gated Pandora Memory intake. It does not approve, promote, or write
canonical Memory.

The source snapshot at `16fc51ecb9cbe905730309a3d64e5ef4fd89c963`
contains two producers of `public.pandora_verified_learning_outbox`:

- `20260927105500_operations_chatgpt_direct_ingress_v1.sql`
- `20260928170000_operations_native_reasoning_rdp_consolidation_v1.sql`

Both producers describe the row as a review-gated candidate and explicitly avoid
self-promotion. That source snapshot contains no definition or caller for the
claim/ack RPCs. The live database supplied the pre-repair table and function
definitions; the append-only migration restores that exact table shape to
canonical source for clean replay. No claim/ack caller was found in the
canonical Pandora or Pandora Memory repositories. An operational consumer must
therefore be identified and upgraded before rollout. This migration intentionally
disables the unsafe legacy calls instead of guessing compatibility.

The live pre-repair ACL allowed only `postgres` and `service_role` to execute
claim, acknowledgement, and the private response validator. The migration
preserves that boundary and adds no role, policy, credential, or provider action.

## V2 calls

Claim:

```sql
select *
from public.pandora_claim_verified_learning_outbox_v2(p_limit := 5);
```

`p_limit` must be non-null and between 1 and 20. Each returned row is moved to
`processing`, increments `attempt_count`, receives a fresh `claim_token`,
and has a five-minute lease. A reclaimed row receives a different token and a
higher attempt count.

A consumer must treat `claim_token` as a short-lived capability: retain it only
for the acknowledgement, do not log it, and do not treat it as evidence.

Acknowledgement:

```sql
select public.pandora_ack_verified_learning_outbox_v2(
  p_outbox_id      := :outbox_id,
  p_claim_token    := :claim_token,
  p_attempt_count  := :attempt_count,
  p_success        := :success,
  p_candidate_id   := :memory_candidate_id,
  p_review_item_id := :memory_review_item_id,
  p_retryable      := :retryable,
  p_error_code     := :bounded_error_code
);
```

The acknowledgement locks the exact row before reading the wall clock, then
succeeds only while the exact token, attempt, processing state, and unexpired
lease still match. A blocked caller therefore cannot validate against a
pre-lock timestamp. Reclaiming or lease expiry fences an old worker. A
successful acknowledgement requires both Memory candidate and review item
UUIDs. A failure accepts neither receipt UUID.

`accepted` means the transport received both review-intake receipt handles. It
does not mean the candidate was reviewed, approved, promoted, or written to
canonical Memory. The migration does not call any promotion API.

A retryable failure below attempt five returns the row to `pending`. Other
failures move it to `failed`. If a fifth claim expires, the next claim pass
moves that row to `failed` with `delivery_attempts_exhausted`; it does not
reclaim a sixth attempt. A still-active fifth lease remains owned until it is
acknowledged or expires. Pending rows already at attempt five are also closed.
Cleanup is ordered, uses `FOR UPDATE SKIP LOCKED`, and is capped by the same
validated `p_limit`; one claim call cannot lock an unbounded exhausted set.
All terminal or retry transitions clear the claim capability and preserve the
difference between transport failure and Memory intake acceptance.

## Legacy compatibility

The old claim signature cannot safely pair with the old acknowledgement:
`pandora_ack_verified_learning_outbox` has no claim token or attempt argument.
Both old functions therefore raise
`PANDORA_LEARNING_OUTBOX_V1_DISABLED` before leasing or mutating a row.

Rollout order is strict:

1. Identify the production consumer and prepare it to read `claim_token` and
   `attempt_count`, then call both v2 RPCs.
2. Confirm there is no active `processing` row. Existing active v1 work would
   need to expire and be reclaimed by v2.
3. Apply this migration.
4. Enable the upgraded consumer and verify one bounded synthetic/intake item
   through claim and acknowledgement readback.
5. Keep automatic Memory promotion disabled and verify candidate/review state
   independently in Pandora Memory.

If consumer deployment cannot be coordinated, do not apply the migration.
Restoring the unfenced v1 acknowledgement is not a safe rollback. A safe rollback
stops the consumer and leaves both legacy functions disabled, while preserving
the table, receipt UUIDs, attempt counts, and v2 claim column for a roll-forward
fix. Never reset accepted receipts or reuse a stale claim token.

## HTTP response validation

The migration also replaces the current private
`execution_learning_response_is_valid(jsonb,integer,text,text,boolean)`
definition with the same typed response contract plus one transport correction:
a null HTTP status returns false. Status 200/202, timeout, error, JSON parsing,
exact source/project identities, receipt fields, and
`canonical_memory_written=false` checks otherwise keep their existing meaning.

## Verification scope

The focused PGlite test executes the migration against the live table shape and
covers:

- null, zero, negative, and over-20 claim limits;
- a maximum 20-row claim and unique per-row capabilities;
- legacy calls rejecting before mutation;
- both success receipt UUIDs being mandatory;
- stale token, stale attempt, and expired lease rejection;
- attempt-five expiry/pending terminalization without a sixth claim;
- retryable versus terminal failure state;
- null HTTP status rejection with the latest typed response contract intact;
- source-level ACL and no-promotion assertions.

PGlite is a single-backend synthetic database. The test does not prove a
two-session lock race, the unidentified production consumer, a deployed
Supabase migration, provider delivery, or Pandora Memory review/promotion.
Those require post-deploy readback and separately authorized runtime evidence.
