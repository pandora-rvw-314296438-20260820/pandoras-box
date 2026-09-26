# Operations owner production toggle v1

The original Operations Room can place a workspace into `noProduction=true`, but its database owner/admin contract had no revision-fenced way to clear that hold. Production-risk tasks could therefore remain intentionally unclaimable after canary hardening.

This release adds one database owner operation: `allow_production`.

Properties:
- admitted only by `pandora_ops_owner_request_v1`, which rechecks an active owner/admin membership and active project binding;
- revision-fenced through `pandora_ops_control_v1`;
- changes only `no_production` from true to false;
- does not unpause the workspace, alter budgets, register workers, claim tasks, accept verification, or bypass dependencies;
- emits immutable event `owner_allow_production`;
- stale revisions fail closed with `OPS_CONTROL_REVISION_CONFLICT`.

The immutable #728 Edge handler is deliberately unchanged and still rejects `allow_production`. This avoids rewriting the pinned foundation identity. Activation is performed server-side through the owner/admin RPC with the authenticated owner identity, and a later UI/API evolution can expose it through a separately versioned surface without mutating #728.

The owner explicitly authorized finishing Operations activation. The toggle is needed to claim the already provider-proven production Memory acceptance task after the production hold has served its purpose.
