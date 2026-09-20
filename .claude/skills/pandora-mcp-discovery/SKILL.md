---
name: pandora-mcp-discovery
description: "Discover, verify, and diagnose MCP servers, connectors, and provider tools before relying on them. Load when about to use a capability you have not confirmed exists, when a tool call fails with auth or connectivity errors, when asked 'can Pandora do X', when onboarding a new connector, or when a provider appears degraded. Enforces discover-never-assume and fail-closed capability reporting."
---

# Pandora MCP Discovery

**Never assume an MCP tool exists. Discover it.**

The most damaging error in this system is not a failed tool call — it is a confident plan built on a capability that was never there. That error surfaces late, after work has been sequenced around it.

## Discovery

1. **Inventory.** `pandora_tool_catalog` returns every Pandora provider tool with its enforced `risk`, `provider`, `scope`, `mutation` flag, allowlist, and `requiredProviderScopes`. This is the authoritative answer to "what can Pandora actually do".
2. **Search the wider surface.** Beyond Pandora, other MCP servers may be connected. Search for tools by keyword before concluding a capability is absent — a server that was still connecting at session start may be available now.
3. **Check authentication state.** A server can be *listed* but *unauthenticated*. Its tools are unavailable until someone completes an OAuth flow, and that cannot be done from a non-interactive session. An unauthenticated connector is a hard capability gap for this session.
4. **Inspect the schema** before first use. Required fields, enums, and allowlists tell you what the tool will actually accept.
5. **Verify with a read.** A health or list call proves the credential works. Do this before planning a mutation against it, not after.

## Reading the catalog

Each entry answers a different question:

- `risk` — `read` / `write` / `destructive`. Drives whether approval is required. Treat it as a **floor**: a `write` tool used destructively is destructive.
- `scope` — `account` / `organization` / `project` / `repository` / `branch` / `capability`. The blast radius.
- `mutation` — whether it changes state at all.
- `requiredProviderScopes` — what the credential must carry. A scope mismatch fails at execution, so check it while planning.

An empty `requiredProviderScopes` on a read tool usually means it reads local configuration rather than calling the provider — useful, but not proof the provider is reachable.

## Capability verification

Before asserting Pandora can do something, confirm all four:

1. The tool exists in the catalog.
2. Its server is connected **and authenticated**.
3. The target is inside its allowlist.
4. The credential carries the required scopes.

Any one missing means the answer is "no, and here is precisely why" — not "probably".

Report gaps as gaps. "The Vercel connector is present but unauthenticated, so deployment inspection is unavailable this session" is a correct and useful answer. Inventing a workaround that reaches the same provider through an unauthorized path is not.

## Diagnosing failures

| Symptom | Likely cause | Action |
|---|---|---|
| Tool not found | Not in catalog, or wrong name | Re-inventory. Do not guess a name. |
| 401 / 403 | Credential missing, expired, or under-scoped | Check scopes. Escalate for a rotation. |
| Requires authentication | OAuth not completed | Escalate — cannot be done non-interactively. |
| 404 on a known resource | Allowlist exclusion, or wrong identity | Verify identity and allowlist before assuming deletion. |
| 502 / 503 | Upstream or gateway degraded | Back off, retry bounded. **Read back before retrying a mutation.** |
| Timeout | Ambiguous | Never blind-retry a mutation. Read state first. |

A 404 deserves particular care: an unauthenticated or under-scoped request to a private resource returns 404, not 403. Do not conclude a repository or project does not exist until you have checked identity and allowlist.

## Connector onboarding

New connectors are onboarded fail-closed: least-privilege scopes, an explicit allowlist of exact targets, credentials referenced from a secret store and never recorded in Memory or source, a read-only verification pass before any mutation is permitted, and a negative test proving out-of-allowlist targets are actually denied.

The negative test is the one that gets skipped and the one that matters. An allowlist nobody has tested is a hope.

## Outage handling

When a provider is down: establish scope (one tool, one provider, or everything), check whether in-flight mutations were left ambiguous, **reconcile ambiguous mutations by reading back once service returns** rather than retrying, and report which capabilities are unavailable so planning can route around them honestly.

Do not fall back to a less-governed path to keep working. A degraded provider is a reason to pause that lane, not to bypass its controls.

## Output

```
INVENTORY     <tools available, by provider>
AUTHENTICATED <which servers are usable this session>
GAPS          <capability> — <precise reason unavailable>
VERIFIED      <what you proved with an actual read>
BLOCKED       <what cannot proceed, and what would unblock it>
```
