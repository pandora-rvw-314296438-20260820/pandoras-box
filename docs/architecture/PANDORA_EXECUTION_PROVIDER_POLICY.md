# Pandora execution provider policy

Active Pandora execution authority is intentionally limited to:

- GitHub — canonical source, pull requests, refs, and source readback.
- Supabase — database, Edge Functions, Vault-backed transport, state, evidence, and durable runtime coordination.
- Vercel — web deployments and sandbox execution when provider capacity is available.

The retired predecessor control plane is permanently disabled and is not an execution, planning, governance, authorization, verification, or routing layer. Historical predecessor schema/code may remain only as inert audit or compatibility material needed to revoke or read back legacy state.

AWS/RDP, Bitbucket, GitLab, local workers, and other external systems are not Pandora execution fallbacks. AI model providers, analytics, payment providers, and customer integrations may remain product capabilities, but they do not gain execution authority from that integration.
