import { createHash, randomUUID } from "node:crypto";
import { spawn } from "node:child_process";

const DOCKER_EXE = "C:\\Program Files\\Docker\\Docker\\resources\\bin\\docker.exe";
const MAX_OUTPUT_BYTES = 1024 * 1024;

function dockerChildEnvironment() {
  return Object.freeze({
    PATH: "C:\\Windows\\System32;C:\\Program Files\\Docker\\Docker\\resources\\bin",
    SystemDrive: "C:",
    SystemRoot: "C:\\Windows",
    WINDIR: "C:\\Windows",
    DOCKER_CONTENT_TRUST: "1",
  });
}

function safeDispatchId(value) {
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error("INVALID_DISPATCH_ID");
  }
  return value.toLowerCase();
}

function sha256(value) {
  return createHash("sha256").update(value).digest("hex");
}

function runDocker(args, options = {}) {
  const spawnFn = options.spawnFn || spawn;
  const timeoutMs = options.timeoutMs || 60_000;
  return new Promise((resolve, reject) => {
    const child = spawnFn(DOCKER_EXE, args, {
      shell: false,
      windowsHide: true,
      env: dockerChildEnvironment(),
      stdio: ["ignore", "pipe", "pipe"],
    });
    let stdout = Buffer.alloc(0);
    let stderr = Buffer.alloc(0);
    let overflow = false;
    const append = (current, chunk) => {
      const next = Buffer.concat([current, Buffer.from(chunk)]);
      if (next.length > MAX_OUTPUT_BYTES) {
        overflow = true;
        child.kill();
        return next.subarray(0, MAX_OUTPUT_BYTES);
      }
      return next;
    };
    child.stdout?.on("data", (chunk) => { stdout = append(stdout, chunk); });
    child.stderr?.on("data", (chunk) => { stderr = append(stderr, chunk); });
    const timeout = setTimeout(() => {
      child.kill();
      reject(new Error("DOCKER_OPERATION_TIMEOUT"));
    }, timeoutMs);
    child.once("error", (error) => {
      clearTimeout(timeout);
      reject(new Error(`DOCKER_OPERATION_FAILED:${error.name}`));
    });
    child.once("close", (code) => {
      clearTimeout(timeout);
      if (overflow) {
        reject(new Error("DOCKER_OUTPUT_LIMIT_EXCEEDED"));
        return;
      }
      resolve({
        code: Number.isInteger(code) ? code : 255,
        stdout,
        stderr,
      });
    });
  });
}

function parseTrustedResult(stdout, marker) {
  const lines = stdout.toString("utf8").split(/\r?\n/).filter(Boolean);
  const marked = lines.filter((line) => line.startsWith(marker));
  if (marked.length !== 1 || marked[0] !== lines.at(-1)) {
    throw new Error("TRUSTED_RUNNER_RESULT_MISSING");
  }
  try {
    const decoded = JSON.parse(marked[0].slice(marker.length));
    if (!decoded || typeof decoded !== "object" || Array.isArray(decoded)) {
      throw new Error("invalid");
    }
    return decoded;
  } catch {
    throw new Error("TRUSTED_RUNNER_RESULT_INVALID");
  }
}

function containerNames(dispatchId) {
  const safe = safeDispatchId(dispatchId).replaceAll("-", "");
  const suffix = randomUUID().replaceAll("-", "").slice(0, 8);
  return {
    acquisition: `pandora-acquire-${safe}-${suffix}`,
    runner: `pandora-run-${safe}-${suffix}`,
    workspaceVolume: `pandora-work-${safe}-${suffix}`,
    tempVolume: `pandora-temp-${safe}-${suffix}`,
  };
}

function commonIsolationArgs(name, network, memory, cpu) {
  return [
    "run",
    "--name", name,
    "--isolation=hyperv",
    `--network=${network}`,
    "--read-only",
    "--user", "ContainerUser",
    "--memory", memory,
    "--cpus", cpu,
    "--pids-limit", "256",
  ];
}

async function assertHyperVContainerRuntime(options = {}) {
  const result = await runDocker(
    ["info", "--format", "{{.OSType}}|{{.OperatingSystem}}"],
    { ...options, timeoutMs: 30_000 },
  );
  const identity = result.stdout.toString("utf8").trim().toLowerCase();
  if (result.code !== 0 || !identity.startsWith("windows|")) {
    throw new Error("HYPERV_WINDOWS_CONTAINER_RUNTIME_REQUIRED");
  }
  return identity;
}

async function cleanup(names, options) {
  const operations = [
    ["rm", "--force", names.acquisition],
    ["rm", "--force", names.runner],
    ["volume", "rm", "--force", names.workspaceVolume],
    ["volume", "rm", "--force", names.tempVolume],
  ];
  for (const args of operations) {
    try {
      await runDocker(args, { ...options, timeoutMs: 30_000 });
    } catch {
      // Continue through every scoped removal, then verify the final state.
      // A failed command can still have removed its target before disconnecting.
    }
  }

  const absenceChecks = [
    {
      args: ["ps", "--all", "--format", "{{.Names}}"],
      targets: [names.acquisition, names.runner],
    },
    {
      args: ["volume", "ls", "--format", "{{.Name}}"],
      targets: [names.workspaceVolume, names.tempVolume],
    },
  ];

  let cleanupVerified = true;
  for (const check of absenceChecks) {
    try {
      const observed = await runDocker(check.args, {
        ...options,
        timeoutMs: 30_000,
      });
      const remaining = observed.stdout
        .toString("utf8")
        .split(/\r?\n/)
        .filter(Boolean);
      if (
        observed.code !== 0 ||
        check.targets.some((target) => remaining.includes(target))
      ) {
        cleanupVerified = false;
      }
    } catch {
      cleanupVerified = false;
    }
  }

  if (!cleanupVerified) {
    throw new Error("ISOLATION_CLEANUP_FAILED");
  }
}

async function runIsolatedVerification(job, configuration, options = {}) {
  const payload = job.payload;
  const names = containerNames(payload.dispatchId);
  const startedAt = new Date();
  await assertHyperVContainerRuntime(options);
  try {
    for (const volume of [names.workspaceVolume, names.tempVolume]) {
      const created = await runDocker(
        ["volume", "create", "--label", `pandora.dispatch=${payload.dispatchId}`, volume],
        { ...options, timeoutMs: 30_000 },
      );
      if (created.code !== 0) throw new Error("ISOLATION_VOLUME_CREATE_FAILED");
    }

    const acquisition = await runDocker([
      ...commonIsolationArgs(names.acquisition, "nat", "2g", "2"),
      "--mount", `type=volume,source=${names.workspaceVolume},target=C:\\workspace`,
      "--mount", `type=volume,source=${names.tempVolume},target=C:\\Temp`,
      "--env", "PANDORA_ACQUISITION_MODE=public_exact_sha",
      configuration.acquisitionImage,
      "acquire-source",
      "--repository", payload.repository,
      "--exact-sha", payload.exactSha,
      "--workspace", "C:\\workspace",
    ], { ...options, timeoutMs: Math.min(600_000, payload.maxRuntimeSeconds * 1000) });
    if (acquisition.code !== 0) throw new Error("SOURCE_ACQUISITION_FAILED");
    const acquired = parseTrustedResult(
      acquisition.stdout,
      "PANDORA_ACQUISITION_RESULT=",
    );
    if (
      acquired.exactSha !== payload.exactSha ||
      !/^[0-9a-f]{40}$/.test(acquired.sourceTreeSha)
    ) {
      throw new Error("SOURCE_ACQUISITION_IDENTITY_MISMATCH");
    }

    const execution = await runDocker([
      ...commonIsolationArgs(names.runner, "none", "4g", "2"),
      "--mount", `type=volume,source=${names.workspaceVolume},target=C:\\workspace`,
      "--mount", `type=volume,source=${names.tempVolume},target=C:\\Temp`,
      "--env", "PANDORA_NETWORK_POLICY=none",
      "--env", "PANDORA_PRODUCTION_MUTATION_ALLOWED=false",
      configuration.runnerImage,
      "run-verification",
      "--job-class", payload.jobClass,
      "--workspace", "C:\\workspace",
    ], { ...options, timeoutMs: payload.maxRuntimeSeconds * 1000 });
    const runner = parseTrustedResult(execution.stdout, "PANDORA_RUN_RESULT=");
    if (
      !Number.isInteger(runner.testsDiscovered) || runner.testsDiscovered < 0 ||
      runner.networkPolicy !== "none" || runner.isolation !== "hyperv_container"
    ) {
      throw new Error("RUNNER_EVIDENCE_INVALID");
    }
    const outcome = execution.code === 0 && runner.testsDiscovered > 0
      ? "completed"
      : "failed";
    const completedAt = new Date();
    return {
      outcome,
      durationMs: Math.max(0, completedAt.getTime() - startedAt.getTime()),
      resultSummary: {
        schemaVersion: 1,
        organizationId: payload.organizationId,
        dispatchId: payload.dispatchId,
        planId: payload.planId,
        workerId: configuration.workerId,
        jobDigest: job.digest,
        repository: payload.repository,
        exactSha: payload.exactSha,
        jobClass: payload.jobClass,
        outcome,
        exitCode: execution.code,
        isolation: "hyperv_container",
        networkPolicy: "none",
        productionMutationAllowed: false,
        runnerPolicyHash: payload.runnerPolicyHash,
        runnerImageDigest: payload.runnerImageDigest,
        acquisitionImageDigest: payload.acquisitionImageDigest,
        sourceTreeSha: acquired.sourceTreeSha,
        testsDiscovered: runner.testsDiscovered,
        startedAt: startedAt.toISOString(),
        completedAt: completedAt.toISOString(),
        stdoutSha256: sha256(execution.stdout),
        stderrSha256: sha256(execution.stderr),
      },
    };
  } finally {
    await cleanup(names, options);
  }
}

export {
  DOCKER_EXE,
  assertHyperVContainerRuntime,
  dockerChildEnvironment,
  runIsolatedVerification,
};
