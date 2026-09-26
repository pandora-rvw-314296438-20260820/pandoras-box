# Operations owner production toggle v1

The original Operations Room control contract allowed an owner/admin to place a workspace into `noProduction=true` but exposed no governed way to clear that hold. Production-risk tasks could therefore become permanently unclaimable after activation hardening.

This release adds one operation: `allow_production`.

Properties:
- admitted only through the existing owner/admin authentication and project-binding checks;
- revision-fenced by the same workspace control revision as pause/resume/no_production;
- changes only `no_production` from true to false;
- does not unpause the workspace, alter budgets, register workers, claim tasks, accept verification, or bypass dependencies;
- emits immutable event type `owner_allow_production`;
- stale revisions fail closed with `OPS_CONTROL_REVISION_CONFLICT`;
- the HTTP Operations endpoint exposes no new fields, only the registered operation name.

The owner explicitly authorized finishing Operations activation. This toggle is required to claim the already-evidenced production Memory task after the production hold has served its canary purpose.
