# Operations max concurrency v1

Owner decision: enable real parallel Operations execution after successful whole-sheet acceptance.

This adds one revision-fenced owner/admin control: `set_max_concurrency`.

Properties:
- range 1..16;
- owner/admin membership and active project binding required;
- refuses to lower the limit below the number of unreleased leases;
- changes only `max_concurrency` and workspace revision;
- emits immutable `owner_set_max_concurrency`;
- does not register workers, claim tasks, bypass dependencies, relax resource locks, change budgets, enable production, accept verification, or alter task risk.

The Operations Edge owner API now exposes both `allow_production` (database parity) and `set_max_concurrency` with bounded JSON input. Scheduler lane, capability, dependency, budget and resource fences remain authoritative.

Initial live target after release: 4. This is an upper bound; actual parallelism remains limited by eligible fresh workers and resource/dependency conflicts.
