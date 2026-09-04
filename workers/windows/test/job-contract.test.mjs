import assert from "node:assert/strict";
import { generateKeyPairSync, sign } from "node:crypto";
import test from "node:test";
import { jobDigest } from "../../../supabase/functions/pandora-worker-dispatch/contract.mjs";
import { strictConfig, verifyControlJob } from "../job-contract.mjs";

function configuration(publicKeyB64) {
  return {
    acquisitionImage: `registry.example/pandora-acquire@sha256:${"a".repeat(64)}`,
    authorityUrl: "https://worker-authority.example/v1/authorize",
    controlPublicKeyB64: publicKeyB64,
    gatewayUrl:
      "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-worker-dispatch",
    journalPath: "C:\\ProgramData\\PandoraWorker\\journal.json",
    organizationId: "2270b266-59da-4c39-bfd9-9f8d08352af0",
    privateKeyPath: "C:\\ProgramData\\PandoraWorker\\worker-key.pk8",
    runnerImage: `registry.example/pandora-runner@sha256:${"b".repeat(64)}`,
    runnerPolicyHash: "c".repeat(64),
    workerId: "worker-01",
  };
}

function payload() {
  return {
    schemaVersion: 1,
    audience: "pandora-worker:worker-01",
    organizationId: "2270b266-59da-4c39-bfd9-9f8d08352af0",
    dispatchId: "a6402a8a-4cbb-4812-80be-640028c81c5b",
    planId: "8ec3acda-4fb7-48b2-81f4-6885c005f561",
    repository: "pandora-rvw-314296438-20260820/pandoras-box",
    exactSha: "0123456789abcdef0123456789abcdef01234567",
    jobClass: "node_regression",
    maxRuntimeSeconds: 1800,
    issuedAt: "2026-08-23T15:00:00.000Z",
    expiresAt: "2026-08-23T15:35:00.000Z",
    runnerPolicyHash: "c".repeat(64),
    runnerImageDigest: `sha256:${"b".repeat(64)}`,
    acquisitionImageDigest: `sha256:${"a".repeat(64)}`,
    networkPolicy: "none",
    isolation: "hyperv_container",
    productionMutationAllowed: false,
  };
}

test("control job verifies Ed25519 signature and every local pin", async () => {
  const { privateKey, publicKey } = generateKeyPairSync("ed25519");
  const rawPublic = publicKey.export({ format: "der", type: "spki" }).subarray(-32);
  const config = strictConfig(configuration(rawPublic.toString("base64")));
  const body = payload();
  const digest = await jobDigest(body);
  const signatureB64 = sign(
    null,
    Buffer.from(`pandora-worker-control-v1|${digest}`),
    privateKey,
  ).toString("base64");
  const verified = await verifyControlJob(
    { digest, payload: body, signatureB64 },
    config,
    new Date("2026-08-23T15:01:00.000Z"),
  );
  assert.equal(verified.digest, digest);

  await assert.rejects(
    verifyControlJob(
      { digest, payload: { ...body, exactSha: "f".repeat(40) }, signatureB64 },
      config,
      new Date("2026-08-23T15:01:00.000Z"),
    ),
    /CONTROL_JOB_BINDING_MISMATCH/,
  );
  await assert.rejects(
    verifyControlJob(
      { digest, payload: body, signatureB64: Buffer.alloc(64).toString("base64") },
      config,
      new Date("2026-08-23T15:01:00.000Z"),
    ),
    /CONTROL_JOB_SIGNATURE_INVALID/,
  );
});

test("configuration rejects moving images, alternate gateway, and unknown fields", () => {
  const publicKey = Buffer.alloc(32, 1).toString("base64");
  assert.throws(
    () => strictConfig({ ...configuration(publicKey), runnerImage: "node:24" }),
    /INVALID_WORKER_CONFIG/,
  );
  assert.throws(
    () => strictConfig({ ...configuration(publicKey), gatewayUrl: "https://evil.example" }),
    /INVALID_WORKER_CONFIG/,
  );
  assert.throws(
    () => strictConfig({ ...configuration(publicKey), authorityUrl: "https://mcpmaster.vercel.app/worker" }),
    /INVALID_WORKER_CONFIG/,
  );
  assert.throws(
    () => strictConfig({ ...configuration(publicKey), localRun: true }),
    /INVALID_WORKER_CONFIG/,
  );
});
