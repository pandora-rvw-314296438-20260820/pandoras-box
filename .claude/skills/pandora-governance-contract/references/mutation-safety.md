# Mutation safety

## The confirmed-mutation rule

> Once an external provider mutation is confirmed successful, a downstream serialization, validation, parsing, or reporting failure must not turn that mutation into a retryable failure.

This is the single most important rule in this file, because violating it causes duplicate real-world effects: two issues, two charges, two emails, two payouts.

### Why agents get this wrong

The natural code shape is:

```
result = provider.mutate(payload)
parsed = schema.parse(result)     // throws
return parsed
```

The throw happens *after* the provider already changed state. An agent seeing the exception concludes "the operation failed" and retries. The provider now has two mutations.

### Correct handling

Separate the outcome of the *mutation* from the outcome of the *reporting*:

1. The moment the provider confirms, treat the external effect as **committed**. Record it immediately — provider ID, timestamp, idempotency key — before doing anything that can fail.
2. If a later step fails, the operation's status is `mutation_committed / reporting_failed`. That is not `failed`.
3. Recover by **reading provider state back**, never by re-issuing the mutation.
4. Surface the reporting failure honestly. It is a real defect worth fixing; it is just not a reason to duplicate an external effect.

## Ambiguous outcomes

Sometimes you genuinely do not know whether the mutation landed — a timeout, a dropped connection, a 5xx after the request was accepted.

**Never blind-retry an ambiguous mutation.** Instead:

1. Read provider state to determine whether the effect exists.
2. If it exists → mutation committed. Proceed.
3. If it does not exist and you can prove it does not → safe to retry.
4. If you cannot determine either way → **escalate**. Do not guess. For anything touching money, communications, or third-party-visible state, an unresolvable ambiguity is an owner decision.

A 502 from a gateway is exactly this case: the gateway failed, but the origin may have succeeded. Read back before retrying.

## Idempotency

Every mutation carries an idempotency key derived from the *intent*, not from the attempt. Pandora's Pandora does this structurally: a durable plan has a `payloadHash` and a one-time `claimedAt`, so an approved plan executes at most once even if execution is invoked twice.

When designing a new adapter:
- key on stable intent identity (project + operation + target + logical version)
- never key on a timestamp, a random value, or a retry counter
- persist the key *before* issuing the mutation, so a crash mid-flight is recoverable
- make the key visible in audit output

## Retries

Retry only when the failure is provably before the mutation: connection refused, DNS failure, 401/403, 400 validation rejection, or a provider error explicitly documented as "no effect".

Do not retry: timeouts after request acceptance · 5xx after acceptance · any failure whose position relative to the mutation you cannot establish.

Bound retries (attempts and total time), use exponential backoff, and treat exhaustion as escalation rather than silent failure.

## Rollback artifacts

Identify the rollback artifact **before** a sensitive mutation, not after it fails. A rollback target that has never been verified retrievable is a hope, not a plan. For migrations, this means the down-migration exists and has been replayed; for deployments, the previous artifact is confirmed still deployable.
