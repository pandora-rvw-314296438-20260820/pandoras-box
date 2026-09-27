# Operations max concurrency v1

Owner decision: enable real parallel Operations execution after successful whole-sheet acceptance.

This adds one database owner/admin control: `set_max_concurrency`.

Properties:
- revision-fenced;
- range 1..16;
- active owner/admin membership and active project binding required;
- refuses to lower the limit below the number of unreleased leases;
- changes only `max_concurrency` and workspace revision;
- emits immutable `owner_set_max_concurrency`;
- does not register workers, claim tasks, bypass dependencies, relax resource locks, change budgets, enable production, accept verification, or alter task risk.

The previously accepted Operations Edge handler is deliberately left byte-identical. The control is server-side and callable only through the service-role RPC boundary after owner/admin authorization. This avoids changing the frozen foundation while allowing governed runtime concurrency changes.

Initial live target after release: 4. This is only an upper bound; actual parallelism is further limited by eligible fresh workers, lane/capability matching, dependency state, budget, and resource leases.
