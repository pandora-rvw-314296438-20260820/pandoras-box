# Operations allow-production control v1

Operations starts fail-closed with `noProduction=true`. The original runtime intentionally exposed only the one-way `no_production` owner control. Final production acceptance requires a symmetric but equally governed transition.

This change adds `allow_production` only through the existing owner/admin request boundary. It is:
- authenticated as an active owner/admin in the exact organization;
- restricted to an active native Operations project binding;
- compare-and-swap fenced by the current workspace revision;
- recorded as immutable `owner_allow_production` control evidence;
- unavailable as a worker, claim, verification, SQL, or provider-execution operation.

It does not unpause the workspace, create workers, execute tasks, increase budget, approve Memory, or bypass independent verification. Production/destructive tasks remain unclaimable until this exact transition succeeds.

Rollback is `no_production` with the next expected control revision.
