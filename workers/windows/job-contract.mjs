import {
  createPrivateKey,
  createPublicKey,
  sign as nodeSign,
  verify as nodeVerify,
} from "node:crypto";
import {
  claimSignatureBasis,
  completeSignatureBasis,
  jobDigest,
  validateJobPayload,
} from "../../supabase/functions/pandora-worker-dispatch/contract.mjs";

const ED25519_SPKI_PREFIX = Buffer.from("302a300506032b6570032100", "hex");

function strictConfig(value) {
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    throw new Error("INVALID_WORKER_CONFIG");
  }
  const required = [
    "acquisitionImage",
    "authorityUrl",
    "controlPublicKeyB64",
    "gatewayUrl",
    "journalPath",
    "organizationId",
    "privateKeyPath",
    "runnerImage",
    "runnerPolicyHash",
    "workerId",
  ];
  const keys = Object.keys(value).sort();
  if (
    keys.length !== required.length ||
    !keys.every((key, index) => key === [...required].sort()[index]) ||
    value.gatewayUrl !==
      "https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-worker-dispatch" ||
    !isExternalAuthorityUrl(value.authorityUrl) ||
    !/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(value.organizationId) ||
    !/^[a-z0-9][a-z0-9._:-]{2,127}$/.test(value.workerId) ||
    !/^[A-Za-z0-9+/]{43}=$/.test(value.controlPublicKeyB64) ||
    !/^[0-9a-f]{64}$/.test(value.runnerPolicyHash) ||
    !/^[a-z0-9./_-]+@sha256:[0-9a-f]{64}$/.test(value.runnerImage) ||
    !/^[a-z0-9./_-]+@sha256:[0-9a-f]{64}$/.test(value.acquisitionImage) ||
    typeof value.privateKeyPath !== "string" ||
    typeof value.journalPath !== "string"
  ) {
    throw new Error("INVALID_WORKER_CONFIG");
  }
  return Object.freeze({ ...value });
}

function isExternalAuthorityUrl(value) {
  try {
    const parsed = new URL(value);
    return parsed.protocol === "https:" && !parsed.username && !parsed.password &&
      !parsed.hash && !/(?:^|\.)supabase\.co$/i.test(parsed.hostname) &&
      !/(?:^|\.)vercel\.(?:app|com)$/i.test(parsed.hostname);
  } catch {
    return false;
  }
}

function rawEd25519PublicKey(rawBase64) {
  const raw = Buffer.from(rawBase64, "base64");
  if (raw.length !== 32) throw new Error("INVALID_CONTROL_PUBLIC_KEY");
  return createPublicKey({
    key: Buffer.concat([ED25519_SPKI_PREFIX, raw]),
    format: "der",
    type: "spki",
  });
}

async function verifyControlJob(job, configuration, now = new Date()) {
  if (
    !job || typeof job !== "object" || Array.isArray(job) ||
    !/^[0-9a-f]{64}$/.test(job.digest) ||
    !/^[A-Za-z0-9+/]{86}==$/.test(job.signatureB64)
  ) {
    throw new Error("INVALID_CONTROL_JOB");
  }
  const payload = validateJobPayload(job.payload);
  const expectedDigest = await jobDigest(payload);
  if (
    expectedDigest !== job.digest ||
    payload.audience !== `pandora-worker:${configuration.workerId}` ||
    payload.organizationId !== configuration.organizationId ||
    payload.runnerPolicyHash !== configuration.runnerPolicyHash ||
    payload.runnerImageDigest !== configuration.runnerImage.split("@")[1] ||
    payload.acquisitionImageDigest !== configuration.acquisitionImage.split("@")[1] ||
    Date.parse(payload.issuedAt) > now.getTime() + 60_000 ||
    Date.parse(payload.expiresAt) <= now.getTime()
  ) {
    throw new Error("CONTROL_JOB_BINDING_MISMATCH");
  }
  const verified = nodeVerify(
    null,
    Buffer.from(`pandora-worker-control-v1|${job.digest}`, "utf8"),
    rawEd25519PublicKey(configuration.controlPublicKeyB64),
    Buffer.from(job.signatureB64, "base64"),
  );
  if (!verified) throw new Error("CONTROL_JOB_SIGNATURE_INVALID");
  return Object.freeze({ digest: job.digest, payload });
}

function privateKeyFromPkcs8Base64(value) {
  const decoded = Buffer.from(value.trim(), "base64");
  if (decoded.length < 48 || decoded.length > 256) {
    throw new Error("INVALID_WORKER_PRIVATE_KEY");
  }
  try {
    return createPrivateKey({ key: decoded, format: "der", type: "pkcs8" });
  } catch {
    throw new Error("INVALID_WORKER_PRIVATE_KEY");
  }
}

function signBasis(privateKeyB64, basis) {
  return nodeSign(
    null,
    Buffer.from(basis, "utf8"),
    privateKeyFromPkcs8Base64(privateKeyB64),
  ).toString("base64");
}

function signClaimRequest(privateKeyB64, request) {
  return signBasis(privateKeyB64, claimSignatureBasis(request));
}

function signCompleteRequest(privateKeyB64, request) {
  return signBasis(privateKeyB64, completeSignatureBasis(request));
}

export {
  signClaimRequest,
  signCompleteRequest,
  strictConfig,
  verifyControlJob,
};
