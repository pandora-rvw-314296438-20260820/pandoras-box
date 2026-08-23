# Independent worker authority

The governed Windows worker is intentionally inactive until an authority
outside this repository, candidate deployment, and candidate CI is provisioned.
No issuer key, reviewer/worker ingest token, service-role key, or job-envelope
private key may be stored in those candidate surfaces.

The authority has two entrypoints:

1. The Windows controller sends an exact Ed25519-signed `claim` or `complete`
   request to its configured HTTPS authority URL. The authority verifies the
   active enrolled worker key and returns a Supabase-trusted JWT lasting no
   more than two minutes. Its claims must match migration `20260823171000`.
2. After a claim, the Edge gateway sends the exact DB-derived job payload and
   digest to the separately configured job-signing endpoint using that same
   claim bearer. The authority must independently read the canonical claimed
   dispatch and plan, confirm that the claim JTI was consumed for that exact
   worker/request, enforce one job signature per claim JTI, recompute the job
   digest, and only then sign `pandora-worker-control-v1|<jobDigest>` with the
   control key whose public half is pinned on Worker-01.

The job-signing endpoint must not trust fields merely because the candidate
Edge supplied them. Without the independent database read and one-signature
ledger, a candidate Edge could ask the authority to sign an instruction that
was never recorded. The endpoint and its signing key are therefore external
release blockers, not evidence produced by this repository.

PostgREST consumes each claim/completion `issuer+jti` atomically. A job envelope
can be recorded only while the same consumed claim JWT remains fresh and only
for its claimed dispatch. Completion requires a separate fresh authority JWT
bound to the exact worker signature. The signature, its basis hash, nonce hash,
and authority-request hash are persisted on the dispatch and copied into the
independent reviewer attestation and evidence before finalization.

For a lost completion response, Worker-01 keeps the exact signed completion in
its crash journal and requests a new short-lived JWT for that same request. The
database consumes the new JTI and returns an idempotent replay only when every
stored completion field already matches; an old signature cannot create a new
result.

Fail-closed activation checks:

- `pandora-worker-dispatch` has `verify_jwt = true` and only the anon key.
- `PANDORA_WORKER_JOB_AUTHORITY_URL` is configured to a non-candidate HTTPS
  origin; absence or a Supabase/Vercel candidate origin is rejected.
- Worker-01 has an external `authorityUrl` and the reviewed control public key.
- Service role has no execute privilege on nonce, claim, job, completion, or
  authorized worker mutation RPCs.
- Provider readback confirms the migration/grants before any physical worker is
  activated.

The paired rollback is deliberately a capability-disable operation, not a
return to the candidate service-role gateway. It revokes both owner-decision
entrypoints and every legacy/authorized worker mutation path, removes the
authenticator's ingest-role membership, and drains active worker identities.
It never grants the caller-supplied `decided_by` path or service-role
claim/job/completion access. The authority JTI ledger, signed claim and
completion fields, reviewer/physical bindings, immutable guards, and all
historical rows remain in place for audit and reconciliation. Re-enablement
requires a separate reviewed forward migration after external authority is
healthy; the rollback itself contains no re-enable path.
