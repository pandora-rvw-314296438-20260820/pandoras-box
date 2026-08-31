# Supabase hardening evidence

This directory is the machine-readable hardening checkpoint for Pandora Evo Tasks 50–54.

- Security-advisor findings are adjudicated from live primary/secondary provider state. RLS/no-policy findings are intentionally fail-closed where anon/authenticated table privileges are absent.
- SECURITY DEFINER warnings remain only where exact authenticated/member/role guard chains were reviewed; no grants were weakened.
- Public-schema pg_net/vector relocation is deferred because live caller/type compatibility exists.
- Every live Edge Function is registered with lifecycle class, auth posture, owner, caller evidence, decision and expiry/review date.
- Simple Mode may directly use only the primary Pandora project. The secondary memory/governance project is server-side/broker-only.
- RETIRE_PENDING is not deletion authority. Deletion requires exact caller/dependency evidence, rollback source and provider read-back.
