# ChatGPT custom app registration blocker — 2026-08-11

## Current user-facing blocker

The provider runtimes and their ChatGPT OAuth clients are alive, but the two private ChatGPT custom dev-app registrations are absent from the current ChatGPT installed-app registry:

- Pandoras-box: `dev-6a740a072c9481918a93bd1c77a33d69`
- Pandoras-box memory: `dev-6a789b815cb88191b52947de79757f12`

Plugin Management reports both IDs as `not_installed`, and neither ID, callback identifier, nor production endpoint is discoverable in the installable plugin index available to this session.

## Surviving ChatGPT OAuth clients

The app disappearance did not delete the authorization-server registrations.

### Pandoras-box / MCPMaster

- MCP endpoint: `https://mcpmaster.vercel.app/mcp`
- Supabase Auth project: `jcyqixttuebxqqfkjonq`
- ChatGPT OAuth client ID: `e96182a8-4253-4ecb-b380-2521b17556d1`
- registration type: `dynamic`
- callback: `https://chatgpt.com/connector/oauth/OPSG2VnXEltY`
- client type: `public`
- token auth method: `none`
- grants: `authorization_code,refresh_token`
- deleted: no

### Pandoras-box Memory

- MCP endpoint: `https://pandorasbox-memory.vercel.app/api/mcp`
- Supabase Auth project: `ivmvufhcsezyhczzondn`
- ChatGPT OAuth client ID: `a04f89cf-6640-49c6-8df5-b15149914b8e`
- registration type: `dynamic`
- callback: `https://chatgpt.com/connector/oauth/P0JoJjhgZ-DA`
- client type: `public`
- token auth method: `none`
- grants: `authorization_code,refresh_token`
- deleted: no

This proves the missing layer is ChatGPT app installation/registration, not OAuth server loss.

## Provider runtime evidence

- `https://mcpmaster.vercel.app/api/mcp` is reachable and unauthenticated requests fail closed with the expected OAuth 401 challenge.
- `https://pandorasbox-memory.vercel.app` remains on production deployment `dpl_7CbTiMxMXQZjrLQDKchf455iBxi4`; Pandora health/search were previously production-verified.
- Canonical Memory migration identities are recovered through live version `20260810115547` in `banataosystems/pandoras-box-memory`.

## Correct recovery

Do not rotate the Supabase projects, OAuth clients, or provider runtimes merely to compensate for the missing ChatGPT registration. Recreate/re-publish the ChatGPT custom apps against the existing endpoints and let tool scan/OAuth bind to the existing authorization servers.

Required app definitions:

1. `Pandoras-box` → `https://mcpmaster.vercel.app/mcp` → OAuth.
2. `Pandoras-box memory` → `https://pandorasbox-memory.vercel.app/api/mcp` → OAuth.

After re-registration prove:

1. Pandoras-box tool discovery succeeds.
2. Pandoras-box Memory `memory.health` succeeds.
3. Memory search returns namespace-isolated context.
4. OAuth denial/wrong-client paths remain fail closed.
5. Refresh-token renewal remains available.

## Current control-plane limitation

The connected Plugin Management surface exposes inspection, permissions, uninstall, and public-plugin install suggestion, but no create/install/re-publish mutation for an unlisted private dev app. The two private apps are also not returned by plugin discovery. Therefore the final ChatGPT registration write cannot be executed from this session even though the endpoints and OAuth clients are ready.