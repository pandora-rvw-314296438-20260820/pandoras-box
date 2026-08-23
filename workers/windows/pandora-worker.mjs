import { randomBytes, randomUUID } from "node:crypto";
import { open, readFile, rename, unlink, writeFile } from "node:fs/promises";
import { pathToFileURL } from "node:url";
import {
  signClaimRequest,
  signCompleteRequest,
  strictConfig,
  verifyControlJob,
} from "./job-contract.mjs";
import { runIsolatedVerification } from "./isolation-policy.mjs";
import { resultEvidenceHash } from "../../supabase/functions/pandora-worker-dispatch/contract.mjs";

const DEFAULT_CONFIG_PATH = "C:\\ProgramData\\PandoraWorker\\worker-config.json";
const MAX_GATEWAY_RESPONSE_BYTES = 128 * 1024;
const MAX_AUTHORITY_RESPONSE_BYTES = 16 * 1024;
const MAX_WORKER_JOURNAL_BYTES = 1024 * 1024;

function nonce() {
  return randomBytes(24).toString("base64url");
}

async function loadJson(path, fallback) {
  try {
    const parsed = JSON.parse(await readFile(path, "utf8"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed
      : fallback;
  } catch (error) {
    if (error?.code === "ENOENT") return fallback;
    throw error;
  }
}

async function loadJournal(path, fallback) {
  let handle;
  try {
    handle = await open(path, "r");
  } catch (error) {
    if (error?.code === "ENOENT") return fallback;
    throw error;
  }

  try {
    const metadata = await handle.stat();
    if (!metadata.isFile()) throw new Error("WORKER_JOURNAL_INVALID");
    if (metadata.size > MAX_WORKER_JOURNAL_BYTES) {
      throw new Error("WORKER_JOURNAL_TOO_LARGE");
    }

    // Read at most one byte beyond the accepted limit. The second check closes
    // the stat/read race if another process grows the journal after stat().
    const buffer = Buffer.allocUnsafe(MAX_WORKER_JOURNAL_BYTES + 1);
    let totalBytes = 0;
    while (totalBytes < buffer.length) {
      const { bytesRead } = await handle.read(
        buffer,
        totalBytes,
        buffer.length - totalBytes,
        null,
      );
      if (bytesRead === 0) break;
      totalBytes += bytesRead;
    }
    if (totalBytes > MAX_WORKER_JOURNAL_BYTES) {
      throw new Error("WORKER_JOURNAL_TOO_LARGE");
    }

    const parsed = JSON.parse(buffer.subarray(0, totalBytes).toString("utf8"));
    return parsed && typeof parsed === "object" && !Array.isArray(parsed)
      ? parsed
      : fallback;
  } finally {
    await handle.close();
  }
}

async function writeJournal(path, journal) {
  const serialized = JSON.stringify(journal);
  const contents = `${serialized}\n`;
  if (Buffer.byteLength(contents, "utf8") > MAX_WORKER_JOURNAL_BYTES) {
    throw new Error("WORKER_JOURNAL_TOO_LARGE");
  }
  const temporary = `${path}.${process.pid}.${randomUUID()}.tmp`;
  await writeFile(temporary, contents, { encoding: "utf8", mode: 0o600 });
  await rename(temporary, path);
}

async function acquireProcessLock(path, now) {
  let handle;
  try {
    handle = await open(path, "wx", 0o600);
  } catch (error) {
    if (error?.code === "EEXIST") return null;
    throw error;
  }
  try {
    await handle.writeFile(`${JSON.stringify({
      schemaVersion: 1,
      pid: process.pid,
      acquiredAt: now().toISOString(),
    })}\n`, "utf8");
    await handle.sync();
    return handle;
  } catch (error) {
    await handle.close().catch(() => {});
    await unlink(path).catch(() => {});
    throw error;
  }
}

async function releaseProcessLock(path, handle) {
  await handle.close();
  await unlink(path);
}

async function workerAuthorityRequest(configuration, payload, fetchFn = fetch) {
  const response = await fetchFn(configuration.authorityUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      "user-agent": "Pandora-Worker-01/1.0",
    },
    body: JSON.stringify(payload),
    redirect: "error",
    signal: AbortSignal.timeout(10_000),
  });
  const declared = Number(response.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_AUTHORITY_RESPONSE_BYTES) {
    throw new Error("WORKER_AUTHORITY_RESPONSE_TOO_LARGE");
  }
  const text = await response.text();
  if (Buffer.byteLength(text, "utf8") > MAX_AUTHORITY_RESPONSE_BYTES) {
    throw new Error("WORKER_AUTHORITY_RESPONSE_TOO_LARGE");
  }
  let decoded;
  try {
    decoded = JSON.parse(text);
  } catch {
    throw new Error("WORKER_AUTHORITY_RESPONSE_INVALID");
  }
  if (
    !response.ok || !decoded || typeof decoded !== "object" || Array.isArray(decoded) ||
    Object.keys(decoded).sort().join("|") !== "authorityToken|schemaVersion" ||
    decoded.schemaVersion !== 1 ||
    !/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(
      decoded.authorityToken || "",
    )
  ) {
    throw new Error("WORKER_AUTHORITY_REQUEST_REJECTED");
  }
  return decoded.authorityToken;
}

async function gatewayRequest(
  configuration,
  payload,
  authorityToken,
  fetchFn = fetch,
) {
  if (!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(authorityToken || "")) {
    throw new Error("WORKER_AUTHORITY_TOKEN_REQUIRED");
  }
  const response = await fetchFn(configuration.gatewayUrl, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      accept: "application/json",
      "user-agent": "Pandora-Worker-01/1.0",
      authorization: `Bearer ${authorityToken}`,
    },
    body: JSON.stringify(payload),
    redirect: "error",
    signal: AbortSignal.timeout(30_000),
  });
  const declared = Number(response.headers.get("content-length") || "0");
  if (Number.isFinite(declared) && declared > MAX_GATEWAY_RESPONSE_BYTES) {
    throw new Error("WORKER_GATEWAY_RESPONSE_TOO_LARGE");
  }
  const text = await response.text();
  if (Buffer.byteLength(text, "utf8") > MAX_GATEWAY_RESPONSE_BYTES) {
    throw new Error("WORKER_GATEWAY_RESPONSE_TOO_LARGE");
  }
  let decoded;
  try {
    decoded = JSON.parse(text);
  } catch {
    throw new Error("WORKER_GATEWAY_RESPONSE_INVALID");
  }
  if (!response.ok || decoded?.ok !== true) {
    throw new Error("WORKER_GATEWAY_REQUEST_REJECTED");
  }
  return decoded;
}

function baseRequest(configuration, action, now) {
  return {
    schemaVersion: 1,
    action,
    organizationId: configuration.organizationId,
    workerId: configuration.workerId,
    requestId: randomUUID(),
    nonce: nonce(),
    timestamp: now.toISOString(),
  };
}

function claimRequest(configuration, privateKeyB64, now = new Date()) {
  const unsigned = baseRequest(configuration, "claim", now);
  return {
    ...unsigned,
    signatureB64: signClaimRequest(privateKeyB64, unsigned),
  };
}

async function completeRequest(
  configuration,
  privateKeyB64,
  job,
  execution,
  now = new Date(),
) {
  const evidenceSha256 = await resultEvidenceHash(execution.resultSummary);
  const unsigned = {
    ...baseRequest(configuration, "complete", now),
    dispatchId: job.payload.dispatchId,
    planId: job.payload.planId,
    outcome: execution.outcome,
    durationMs: execution.durationMs,
    jobDigest: job.digest,
    evidenceSha256,
    resultSummary: execution.resultSummary,
  };
  return {
    ...unsigned,
    signatureB64: signCompleteRequest(privateKeyB64, unsigned),
  };
}

async function runOnce(rawConfiguration, dependencies = {}) {
  const configuration = strictConfig(rawConfiguration);
  const fetchFn = dependencies.fetchFn || fetch;
  const requestAuthority = dependencies.requestAuthority || workerAuthorityRequest;
  const authorityFetchFn = dependencies.authorityFetchFn || fetch;
  const runVerification = dependencies.runVerification || runIsolatedVerification;
  const now = dependencies.now || (() => new Date());
  const processLockPath = `${configuration.journalPath}.process.lock`;
  const processLock = await acquireProcessLock(processLockPath, now);
  if (!processLock) return { state: "busy" };

  try {
    const privateKeyB64 = (dependencies.privateKeyB64 ||
      await readFile(configuration.privateKeyPath, "utf8")).trim();

    const signedClaim = claimRequest(configuration, privateKeyB64, now());
    const claimAuthority = await requestAuthority(
      configuration,
      signedClaim,
      authorityFetchFn,
    );
    const claim = await gatewayRequest(
      configuration,
      signedClaim,
      claimAuthority,
      fetchFn,
    );
    if (!claim.job) return { state: "idle" };
    const job = await verifyControlJob(claim.job, configuration, now());

    const journal = await loadJournal(configuration.journalPath, {
      schemaVersion: 1,
      entries: {},
    });
    if (journal.schemaVersion !== 1 || !journal.entries || typeof journal.entries !== "object") {
      throw new Error("WORKER_JOURNAL_INVALID");
    }
    const existing = journal.entries[job.digest];
    if (existing?.state === "acknowledged") {
      return { state: "acknowledged", jobDigest: job.digest };
    }
    if (existing?.state === "started") {
      // Candidate execution may already have occurred. Never run it again.
      return { state: "ambiguous", jobDigest: job.digest };
    }

    let execution = existing?.state === "completed" ? existing.execution : null;
    if (!execution) {
      journal.entries[job.digest] = {
        state: "started",
        dispatchId: job.payload.dispatchId,
        planId: job.payload.planId,
        exactSha: job.payload.exactSha,
        startedAt: now().toISOString(),
      };
      await writeJournal(configuration.journalPath, journal);
      execution = await runVerification(job, configuration, dependencies.isolationOptions || {});
      journal.entries[job.digest] = {
        ...journal.entries[job.digest],
        state: "completed",
        execution,
        completedAt: now().toISOString(),
      };
      await writeJournal(configuration.journalPath, journal);
    }

    let completion = journal.entries[job.digest].completionRequest;
    if (!completion) {
      completion = await completeRequest(
        configuration,
        privateKeyB64,
        job,
        execution,
        now(),
      );
      journal.entries[job.digest] = {
        ...journal.entries[job.digest],
        completionRequest: completion,
      };
      await writeJournal(configuration.journalPath, journal);
    }
    const completionAuthority = await requestAuthority(
      configuration,
      completion,
      authorityFetchFn,
    );
    const acknowledged = await gatewayRequest(
      configuration,
      completion,
      completionAuthority,
      fetchFn,
    );
    if (
      acknowledged.completion?.planId !== job.payload.planId ||
      acknowledged.completion?.dispatchId !== job.payload.dispatchId
    ) {
      throw new Error("WORKER_COMPLETION_READBACK_MISMATCH");
    }
    journal.entries[job.digest] = {
      ...journal.entries[job.digest],
      state: "acknowledged",
      acknowledgedAt: now().toISOString(),
    };
    await writeJournal(configuration.journalPath, journal);
    return {
      state: "acknowledged",
      jobDigest: job.digest,
      evidenceSha256: completion.evidenceSha256,
    };
  } finally {
    await releaseProcessLock(processLockPath, processLock);
  }
}

async function main() {
  if (process.platform !== "win32") {
    throw new Error("WINDOWS_WORKER_REQUIRED");
  }
  if (process.argv.length > 4 || ![undefined, "--once"].includes(process.argv[2])) {
    throw new Error("WORKER_ARGUMENTS_INVALID");
  }
  const configPath = process.argv[3] || DEFAULT_CONFIG_PATH;
  if (
    !/^C:\\ProgramData\\PandoraWorker\\[A-Za-z0-9._-]+\.json$/i.test(configPath)
  ) {
    throw new Error("WORKER_CONFIG_PATH_INVALID");
  }
  const configuration = await loadJson(configPath, null);
  if (!configuration) throw new Error("WORKER_CONFIG_NOT_FOUND");
  const result = await runOnce(configuration);
  process.stdout.write(`${JSON.stringify(result)}\n`);
}

if (import.meta.url === pathToFileURL(process.argv[1] || "").href) {
  main().catch((error) => {
    process.stderr.write(`${error instanceof Error ? error.message : "WORKER_FAILED"}\n`);
    process.exitCode = 1;
  });
}

export {
  MAX_WORKER_JOURNAL_BYTES,
  claimRequest,
  completeRequest,
  gatewayRequest,
  runOnce,
  workerAuthorityRequest,
};
