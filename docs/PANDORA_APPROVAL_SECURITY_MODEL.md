# Pandora approval security model

Owner decision: AAL2/TOTP is not required for ordinary MCPMaster/Pandora plan approval.

The authorization and execution sequence is:

1. An authenticated human has an active membership in the exact Pandora organization.
2. Only an `owner` or `admin` may approve the exact pending durable plan.
3. Approval records the authenticated human identity. It does not execute the plan.
4. A separate owner/admin action claims and executes the exact approved plan once.
5. Every meaningful lifecycle transition is audited.

Read tools may execute automatically when current policy classifies them as reads. Writes and destructive operations use durable plans, exact payload hashes, expiry, and one-time claim semantics. Provider scopes, account/project/repository allowlists, connector mutation switches, confirmation text, and server-only internal credentials remain enforced.

Destructive operations retain their independent controls. High-impact provider operations remain disabled unless the separate supervised break-glass switch is explicitly enabled, and manifest-defined confirmation text must match exactly.

Machine credentials remain operator/service identities. They cannot declare or inherit owner/admin status and cannot approve a human-governed plan. Caller-supplied approval, approver, Vercel OIDC, and other privileged internal headers are removed before the human session and organization membership are evaluated.

Supabase MFA may remain available at the identity provider, and separate sensitive connection or destructive workflows may retain independently classified step-up controls. MCPMaster/Pandora does not require AAL2/TOTP for ordinary plan approval or OAuth consent.

OAuth consent continues to require an authenticated Supabase session, active Pandora membership, a valid registered client and authorization request, PKCE S256, bound short-lived browser state, registered redirect handling, explicit scopes, and explicit approve or deny consent. Modern OAuth grants that contain any `pandora:*` scope must carry `openid` plus the exact `pandora:read`, `pandora:plan`, `pandora:approve`, or `pandora:execute` action scope (or the explicit `pandora:*` wildcard). The operator bridge retains its exact action-scope checks.

The MCP boundary temporarily accepts the already-consented ChatGPT identity grant of exactly `openid email profile`, with optional `offline_access`, until staged connector re-consent is complete. This compatibility path never substitutes for bearer verification, exact active organization membership, owner/admin role checks, durable plan state, payload hashes, expiry, one-time claim, provider policy, or audit controls. Empty grants, grants without `openid`, unknown extra scopes, and partially migrated `pandora:*` grants fail closed.
