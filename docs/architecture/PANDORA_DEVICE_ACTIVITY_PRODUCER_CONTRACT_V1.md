# Pandora Device Activity Producer Contract v1

Status: **Bound to frozen Activity Theatre v1**
Owner: M2 contract; consumers: M4/M7/M8 device producers

Device-facing Android code does not create a second event schema. It emits real source facts into the existing canonical Activity Theatre contract in `pandora-activity-theatre-contract-v1.json`; live Theatre and Activity History consume those same admitted events.

For each device event preserve the canonical `jobId`, unique `eventId`, next canonical `sequence`, current `writerEpoch`, offset-aware `occurredAt`, and real device provenance. Use `provenance.sourceType = "device"`; provide a privacy-safe `sourceId` and either `sourceEventId` or typed evidence.

Use `device_event` evidence only for real Android/device observations or callbacks. Permission checks, SMS sent/delivery callbacks, telephony state, contact resolution, connectivity and device readback must reflect what Android actually reported. Never manufacture callback, delivery, connection, completion, percentage, or stage truth.

A physical-device `result` requires both overall-job verification evidence and `device_event` verification evidence. Request submission, permission grant, API invocation, dialer/composer launch, or provider acceptance alone is not a verified physical Result.

Use only frozen public states. `needs_you` is reserved for a genuine user boundary with the exact required action. Permission denial may become Needs You only when the user can actually resolve that boundary; ordinary waiting, dispatch in progress, callback latency, verification, or bounded retry is not Needs You.

Consequential retries must reuse the same side-effect/idempotency identity and reconcile ambiguous outcomes before retry. A reconnect or process restart preserves the original source-event identity and occurrence time; it must not resend an SMS, restart a call, or duplicate another consequential action simply to recreate activity.

Public messages and evidence references must never contain SMS bodies unless specifically authorized for that public surface, raw contacts databases, OTPs, credentials, tokens, private app payloads, raw tool arguments, or other protected-app data. Prefer bounded identifiers and sanitized outcome summaries.

Producer sequence for direct communications should normally be: accepted canonical job → real resolution/check events → real dispatch/request event → real Android callback/readback → verified terminal event. Omit any stage for which no real event exists.

History requires no separate write. Once the canonical event is admitted, M2-002 renders it live and M2-008 reads the same immutable canonical event later, subject to the same requester/tenant privacy boundary and retention policy.
