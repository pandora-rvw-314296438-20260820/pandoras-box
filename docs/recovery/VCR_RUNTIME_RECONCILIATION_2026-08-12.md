# Verified runtime reconciliation — 2026-08-12

The canonical repository's default branch at `3de0e050fd67a662854c053408b06106f75df374` did not contain the MCPMaster source tree. This branch therefore recovered the last verified runtime artifacts before changing the approval boundary.

## Provenance

- Historical Git revision recorded by Vercel: `6faf1dd25cb12f6ff20aa4f9500658c285d3025f`
- Verified Vercel deployment: `dpl_8ZyJBv7oR4gC4krdo2eYfj6DKVMX`
- OCI image manifest: `sha256:10c93a3879dee1bc5dab40470924bfc1869ecea952fb22e93de3f0dabc9a48e3`
- OCI image config: `sha256:86f80aaa5fc80621245ac70b7d8af4c369c8f1e7ddfa1354e7aa51edfc0b8e48`
- Root runtime layer: `sha256:793d0e46da67adf573a752abebb3362de91f38b9629bcc04a3b09d20bb7e976c`
- Meta/operator layer: `sha256:b27424c97649b00986b854c487164351a5d0287f19b7703b65eb037fdafa7893`
- Control Tower layer: `sha256:703abf6330911ed89158a336948313dfa73921b97707656c1cb53ec2b743b1cd`
- Shared-security layer: `sha256:37ef3bc64f94625b928457e74281b15878eac62bb832e812fba81b8f10b7f66d`
- Package manifest layer: `sha256:4f94fe92824ba8da39e7c11b10acdfabfe13f02e9eae882c5191a4fb874f9566`
- OAuth consent JavaScript: `sha256:ee58a935f20ff387972ea7e0755fb4362d42987c6b25c92a7dbb98274f3b137d`
- OAuth consent HTML: `sha256:2976536a92db099b6962c167f796d6744b0b144652aeda6d096cbde6c1ddad09`
- Deployed `pandora-owner-api` v3 bundle: `sha256:d435fcde46c86dc7afa5c52f1e2160e476750a900aad87444d9beb527777ec81`
- Deployed `mcpmaster-supabase-control` v9 bundle: `sha256:85b2fee91e3121690d34baec83a55ccc6373e8215417e455de6c9de9ad50a47c`

All OCI layer downloads were authenticated, and each downloaded layer's SHA-256 matched the manifest digest before extraction. The original TypeScript and test files were not present in the runtime image; the recovered CommonJS runtime was promoted to reviewable JavaScript source and a Node 24 build/test harness was rebuilt around it. The missing Pandora MCP serverless handler was reconstructed against the recovered durable-ledger and provider-policy modules. The active execution-ledger Edge Function and SQL function definitions were recovered read-only from Supabase; the source copy adds UUID validation for approve, claim, and finish inputs before any future deployment.

No production deployment or Supabase migration was performed by this reconciliation. Two protected preview recovery probes (`dpl_BmxaUYc7f1hYHx6UvZbd5WDhsf4f` and `dpl_9EyvANFLXJxoKNkCA3VWzo7DRoBd`) failed closed because the historical builder cache was unavailable; neither changed a production alias.

A read-only query of active Supabase OAuth records on 2026-08-12 confirmed that historical ChatGPT and Claude authorization requests used standard OIDC scopes (`openid`, `email`, `profile`, and optionally `offline_access`). The reconstructed MCP handler does not treat those identity scopes as action authority: clients must obtain explicit `pandora:*` scopes before invoking Pandora tools. Existing grants require a new consent exchange before a future release of this branch.
