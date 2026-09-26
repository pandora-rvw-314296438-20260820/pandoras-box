# Operations Room concrete cloud connectors

Task: OPS-CLOUD-CONNECTORS-20260926. Canonical coordination: Box issue 714, tracker Operations Room row 40. Base: ea0387277d0a9f0eddec20e51c46e609279222e7.

These additive connectors reuse the merged Operations scheduler and task/Sheet contracts. They do not modify the unpublished primary Intelligence Router worktree or create a competing scheduler.

## Implemented boundaries

- Native HTTPS Workspace Agent trigger and run-status requests use fixed server-owned channel and principal bindings. Total deadlines cover credential loading and body streaming. Redirects, unbounded bodies, unsafe headers and raw provider error leakage are rejected.
- Workspace Agent queue acceptance remains `provider_queued`, never a worker ACK or Pandora completion. The adapter persists an exact request digest and provider run receipt before consuming a separately authenticated, exact-dispatch ACK. Ambiguous delivery is retained for reconciliation, not blindly repeated.
- Native Google Sheets reads use a fixed workbook and numerical sheet ID. Ingestion reuses the existing normalized task schema. Only declared machine output cells are written as literal string values. Inputs, formulas, validation and structured cells are preserved or cause a fail-closed rejection. The connector re-reads before mutation and verifies inputs and outputs afterward. This is not a transactional compare-and-swap guarantee.
- No token, channel access, worker enrollment, provider approval or production activation is created by installing source files. A ChatGPT Pro subscription and role names alone are not dispatchable worker evidence.

## Required server configuration

A published Workspace Agent API channel (`agtch_...`), a Workspace Agent access token authorized for that channel, a genuine authenticated callback path, and server-owned mapping to the canonical organization/project/worker principal are required. An OpenAI Platform API key is not interchangeable. Credentials must be loaded from the existing server-side Vault/provider boundary; they must not be put in agent input, browser code, source, diagnostics or Memory.

The Sheets binding requires an existing OAuth access-token loader, exact spreadsheet ID, sheet ID, header row and bounded task rectangle. This connector consumes the frozen INPUT_COLUMNS/OUTPUT_COLUMNS in `packages/pandora-operations-room/sheet-adapter.js`; it must not silently reinterpret a differently shaped human tracker. A mapping or explicit normalized task range must be separately grounded in current native cell data.

Before `workerDispatch` is admitted, its durable journal and current-scope authorization must be wired to the trusted service. Tests using synthetic transport/receipts prove contract behavior, not live authenticated workers. Existing M3 action and coordinator release boundaries remain mandatory.

## Verification and activation

Run `node --test test/pandora-operations-connectors*.test.js` and the existing `pandora-operations-room-runtime*.test.js` suite through the pinned GitHub workflow. Test fixture IDs, credentials and provider responses are synthetic and never production enrollment or business-outcome evidence.

Keep the existing canonical workspace paused and no-production until authenticated worker enrollment, callback, failure/recovery, safe Sheet roundtrip, release/provider readback and Memory/Theatre evidence are independently accepted. Preserve uncertain mutations and historical receipts during rollback. No whole-sheet acceptance is claimed by source publication.

## Provider contracts consulted

- https://developers.openai.com/workspace-agents/trigger-runs
- https://developers.openai.com/workspace-agents/authentication
- https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/getByDataFilter
- https://developers.google.com/workspace/sheets/api/reference/rest/v4/spreadsheets/request#UpdateCellsRequest

The Workspace Agents API currently queues triggers and exposes beta run status; it does not return the agent's response. Therefore a completed provider run cannot replace a task-bound authenticated output/verification receipt.


## Native delivery and scheduler integration

`native-journal.cjs` calls a real Supabase service RPC against the immutable private delivery journal. `worker-callback.cjs` verifies a per-worker HMAC over the exact raw body and timestamp before accepting an exact task/lease/channel/run ACK. A late authentic ACK resumes the same held lease without re-triggering the provider. The guarded store prevents an old dispatch-error handler from overwriting a confirmed ACK. Historical receipts remain immutable. These are executed source contracts, not configured production worker tools.

`runtime.cjs` wires these native transports to the existing OperationsRuntime and task store, intersects actual enrolled/acknowledged/heartbeat-ready workers with configured channels, provides normalized Sheets ingestion with immutable-spec and output readback, and exposes a fixed-scope authenticated wake handler. It never enrolls a nominal worker or enables production by configuration alone. Generic callback authority, provider-known terminal recovery, scheduled deployment and the whole execution canary still require real trusted integration.

Canonical journal migration: `supabase/migrations/20260926012832_operations_connector_delivery_v1.sql`. The original CLI-generated candidate was reconciled to the actual production migration ledger identity after native installation; the checked-in bytes now match the live stored statement exactly. SHA-256 `6ff1ee8767f518f15c5066f4f51d8f2ade0c2e23caf2376fbde33d2437a40f26` matches the tested `delivery-schema.sql`. It adds one RLS-enabled private table and two service-only RPCs, seeds nothing and leaves existing core routines unchanged. Source presence is not deployment evidence.

## Real intake and configuration boundary

Eight owner-requested implementation/activation/acceptance tasks were admitted through the existing native Ops ingestion RPC into the canonical paused workspace. The true event is `tasks_ingested`, not worker execution. The normalized native Google Sheet copy is `Operations Task Intake`, sheet ID 1910212030, header row 1, 21 columns, in spreadsheet 18JgJd9VD9-k9hPduUegqMKJAkeblZc_YRmx1Qr2q6xg. Bind at most its 99 data rows. The human Operations Room tab is not reinterpreted or replaced. Initial database/Sheet values were independently read back: eight queued tasks, zero workers and leases.

The initial copy used this conversation's Google Drive connection. It does not give Pandora runtime an OAuth token. No runtime Google connection was found for the canonical organization in the inspected connection table. Likewise, no published Workspace Agent channel/access token was found in the inspected Vault metadata. Personal Pro alone does not establish eligible managed-workspace Agent API access; a published channel, dedicated workspace-scoped token and genuinely connected agent tools are separate requirements. No plan, billing or permission changes were made. See https://help.openai.com/en/articles/20001143-chatgpt-workspace-agents-for-enterprise-and-business and the developer authentication contract above.

## Observed verification and review

At exact head 99881d0f, GitHub job 108293480285 passed 99 new connector/runtime/SQL cases and 113 existing Ops cases. PGlite executes the real SQL; synthetic identities and provider responses do not constitute live enrollment or multi-session production race proof. CodeRabbit review 5323702373 identified two valid issues: dependency path filters and Google's omitted empty-cell readback. Both receive narrow corrections and regression tests in the subsequent commit. Exact final-head CI and coordinator/merge/deployment readbacks are separate release evidence.

The separate Intelligence Router, actual Memory caller grants, live Theatre UI feed, account/channel/OAuth provisioning, trusted server deployment and full canary are not completed by this connector package. Keep the workspace paused/no-production until independently verified runtime acceptance. Rollback disables consumers and preserves immutable delivery and lease history.
