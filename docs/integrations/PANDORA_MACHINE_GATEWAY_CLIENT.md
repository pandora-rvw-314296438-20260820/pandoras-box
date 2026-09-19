# Pandora → Pandora Machine Gateway

**Status:** recovery overlay implemented in canonical source; not yet integrated into the recovered MCPMaster runtime

## Purpose

Replace the old dependency on Vercel Deployment Protection bypass credentials with short-lived Vercel workload identity when Pandora/MCPMaster calls Pandora Memory.

Human/operator MCPMaster surfaces may remain protected by Vercel SSO. Server-to-server Pandora traffic goes directly to the Supabase-hosted machine gateway.

## Machine endpoint

`https://ivmvufhcsezyhczzondn.supabase.co/functions/v1/pandora-machine-gateway`

The endpoint is a protected MCP resource. It exposes only capabilities independently enabled in the Pandora gateway registry.

## Authentication

Pandora running inside the production `mcpmaster` Vercel project obtains a short-lived signed workload token with `@vercel/oidc` and sends it only in:

`x-pandora-workload-oidc: <signed short-lived token>`

Do not:

- store the token in Supabase Vault;
- store it in GitHub;
- store it in Pandora semantic Memory;
- log it;
- transform it into a long-lived shared secret;
- use the old `x-vercel-protection-bypass` mechanism for this new machine path.

The gateway cryptographically verifies the Vercel issuer/audience/subject and then independently checks gateway service/action/resource grants.

## Production identity currently registered

Principal key: `pandora-mcpmaster-production`

The gateway principal is derived from the already verified Pandora service principal for the Vercel project that owns `mcpmaster.vercel.app`. The gateway does not grant this identity universal access.

Current intended grants are only:

- `pandora_memory / health / production`
- `pandora_memory / search / production / namespace:real_life`

No FlutterFlow, GitHub, Vercel administration, Supabase administration, PostHog, Resend, or other provider access is inherited.

## Recovery overlay

`recovery/overlay/pandora-machine-gateway-client.ts`

The overlay uses `getVercelOidcToken()` and provides:

- `callPandoraMachineGateway(...)`
- `pandoraMemoryHealth()`
- `pandoraMemorySearch(query, limit)`

It intentionally contains no credential value.

## Integration gate

Do not claim MCPMaster/Pandora is migrated merely because this overlay exists. The recovered running MCPMaster source must import/wire this client, deploy from canonical source, and prove the signed-token path against the live gateway.

## Required verification

1. canonical MCPMaster source contains the client integration;
2. exact source SHA is recorded;
3. deployment comes from that source;
4. signed Vercel workload token reaches the Supabase gateway;
5. `memory_health` succeeds;
6. approved `memory_search` succeeds;
7. wrong Vercel project/subject is denied;
8. FlutterFlow remains denied;
9. gateway audit records the allow/deny decisions without token content;
10. MCPMaster rollback target is recorded;
11. Pandora internal cron/learning continues during any MCPMaster outage.

## Current distinction

- Gateway workload authorization registry: **implemented + database-tested**.
- Gateway runtime workload verification: **implemented + deployed**.
- Canonical MCPMaster client overlay: **implemented in recovery branch**.
- Recovered MCPMaster runtime integration: **blocked by source recovery**.
- End-to-end signed workload call from production MCPMaster: **not yet production-verified**.
