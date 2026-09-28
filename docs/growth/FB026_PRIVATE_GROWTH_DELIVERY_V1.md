# FB026 private growth delivery v1

This source slice adds management-only admission of a validated growth envelope to
`private.execution_learning_outbox` and validates the Memory receipt before the
existing reconciler can mark that row delivered. It does not create an active
growth producer, enqueue historical rows, invoke the dispatcher, add a schedule,
or promote Memory content. A source test pass is not production-chain evidence.

## Source and dependencies

- Box base: PR805 `991265538439b54bbaf0c9014632a417e11f75f9`. Its public queue
  fencing, disabled legacy claim/ACK functions and NULL HTTP-status repair remain
  intact.
- Envelope contract: PR804 adapter
  `2822a8e64bc606192728816b333c0d112d22c55e`,
  `src/pandora-growth-learning-outbox.js`. The adapter is pure and has no active
  enqueue caller. It is a separate source dependency, absent from this base.
- Memory intake contract: PR126
  `de1a43c709a097010515b98b018d6d5052681d2a`,
  `supabase/functions/pandora-projectos-learning/growth-learning.ts` and
  `supabase/migrations/20260929030000_growth_learning_intake_v1.sql`.
  Deployment also requires the separate Memory marker-consistency correction:
  a signed growth tool or binding must never fall through to generic intake when
  `learning_kind` is removed or changed.
- Existing private table and signer:
  `20260807083337_projectos_memory_lifecycle_enforcement.sql`; event-key identity:
  `20260902030000_pandora_visible_creation_memory_evidence_outbox_v1.sql`;
  response reconciliation: `20260903013000_pandora_visible_memory_response_contract_v2.sql`;
  current dispatcher: `20260903021000_pandora_project_memory_decision_transport_v2.sql`.
- New migration:
  `20260929040000_growth_learning_outbox_delivery_v1.sql`. The repository CLI
  generated `20260928195755_growth_learning_outbox_delivery_v1.sql`; the new file
  was then explicitly authorized to use the unused `20260929040000` version so it
  follows PR805. No existing migration was edited.

## Admission contract

`private.enqueue_growth_learning_v1(p_payload jsonb) returns uuid` accepts the
complete PR804 `outbox.payload` and returns the durable outbox row ID. It has a
fixed empty search path and definer rights. PUBLIC, anon, authenticated and
service_role have no execute privilege; a future authenticated producer requires
its own bounded authorization design. There is no new public RPC or route.

The function first calls the pure
`private.pandora_growth_learning_payload_is_valid_v1(jsonb) returns boolean`.
This validates exact JSON shapes and types, all six claim classes and their
authority/provenance/evidence rules, canonical UTC dates, safe identifiers,
candidate content hash, binding context hash and deterministic transport UUID.
Malformed input returns false; enqueue rejects it with SQLSTATE `22023` and
`GROWTH_LEARNING_OUTBOX_PAYLOAD_INVALID`. Data and program-limit exceptions fail
closed; missing dependencies and ACL errors remain visible.

The source organization is `2270b266-59da-4c39-bfd9-9f8d08352af0`; the source Box
project is `ee282126-3f61-4058-8c92-2fedbfcecf1f`. The target Memory project is
`7c686cbd-d968-49d5-86cc-918f5e777bd2`, key `mcpmaster-pandoras-box`, namespace
`real_life`, principal `projectos-mcpmaster-production`, environment `production`.
These bindings cannot be widened by a caller. The row's project is the source
Box project; the payload's project is the target Memory project.

The stored payload is unchanged, including explicit JSON nulls. New rows have
`pending` delivery status and zero attempts. The function never dispatches.
The existing scheduled processor may subsequently consume a newly admitted row;
there is no claim that inserting one would remain inert in a deployed database.

The stable identity is `(source organization, source project, learning ID)`.
An advisory transaction lock and a partial unique index enforce one growth row
per identity. Exact replay returns the existing UUID without changing status,
attempts, timestamps, response or payload, including delivered and failed rows.
A changed payload or row binding for that identity raises SQLSTATE `23505` and
`GROWTH_LEARNING_OUTBOX_IDEMPOTENCY_CONFLICT`. Historical collisions fail closed;
the migration does not repair or reset them. The deterministic event key remains
`growth:<organization>:<project>:<learning ID>:<content hash>`.

The two hash serializers and the pure payload validator are invoker-rights
functions. Only service_role receives their execute grants because the existing
service-callable response validator invokes that dependency chain. They cannot
enqueue, read durable state, dispatch or promote content.

The coordinating review's bounded, read-only provider check confirmed existing
service_role USAGE on `private` and `extensions`, and EXECUTE on the existing
response validator in `jcyqixttuebxqqfkjonq`. No schema grant is added here. This
prerequisite readback does not establish deployment of the new functions.

## Delivery and receipt

The existing private route is reused unchanged:

`private.execution_learning_outbox` → `private.dispatch_execution_learning(uuid)`
→ signed `pandora-projectos-learning` request → `net._http_response` →
`private.reconcile_execution_learning_responses()`.

The established signer authenticates the growth binding through `context_hash`,
along with the source event, source request, tenant, target, tool and execution
metadata. The existing consumer owns its attempt bound and reconciliation.
This route is separate from `public.pandora_verified_learning_outbox`; no public
activity job is claimed, replayed or acknowledged by this implementation.

For a growth row, HTTP 200 or 202 alone is insufficient. The response must contain
exactly these twelve fields, with the stated JSON types and bindings:

| Field | Required value |
| --- | --- |
| `ok` | boolean `true` |
| `status` | string `pending_review` |
| `source_event_id` | queued transport UUID string |
| `learning_id` | queued candidate source-event string |
| `content_hash` | queued candidate content-hash string |
| `candidate_id` | UUID string |
| `review_item_id` | UUID string |
| `review_required` | boolean `true` |
| `canonical_memory_written` | boolean `false` |
| `promotion_status` | string `not_promoted` |
| `retrieval_status` | string `not_retrievable` |
| `deduplicated` | boolean, either value |

Missing, extra, mistyped or mismatched fields fail closed. A growth marker in any
of `learning_kind`, `tool` or the `growth_learning` key requires a fully valid
growth envelope. Unknown, empty or malformed kinds cannot use generic success.
The three existing visible-creation receipt branches remain intact; genuinely
untyped generic rows retain their established behavior. NULL status remains
invalid. Delivered means a review candidate and review item were accepted; it
does not mean approved, promoted, canonical or retrievable.

## Disposable verification

Run with the repository's PGlite dependency and a supported Node version:

```sh
node --test test/pandora-growth-learning-outbox-delivery-db.test.js test/pandora-learning-outbox-fencing-db.test.js test/pandora-growth-learning-schema.test.js
node scripts/verify-migration-authority.mjs
node scripts/check-supabase-syntax.mjs
node scripts/verify-supabase-hardening.mjs
node scripts/replay-supabase-migrations.mjs
```

The new database suite executes the actual table/index DDL, unchanged signer,
dispatcher and reconciler, PR805 fencing migration and this migration in PGlite.
Only prerequisite tables and `net.http_post` are local fixtures; HTTP calls are
captured locally and never leave the process. It covers eighteen projected
payloads across the six classes with null/lowercase/uppercase source SHAs,
Unicode and confidence `1e-7`; exact replay and conflicts; malformed JSON;
strict receipts and marker downgrade; signed dispatch and bounded retry;
historical-row preservation; and actual service/anon/authenticated ACL behavior.

Separate frozen verification uses the exact PR804 adapter and PR126 parser,
receipt validator, signature basis and HMAC source with the same eighteen
payloads. It compares both hashes, the unchanged SQL signature and all 36
new/replay receipt variants. It uses a synthetic local signing key and local
HTTP capture, never credentials or deployed intake.

Full migration replay substitutes provider extensions as documented by the
repository replay harness. Neither that replay nor the bounded suite proves
pg_net, cron, provider deployment, live grants, active producer integration or
production delivery. Activation remains held until the adapter, this migration,
the corrected Memory intake and an authorized genuine producer are deployed and
their exact bindings are independently evidenced.
