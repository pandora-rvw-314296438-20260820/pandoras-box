# Pandora Governed Tool Execution v1 — M3-005

Status: implementation candidate for **M3-005**.

## Purpose

M3-005 makes Pandora execute routine tool chains continuously inside already-established authority without weakening the Tool Gateway or turning model output, Memory inference, provider capability, prior success, or prediction into permission.

The separation of responsibilities is:

- **M1-003** owns the continuous reason → act → observe → reason agent loop.
- **M3-005** owns the governed tool-execution seam used by that loop.
- **M0-003** remains the authority-policy contract.
- **M3-004** remains the capability/discovery contract.
- The existing `PandoraToolGateway` remains the execution authority for project-scoped tools.

## Authority path

Routine reads, searches, model calls, tests and bounded non-consequential work continue through the existing Tool Gateway without new approval prompts.

When the existing Gateway would require approval, `PandoraAuthorityToolExecutor` may satisfy that boundary only through a trusted `authorityEvaluator` dependency. The evaluator receives an exact action binding generated from trusted runtime state. It may return:

- `auto_execute` only for `explicit_current_user_instruction`;
- `standing_authorized` only for an `active_explicit_standing_policy` that explicitly reports an exact match;
- `needs_approval` for missing, ambiguous, expired, revoked or otherwise non-granting authority;
- `deny` only for a restrictive safety/security/protected-app/organization/provider boundary.

The evaluator is a runtime dependency, not proposal text. Tool/model proposals cannot inject an authority receipt.

## Exact binding and durable evidence

An authorizing decision is bound to:

- actor/principal;
- organization and project;
- tool and version;
- required capability set;
- execution adapter;
- target resource;
- environment;
- current risk;
- Tool Gateway policy version;
- project version and state hash;
- exact `action_hash`.

The authorization fingerprint hashes those bindings. A current-user decision additionally binds to the exact request ID. A standing-policy decision requires an active policy identity and `standing_policy_match=true`.

The authority decision is converted into a reusable-for-the-same-action approval grant with the exact action hash. This is intentionally **not** a second user approval. It is durable evidence that the current instruction or standing policy already covered the action.

The unchanged Tool Gateway then independently re-resolves current state and re-validates the generated grant. Any organization/project/environment/risk/version/state/action drift fails closed before provider execution.

## Continuous chain behavior

`PandoraToolChainExecutor` executes ordered tool steps until one of these terminal outcomes:

- `completed`;
- `needs_approval`;
- `denied`;
- `verification_required` for an ambiguous mutation;
- `failed`;
- `cancelled`.

A chain never runs later steps after a real authority boundary, policy denial, failed operation, cancellation, or ambiguous mutation. Ambiguous mutations require readback/reconciliation before retry.

## Security invariants

M3-005 does not:

- let model `reason` text or model output grant authority;
- let Memory patterns, predictions, recommendations, provider capability or prior success grant authority;
- widen capability, organization, project, environment, resource, cost, production or protected-app scope;
- bypass durable production-state requirements;
- bypass verification, idempotency, leases, rate limits, scoped credentials, network policy, or lineage;
- create arbitrary shell access;
- take ownership of M1-003 iteration logic;
- claim physical Android/device acceptance.

## Acceptance

Source acceptance requires:

1. routine read/query/test/build chains continue without repeated approval prompts;
2. exact current-user authority can satisfy an existing approval boundary without a second prompt;
3. exact matching active standing authority can do the same;
4. prediction or tampered authority evidence fails closed before provider execution;
5. unresolved approval/deny/failure/cancellation stops the chain;
6. ambiguous mutations stop at `verification_required`;
7. existing Tool Gateway enforcement remains unchanged underneath;
8. exact-head repository CI passes before merge.
