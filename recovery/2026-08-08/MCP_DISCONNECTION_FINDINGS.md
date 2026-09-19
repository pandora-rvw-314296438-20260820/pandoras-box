# MCP / Pandora Memory disconnection findings

Verified on 2026-08-08 (Asia/Manila).

## Failure boundary

The Pandora Pandora Memory health request is currently intercepted by Vercel Deployment Protection before the MCP application authentication layer runs. The protected `/mcp` request therefore cannot reach `api/mcp.ts` and `handlePandoraMcp` using the Pandora workload path.

## Recovered routing evidence

The independently preserved MCPMaster snapshot defines:

- canonical resource origin `https://mcpmaster.vercel.app`;
- Pandora Memory base URL `https://pandorasbox-memory.vercel.app`;
- `/mcp` rewritten to `/api/mcp`;
- OAuth protected-resource metadata rewritten to `/api/mcp?metadata=...`;
- `api/mcp.ts` delegating to `handlePandoraMcp` in `src/pandora-mcp-handler.ts`.

This supports the diagnosis that a Vercel protection layer in front of the application can break MCP connectivity even when the application route and Pandora Memory service still exist.

## Correct repair

Use Vercel Deployment Protection automation access for the machine-to-machine MCP request while retaining MCP application authentication. Do not make the entire MCPMaster application public merely to bypass the 401.

Vercel documents the `x-vercel-protection-bypass` automation header and the project protection-bypass API for this purpose.

## Current tooling limitation

The connected Vercel management tool available in this recovery session can inspect projects, deployments, protected URLs, logs, and deployment state, but does not expose the mutation for generating/updating a project's Deployment Protection automation-bypass secret. Therefore that production setting has not been changed and Pandora Memory must not yet be reported connected.

## Verification required after repair

1. `/mcp` request traverses Vercel protection using automation credentials.
2. Application-level MCP/OAuth authentication still fails closed for unauthorized callers.
3. `Pandora Memory health` succeeds through the Pandora workload identity.
4. Memory retrieval returns namespace-isolated records.
5. Production deployment ID and rollback candidate are recorded.
