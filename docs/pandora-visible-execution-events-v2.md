# Pandora Visible Execution Events — Protocol V2 Extension

Status: normative producer contract for Pandora Live-Build Protocol V2.

This extension defines the Builder/Repair/Trust events produced after real source exists. It does **not** create another stream, sequence, retry identity, Build state machine, or durable evidence store. All rows use the canonical `pandora_build_stream_events` stream and database-assigned per-stream `sequence`. BuildJob/attempt/step, ProjectVersion, artifact and verification records remain authority.

## Execution events

| Event | Retention | Required safe meaning |
| --- | --- | --- |
| `command_started` | durable projection | A governed command actually began; includes step key, command class and redacted display command. |
| `stdout_chunk` | ephemeral | Bounded, redacted excerpt of stdout from that actual command. |
| `stderr_chunk` | ephemeral | Bounded, redacted excerpt of stderr from that actual command. |
| `command_completed` | durable projection | Durable command result exists; includes status/exit code/failure class and truncation metadata. |
| `compile_started` | durable projection | Governed compile/analyze/build validation actually began. |
| `compile_diagnostic` | durable projection | Structured safe diagnostic with project-relative `file_path`, location/code/message/fingerprint where available. |
| `compile_completed` | durable projection | Actual compiler result with diagnostic counts/fingerprint. |
| `test_started` | durable projection | Governed test/check suite actually began. |
| `test_result` | durable projection | Actual suite/check result; skipped/not-run is never counted as passed. |
| `test_completed` | durable projection | Exact executed/passed/failed/skipped counts. |
| `repair_started` | durable projection | A classified, authorized, bounded candidate repair actually began. |
| `repair_completed` | durable projection | Repair attempt outcome with input/output candidate identity and bounded cost/change summary. |
| `file_started` / `code_chunk` / `file_completed` | canonical existing semantics | Repair source reuses the existing real-source lifecycle; payload marks activity=`repair`. |

## Trust ordering

Customer projection follows durable execution checkpointing. A producer must not emit `command_completed`, `compile_completed`, `test_completed`, `repair_completed`, `preview_ready`, or terminal success before the corresponding authoritative result exists.

A source-changing repair is never complete because a model returned code. It must operate against the exact failed candidate, materialize the changed source, rerun the governed compile/analyze/build step and required tests/checks, and return to independent verification.

## Output safety

Customer-visible stdout/stderr is display evidence only. It is:

- redacted for known credential values and secret-shaped token/header/key patterns;
- bounded per chunk and per step;
- ephemeral under Protocol V2 retention;
- allowed to state that additional output was hidden when truncated;
- never the sole durable debugging or verification authority.

Hidden prompts, chain-of-thought, provider credentials, authorization headers, private keys, raw environment objects and platform secret paths are forbidden.

## Diagnostic safety

Diagnostics use project-relative paths only. Absolute worker/container prefixes are not customer-visible. Diagnostic fingerprints are normalized operational identifiers and must not include raw source or secret values.

## Repair disposition

Only explicitly auto-repairable source defects enter autonomous mutation. Infrastructure retry, missing customer/provider authorization, security/policy blocks, budget/deadline exhaustion and non-repairable failures do not trigger arbitrary source rewriting.

## Consumer contract

Chat D renders only these real events and never invents activity. Chat B derives historical summaries from durable BuildJob/step/event/verification records, not expired stdout/stderr or source chunks. Chat F may measure safe stage/fingerprint/outcome/cost metadata but not raw source or secret-bearing output.
