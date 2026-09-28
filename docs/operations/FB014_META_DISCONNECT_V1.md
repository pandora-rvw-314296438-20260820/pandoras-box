# FB-014 Meta disconnect and revocation contract

This source slice closes the missing local revocation primitive without disrupting the live Meta connection.

- Owner-facing disconnect remains AAL2 and governed through the existing approval/intake path.
- The execution primitive is service-role-only and rechecks an active owner/admin membership.
- Execution is bound to the exact organization, installation and current credential key version.
- A second active Meta installation fails closed rather than partially disconnecting an ambiguous provider scope.
- One transaction revokes the connector installation, current credential generation and organization Meta connection. Pandora's existing runtime secret resolver therefore stops both Page and Marketing access.
- No Meta request is sent and no Vault secret is deleted. This is a local authorization disconnect, not a claim of provider-side token revocation.
- Reconnect uses the existing one-time OAuth commit. That path restores active/current/connected state and increments the credential key version, so a stale disconnect cannot revoke a fresh reconnect.

Release evidence must include an actual-schema transactional rehearsal with rollback against the current production connection, proving tenant/generation denial, runtime-secret denial after local disconnect, and unchanged live state after rollback.
