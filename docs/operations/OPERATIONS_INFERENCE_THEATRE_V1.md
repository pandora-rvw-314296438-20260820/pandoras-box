# Operations-controlled inference and current-event Theatre

Owner contract: canonical Memory `docs/architecture/PANDORA_INTELLIGENCE_ROUTER_BASELINE_V1.md`.
Source base: ea0387277d0a9f0eddec20e51c46e609279222e7. Continuation: OPS-FINISH-20260926-0049 / Operations Room #714.

## Implemented scope and authority

This isolated lane implements the service-side inference lifecycle, a concrete Vault-backed Gemini provider, authenticated HTTP serving, output-bound canonical verification adoption, metadata-only reviewed Memory delivery, and an immutable Operations event feed/browser consumer. It reuses the existing Operations scheduler, project bindings, workers, leases, canonical verification registry and Memory clients. It does not replace the scheduler, create another provider credential store, overwrite PR741 or unpublished Router source, or treat a model invocation as a ChatGPT worker.

The ten capability classes are imported from the existing approved-performance client. Security eligibility is mandatory. Explicit owner overrides are principal/task/expiry-bound. High-risk work ranks model capability strength before price. Only approved/current/revision-and-configuration-compatible numeric Memory evidence may influence ranking. Unknown history is a separate tier, never an invented zero metric. Overlapping snapshots are not summed. Unknown cost ceilings are not admitted; a reserved ceiling is never reported as a bill. Context admission counts UTF-8 bytes conservatively plus approved image-token bounds and maximum output. Image bytes count toward transport limits. No URL fetcher is exposed.

The parent Operations lease must be real, running, unexpired, generation-current, task-bound and attached to a fresh acknowledged worker. Workspaces must permit execution, and production/destructive work respects no-production. New policy/caller tables have no seeded rows; all five tables are RLS-enabled with no browser or direct service-role grants. Only the bounded native RPCs are callable by service_role.

## Durable lifecycle

Caller identity is an independently enrolled opaque worker bearer whose hash maps to an existing real Operations worker/principal. Request IDs are globally unique and payload-digest bound. Scoped Memory context and performance provenance participate in the immutable request digest. A duplicate request reads its original receipt; missing raw output is not fabricated or regenerated.

Preparation reserves a model attempt under current policy, budget, provider capacity and circuit-breaker state. A second native send transition issues canSend=true once. Immediately before sending, project scope, pause/cancellation, worker health, generation, lease and policy are rechecked. A database transaction cannot make its later network send atomic; this remaining network boundary is represented explicitly. Unknown outcomes retain the original attempt and parent lease for reconciliation, not automatic resends. Half-open probes have one durable owner and a generation fence.

Known provider responses carry a digest, provider receipt, reported usage, measured latency and nullable billing/revision. Raw prompts, Memory context and model output do not enter the journal. Cancellation is a request until the provider outcome is known. Parent lease settlement is blocked while attempts or billing remain unknown; known billed costs cannot be underreported by handoff.

A provider response is verification_pending, not complete. Verification consumes an existing canonical PASS bound to the output digest, full request digest, exact source SHA, builder identity and a different acknowledged release principal. This verifies inference only. Existing Operations acceptance remains the only route to task completion, merge or release.

## API

Function entrypoint: `supabase/functions/pandora-intelligence-router/index.ts`.

POST subroutes are `infer`, `status`, `cancel`, `verify`, and `events`.

The four inference routes require a real `opw_` bearer mapped by the service-only native authentication RPC. They reject an ordinary owner JWT as a worker credential. `events` authenticates the owner JWT through Supabase Auth and checks current owner/admin membership plus the active project binding inside the read RPC. Request fields cannot supply another actor. Exact CORS, content type, body size, stream deadline, operation shape and response redaction are enforced.

Because the function implements two explicit authentication schemes, deployment must use the reviewed custom-auth configuration rather than assuming the Supabase gateway understands opaque worker tokens. No deployment has been performed by publishing this source. An originless preflight is transport metadata, not authentication or execution permission.

## Memory identity boundary

The service supports existing `NativeOperationsMemoryClient` and `NativeOperationsPerformanceClient` through authenticated server-owned bindings. Verified output adoption produces only a metadata proposal and checks delivery readback; it never self-promotes canonical Memory or reports downstream task success.

The included Supabase entrypoint deliberately has no Memory binding. The current native Memory principal provider is `vercel_oidc`; an Edge function must not claim that Vercel identity or copy its credential. A legitimate Vercel runtime/gateway binding and appropriate narrow model_outcome/provider_performance grants are required. `requireMemoryContext=true` fails closed until that binding is supplied. This is an outstanding production integration, not completed account configuration.

## Theatre

`pandora_ops_event_feed_v1` reads current immutable Operations events, not the historical Build Theatre projection. It uses scoped high-watermark pagination and decimal-string bigint cursors. No fake percentages or synthetic starts are returned. The browser `OperationsTheatre` consumer validates source/tenant/time/cursor, deduplicates refresh requests, bounds retained events, clears on session reset, fences late responses, and renders untrusted text with textContent rather than HTML. Inference verification is visibly distinct from whole-task acceptance.

The consumer and owner event HTTP route are implemented and tested. Mounting the consumer in the existing owner/mobile UI and enabling runtime refresh are separate integration/acceptance work; no live UI or customer-visible timeline is claimed by this branch.

## Migration and testing

Deployment migration `20260926011646_operations_inference_service_v1.sql` was generated by Supabase CLI2.116.0 during actual GitHub job108308101466. Its bytes match `packages/pandora-operations-inference/schema.sql`; the test enforces that parity. No live schema migration was applied in this lane.

Tests run policy behavior, actual unchanged parent SQL plus the new SQL in disposable PGlite, the real JavaScript service against that native SQL, HTTP/body/auth negatives, provider-response classification and digest checks, independent verification adoption, and browser event isolation. The PostgreSQL workflow uses actual separate connections and observes a blocked competing database session before releasing the holder. It proves admission, parent-budget limits, one-sender dispatch, cross-project provider capacity, one half-open probe and caller-revocation fencing. Synthetic test principals and provider responses never represent real enrolled production workers.

Run the dedicated workflow and normal full repository checks on the final exact head. A focused pass is not a complete repository pass; a skipped cross-repository fixture must remain reported as skipped. The Deno check stays frozen. The only required lock change is the generated npm:@types/node@* alias to already-locked24.13.3; no package version or integrity changed.

## Remaining release gates

A qualifying independent review and the normal exact-SHA coordinator/release decision are still required. Never use an older deployed coordinator implementation to bypass newer source policy. PR741 release, real Workspace Agent channel/token enrollment, native Google runtime authorization, live Memory identity binding, owner/mobile Theatre mounting, wake/recovery deployment, and the full real-worker acceptance run remain external or follow-on integration gates. No new provider approval, paid plan, grant, credential, worker, budget, unpause, production deployment or whole-sheet acceptance is claimed.

Rollback pauses this service and its consumers, preserving receipts, unknown-outcome holds, parent leases, canonical verification and Memory review history. Do not delete uncertain execution evidence to make the queue appear clear.
