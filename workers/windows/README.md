# Pandora Worker-01

Worker-01 is a verification-only Windows controller. It accepts one closed,
signed job contract for the canonical repository and an exact 40-character
source SHA. It cannot receive a caller command and cannot mutate production.

Candidate repository code never runs directly on the Windows host. The host
controller invokes only the Docker CLI with a fixed environment. Public source
acquisition happens in a disposable, digest-pinned Hyper-V container with no
credentials. Verification happens in a second digest-pinned Hyper-V container
with `--network=none`, a read-only root filesystem, bounded resources, and no
host bind mounts, sockets, pipes, devices, or inherited environment.

The controller fails closed when any of these are absent:

- an enrolled Ed25519 Worker-01 identity;
- a fresh exact-request JWT from the independently operated worker authority;
- fresh, independently recorded ProjectOS runtime proof;
- a valid control-plane signature and unused nonce;
- exact plan, organization, repository, SHA, and job-class binding;
- digest-pinned acquisition and runner images;
- a runner-policy SHA-256 matching the signed job;
- a Windows container engine accepting `--isolation=hyperv`;
- a network-disabled candidate execution result with at least one discovered
  test and exit code zero.

There is no unsigned local-run mode and no host fallback. A local journal is
written before candidate execution. If the controller crashes after that
boundary, it reports an ambiguous state and never executes the job again.

Exactly one controller process may use a journal. The worker acquires the
exclusive `<journalPath>.process.lock` before reading its private key or
claiming work and holds it through the completion acknowledgement. A second
process returns `busy` without touching the job. The Windows service manager
must also be configured for one instance only.

The process lock intentionally fails closed after an unclean process exit; it
has no time-based auto-recovery. An operator may remove that one lock file only
after proving no worker process owns the configured journal and preserving the
journal for ambiguity review. Never remove or rewrite the journal to retry a
`started` entry: that job may already have executed and requires a new governed
dispatch decision.

## Activation gate

The source in this directory is not an installed Worker-01 release. Activation
requires separately built and reviewed acquisition/runner images, their exact
registry digests, a reviewed runner-policy hash, a signed controller release,
a dedicated non-administrator Windows service identity, protected key storage,
an external authority URL and Supabase-trusted signing key unavailable to the
candidate repository/deployment/CI, database migration/provider readback, and
a real Hyper-V hostile-workload test. The external authority also owns the
job-envelope Ed25519 signing key; Edge receives only the signature for the
exact DB-validated claimed dispatch.
Ordinary `windows-latest` CI proves the contract only; it does not prove the
physical Hyper-V security boundary.

Run the source contract suite with:

```text
npm run test:worker
```
