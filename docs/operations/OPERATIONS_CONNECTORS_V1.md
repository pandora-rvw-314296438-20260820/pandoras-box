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
