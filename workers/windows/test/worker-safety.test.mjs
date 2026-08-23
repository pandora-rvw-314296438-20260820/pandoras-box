import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import { mkdtemp, readFile, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";
import test from "node:test";
import {
  jobDigest,
  validateClaimRequest,
  validateCompleteRequest,
} from "../../../supabase/functions/pandora-worker-dispatch/contract.mjs";
import {
  MAX_WORKER_JOURNAL_BYTES,
  runOnce,
} from "../pandora-worker.mjs";

const NOW = new Date("2026-08-23T15:01:00.000Z");

async function fixture() {
  const directory = await mkdtemp(join(tmpdir(), "pandora-worker-test-"));
  const controlKeys = generateKeyPairSync("ed25519");
  const workerKeys = generateKeyPairSync("ed25519");
  const rawControlPublic = controlKeys.publicKey
    .export({ format: "der", type: "spki" })
    .subarray(-32)
    .toString("base64");
  const workerPrivate = workerKeys.privateKey
    .export({ format: "der", type: "pkcs8" })
    .toString("base64");
  const configuration = {
    acquisitionImage: `registry.example/pandora-acquire@sha256:${"a".repeat(64)}`,
    authorityUrl: "https://worker-authority.example/v1/authorize",
    controlPublicKeyB64: rawControlPublic,
    gatewayUrl:
      "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-worker-dispatch",
    journalPath: join(directory, "journal.json"),
    organizationId: "2270b266-59da-4c39-bfd9-9f8d08352af0",
    privateKeyPath: join(directory, "worker-key.pk8"),
    runnerImage: `registry.example/pandora-runner@sha256:${"b".repeat(64)}`,
    runnerPolicyHash: "c".repeat(64),
    workerId: "worker-01",
  };
  const payload = {
    schemaVersion: 1,
    audience: "pandora-worker:worker-01",
    organizationId: configuration.organizationId,
    dispatchId: "a6402a8a-4cbb-4812-80be-640028c81c5b",
    planId: "8ec3acda-4fb7-48b2-81f4-6885c005f561",
    repository: "banataosystems/Pandoras-box",
    exactSha: "0123456789abcdef0123456789abcdef01234567",
    jobClass: "node_regression",
    maxRuntimeSeconds: 1800,
    issuedAt: "2026-08-23T15:00:00.000Z",
    expiresAt: "2026-08-23T15:35:00.000Z",
    runnerPolicyHash: configuration.runnerPolicyHash,
    runnerImageDigest: configuration.runnerImage.split("@")[1],
    acquisitionImageDigest: configuration.acquisitionImage.split("@")[1],
    networkPolicy: "none",
    isolation: "hyperv_container",
    productionMutationAllowed: false,
  };
  const digest = await jobDigest(payload);
  const signatureB64 = sign(
    null,
    Buffer.from(`pandora-worker-control-v1|${digest}`),
    controlKeys.privateKey,
  ).toString("base64");
  return {
    configuration,
    workerPrivate,
    job: { digest, payload, signatureB64, redelivery: false },
  };
}

async function requestAuthority() {
  return "eyJhbGciOiJFZERTQSJ9.eyJyb2xlIjoicHJvamVjdG9zX3dvcmtlcl9pbmdlc3QifQ.signature";
}

function response(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function execution(job) {
  return {
    outcome: "completed",
    durationMs: 60_000,
    resultSummary: {
      schemaVersion: 1,
      organizationId: job.payload.organizationId,
      dispatchId: job.payload.dispatchId,
      planId: job.payload.planId,
      workerId: "worker-01",
      jobDigest: job.digest,
      repository: job.payload.repository,
      exactSha: job.payload.exactSha,
      jobClass: job.payload.jobClass,
      outcome: "completed",
      exitCode: 0,
      isolation: "hyperv_container",
      networkPolicy: "none",
      productionMutationAllowed: false,
      runnerPolicyHash: job.payload.runnerPolicyHash,
      runnerImageDigest: job.payload.runnerImageDigest,
      acquisitionImageDigest: job.payload.acquisitionImageDigest,
      sourceTreeSha: "d".repeat(40),
      testsDiscovered: 200,
      startedAt: "2026-08-23T15:00:00.000Z",
      completedAt: "2026-08-23T15:01:00.000Z",
      stdoutSha256: "e".repeat(64),
      stderrSha256: "f".repeat(64),
    },
  };
}

test("worker signs claim and completion while candidate execution sees no host secret", async () => {
  const data = await fixture();
  const requests = [];
  let executionCalls = 0;
  const fetchFn = async (_url, options) => {
    const body = JSON.parse(options.body);
    requests.push(body);
    if (requests.length === 1) {
      validateClaimRequest(body, NOW);
      return response({ ok: true, job: data.job });
    }
    validateCompleteRequest(body, NOW);
    return response({
      ok: true,
      completion: {
        planId: data.job.payload.planId,
        dispatchId: data.job.payload.dispatchId,
        status: "completed",
      },
    });
  };
  const result = await runOnce(data.configuration, {
    privateKeyB64: data.workerPrivate,
    requestAuthority,
    fetchFn,
    now: () => new Date(NOW),
    runVerification: async (job, config, isolationOptions) => {
      executionCalls += 1;
      assert.equal(config.GITHUB_TOKEN, undefined);
      assert.deepEqual(isolationOptions, {});
      return execution(job);
    },
  });
  assert.equal(result.state, "acknowledged");
  assert.equal(executionCalls, 1);
  assert.equal(requests.length, 2);
  assert.equal(requests[0].signatureB64.length, 88);
  assert.equal(requests[1].signatureB64.length, 88);
  const journal = JSON.parse(await readFile(data.configuration.journalPath, "utf8"));
  assert.equal(journal.entries[data.job.digest].state, "acknowledged");
});

test("crash journal blocks duplicate candidate execution", async () => {
  const data = await fixture();
  await writeFile(data.configuration.journalPath, JSON.stringify({
    schemaVersion: 1,
    entries: {
      [data.job.digest]: {
        state: "started",
        dispatchId: data.job.payload.dispatchId,
        planId: data.job.payload.planId,
      },
    },
  }));
  let executionCalls = 0;
  const result = await runOnce(data.configuration, {
    privateKeyB64: data.workerPrivate,
    requestAuthority,
    now: () => new Date(NOW),
    fetchFn: async () => response({ ok: true, job: data.job }),
    runVerification: async () => { executionCalls += 1; },
  });
  assert.equal(result.state, "ambiguous");
  assert.equal(executionCalls, 0);
});

test("overlapping worker invocations claim and execute at most once", async () => {
  const data = await fixture();
  let releaseClaim;
  let signalClaimStarted;
  const claimStarted = new Promise((resolve) => { signalClaimStarted = resolve; });
  const claimBarrier = new Promise((resolve) => { releaseClaim = resolve; });
  let requests = 0;
  let executionCalls = 0;
  const dependencies = {
    privateKeyB64: data.workerPrivate,
    requestAuthority,
    now: () => new Date(NOW),
    fetchFn: async () => {
      requests += 1;
      if (requests === 1) {
        signalClaimStarted();
        await claimBarrier;
        return response({ ok: true, job: data.job });
      }
      return response({
        ok: true,
        completion: {
          planId: data.job.payload.planId,
          dispatchId: data.job.payload.dispatchId,
          status: "completed",
        },
      });
    },
    runVerification: async (job) => {
      executionCalls += 1;
      return execution(job);
    },
  };

  const first = runOnce(data.configuration, dependencies);
  await claimStarted;
  const second = await runOnce(data.configuration, dependencies);
  assert.deepEqual(second, { state: "busy" });
  releaseClaim();
  const completed = await first;
  assert.equal(completed.state, "acknowledged");
  assert.equal(requests, 2);
  assert.equal(executionCalls, 1);
});

test("cleanup failure cannot send or acknowledge a nominally successful completion", async () => {
  const data = await fixture();
  const requests = [];
  let executionCalls = 0;
  await assert.rejects(
    runOnce(data.configuration, {
      privateKeyB64: data.workerPrivate,
      requestAuthority,
      now: () => new Date(NOW),
      fetchFn: async (_url, options) => {
        requests.push(JSON.parse(options.body));
        if (requests.length === 1) {
          return response({ ok: true, job: data.job });
        }
        throw new Error("COMPLETION_MUST_NOT_BE_SENT");
      },
      runVerification: async () => {
        executionCalls += 1;
        throw new Error("ISOLATION_CLEANUP_FAILED");
      },
    }),
    /ISOLATION_CLEANUP_FAILED/,
  );
  assert.equal(executionCalls, 1);
  assert.equal(requests.length, 1);
  const journal = JSON.parse(await readFile(data.configuration.journalPath, "utf8"));
  assert.equal(journal.entries[data.job.digest].state, "started");
});

test("oversized valid journal is rejected before parsing or candidate execution", async () => {
  const data = await fixture();
  const smallValidJournal = JSON.stringify({ schemaVersion: 1, entries: {} });
  await writeFile(
    data.configuration.journalPath,
    `${smallValidJournal}${" ".repeat(MAX_WORKER_JOURNAL_BYTES)}`,
    "utf8",
  );
  let executionCalls = 0;
  let requests = 0;
  await assert.rejects(
    runOnce(data.configuration, {
      privateKeyB64: data.workerPrivate,
      requestAuthority,
      now: () => new Date(NOW),
      fetchFn: async () => {
        requests += 1;
        return response({ ok: true, job: data.job });
      },
      runVerification: async () => {
        executionCalls += 1;
        return execution(data.job);
      },
    }),
    /WORKER_JOURNAL_TOO_LARGE/,
  );
  assert.equal(requests, 1);
  assert.equal(executionCalls, 0);
});

test("worker source has no unsigned local-run or host repository command path", async () => {
  const source = await readFile(
    new URL("../pandora-worker.mjs", import.meta.url),
    "utf8",
  );
  assert.doesNotMatch(source, /local-run|callerCommand|execSync|shell:\s*true/i);
  assert.doesNotMatch(source, /\.\.\.process\.env|process\.env/);
  assert.doesNotMatch(source, /spawn\([^,]*(?:git|npm|node|powershell)/i);
});
