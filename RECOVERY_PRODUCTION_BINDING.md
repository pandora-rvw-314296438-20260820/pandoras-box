# MCPMaster recovered production binding

This branch is the operational production lane created after the August 25, 2026 source recovery.

- Base recovered source: `recovery/convergence-latest`
- Exact recovered base SHA: `7398de0014485089150ab154cbcac5617c9fdd6c`
- Existing Vercel project: `prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk`
- Production domain: `https://mcpmaster.vercel.app`
- Deployment authority: encrypted GitHub Actions secret `VERCEL_TOKEN`

The branch exists because Vercel's legacy Git link referenced the suspended `banataosystems/Pandoras-box` account. The dead link was removed. Production deployment now uses this repository-owned workflow without exposing provider credentials.
