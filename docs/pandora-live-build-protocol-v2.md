# Pandora Live-Build Protocol V2

Status: canonical protocol contract for Background Build + Streaming.

## Authority

A stream is a customer-visible projection of backend truth. It never owns execution. The BuildJob, its attempt/lease state, ProjectVersion/candidate lineage, verification records, and durable build events remain authoritative.

Every client-visible event is scoped by `organization_id`, `project_id`, and `stream_id`. When a BuildJob exists it is also bound by `build_job_id`.

## Ordering and identity

Protocol V2 uses a database-assigned monotonic `sequence` per stream. The database ignores producer-supplied sequence values and allocates the next sequence while locking the stream session row.

Stable client dedupe identity:

`streamId + sequence`

Clients must never use global row `id`, arrival order, Realtime order, or query default order as lifecycle truth.

## Event schema

Every event has `event_schema_version = 2`.

Current event types:

| Event | Class | Required payload |
| --- | --- | --- |
| `build_admitted` | durable projection | safe Build identity |
| `stream_started` | durable projection | safe stage/model metadata only |
| `file_started` | ephemeral | `file_path` |
| `code_chunk` | ephemeral | `file_path`, exact `content_chunk` |
| `file_completed` | ephemeral | `file_path`, byte summary |
| `generation_completed` | durable projection | file/byte summary |
| `build_job_created` | durable projection | BuildJob/ProjectVersion identity |
| `job_state` | durable projection | safe status/stage |
| `build_step` | durable projection | safe step/status |
| `command_started` | durable projection | real governed command class + redacted display command |
| `stdout_chunk` | ephemeral | bounded redacted real stdout excerpt |
| `stderr_chunk` | ephemeral | bounded redacted real stderr excerpt |
| `command_completed` | durable projection | durable command status/exit/failure + truncation metadata |
| `compile_started` | durable projection | real compiler/analyzer identity |
| `compile_diagnostic` | durable projection | project-relative diagnostic identity/location/summary/fingerprint |
| `compile_completed` | durable projection | actual compiler result + exact diagnostic counts |
| `test_started` | durable projection | governed suite/check identity |
| `test_result` | durable projection | actual suite/check status; skipped is not passed |
| `test_completed` | durable projection | exact executed/passed/failed/skipped counts |
| `repair_started` | durable projection | classified authorized repair attempt + input candidate identity |
| `repair_completed` | durable projection | repair result + changed-file/cost/output candidate identity |
| `verification` | durable projection | safe verification state |
| `preview_ready` | durable projection | safe preview identity/state |
| `needs_you` | durable projection | safe intervention code/message |
| `build_completed` | durable projection | safe terminal summary |
| `build_failed` | durable projection | safe public error |
| `stream_error` | durable projection | safe public error code |

`code_chunk` is a display copy of real generated source and must reconstruct the exact emitted source when concatenated in file/sequence order. Provider chunks must never be trimmed or otherwise transformed before canonical source assembly.

Repair-generated source reuses the same `file_started` / `code_chunk` / `file_completed` lifecycle and marks the activity as repair. A source-changing repair is not successful until the governed build/check path runs again.

Secrets, authorization headers, provider credentials, hidden prompts, chain-of-thought, private keys, service-role keys, raw secret-bearing logs, and credential objects are forbidden in all stream payloads.

The detailed normative producer requirements for the Chat E execution events are in `docs/pandora-visible-execution-events-v2.md`. That extension does not create a second stream or state machine.

## Retention

`code_chunk`, `file_started`, `file_completed`, `stdout_chunk`, and `stderr_chunk` are ephemeral and expire after 20 minutes.

High-level state and outcome events are durable projections retained for 30 days. They are not the permanent evidence authority. Permanent execution evidence remains in BuildJob/step/event/version/verification records.

Cleanup is server-side every 15 minutes. The viewer is never responsible for retention or recovery.

## Replay contract

Authenticated clients call:

`pandora_build_stream_replay_v2(stream_id, after_sequence, limit)`

The response contains:

- authoritative session identity
- current BuildJob status/stage when bound
- a durable step summary
- surviving events ordered by `sequence`
- a replay `watermarkSequence`
- `historyGapDueToRetention`
- `oldestRetainedSequence`
- `hasMore`

Membership is checked at replay time. Revoked users cannot regain stream access by holding an old cursor.

## Reconnect algorithm

Use subscribe-then-replay:

1. Restore only the local resume hint: project ID, stream ID, last rendered sequence.
2. Reauthenticate if needed.
3. Establish the narrow Realtime subscription filtered by `stream_id`.
4. Once the subscription is active, call replay from the last rendered sequence.
5. Buffer live events while replay is in flight.
6. Merge replay and live events by `(streamId, sequence)`.
7. Sort by sequence before presentation.
8. Discard duplicates deterministically.
9. If `hasMore`, page replay until the watermark is covered.
10. If `historyGapDueToRetention` is true, do not fabricate expired source or output. Render the durable summary/current stage and continue with surviving real events.

A local cursor is never authority. A superseded stream, membership change, invalid cursor, or terminal Build followed by a new Build requires authoritative rehydration.

## Lifecycle guarantees

Unsubscribe, navigation, backgrounding, socket loss, auth-token expiry in the viewer, app process death, and force-close are not cancellation signals.

Only an explicit governed cancel action may cancel backend execution.

Two authorized viewers may watch the same stream independently. Neither viewer owns the BuildJob or its worker lease.

## Producer rules

All producers use the same table/protocol. A database trigger allocates sequence and enforces payload bounds, path safety, schema version, retention class, and stream/project identity.

Consequential completion projection follows durable checkpointing. A producer must not project command/build/test/repair completion before the corresponding durable result exists.

Client roles have read-only access to stream rows. They cannot forge authoritative events or choose sequence numbers.

## Handoff

Chat D consumes sequence, replay watermark, retention-gap signal, safe payloads, and dedupe identity. Chat E emits build/repair/test/verification semantics into this protocol. Chat B uses durable BuildJob/step/event history rather than expired code chunks or stdout/stderr for conversation history. Chat F may measure counts/latencies/statuses but not raw source or secret-bearing payloads.
