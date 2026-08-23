import assert from "node:assert/strict";
import { EventEmitter } from "node:events";
import { PassThrough } from "node:stream";
import test from "node:test";
import {
  DOCKER_EXE,
  dockerChildEnvironment,
  runIsolatedVerification,
} from "../isolation-policy.mjs";

function fakeDocker(
  calls,
  runtime = "windows|Microsoft Windows Server",
  behavior = {},
) {
  return (executable, args, options) => {
    calls.push({ executable, args: [...args], options });
    const child = new EventEmitter();
    child.stdout = new PassThrough();
    child.stderr = new PassThrough();
    child.kill = () => {};
    queueMicrotask(() => {
      let output = "";
      let exitCode = 0;
      if (args[0] === "info") output = `${runtime}\n`;
      if (args.includes("acquire-source")) {
        output = `PANDORA_ACQUISITION_RESULT=${JSON.stringify({
          exactSha: "0123456789abcdef0123456789abcdef01234567",
          sourceTreeSha: "d".repeat(40),
        })}\n`;
      }
      if (args.includes("run-verification")) {
        output = `PANDORA_RUN_RESULT=${JSON.stringify({
          testsDiscovered: 200,
          networkPolicy: "none",
          isolation: "hyperv_container",
        })}\n`;
      }
      if (args[0] === "ps" && behavior.remainingContainer) {
        const containerRun = calls.find((call) => call.args[0] === "run");
        const target = containerRun?.args[containerRun.args.indexOf("--name") + 1];
        if (target) output = `${target}\n`;
      }
      if (args[0] === "volume" && args[1] === "ls" && behavior.remainingVolume) {
        const volumeCreate = calls.find((call) =>
          call.args[0] === "volume" && call.args[1] === "create"
        );
        const target = volumeCreate?.args.at(-1);
        if (target) output = `${target}\n`;
      }
      if (
        behavior.cleanupReadbackFailure &&
        (args[0] === "ps" || (args[0] === "volume" && args[1] === "ls"))
      ) {
        exitCode = 1;
      }
      child.stdout.end(output);
      child.stderr.end("");
      child.emit("close", exitCode);
    });
    return child;
  };
}

function job() {
  return {
    digest: "e".repeat(64),
    payload: {
      organizationId: "2270b266-59da-4c39-bfd9-9f8d08352af0",
      dispatchId: "a6402a8a-4cbb-4812-80be-640028c81c5b",
      planId: "8ec3acda-4fb7-48b2-81f4-6885c005f561",
      repository: "banataosystems/Pandoras-box",
      exactSha: "0123456789abcdef0123456789abcdef01234567",
      jobClass: "node_regression",
      maxRuntimeSeconds: 1800,
      runnerPolicyHash: "c".repeat(64),
      runnerImageDigest: `sha256:${"b".repeat(64)}`,
      acquisitionImageDigest: `sha256:${"a".repeat(64)}`,
    },
  };
}

const configuration = {
  workerId: "worker-01",
  acquisitionImage: `registry.example/pandora-acquire@sha256:${"a".repeat(64)}`,
  runnerImage: `registry.example/pandora-runner@sha256:${"b".repeat(64)}`,
};

test("candidate verification uses only digest-pinned Hyper-V containers", async () => {
  const calls = [];
  const result = await runIsolatedVerification(job(), configuration, {
    spawnFn: fakeDocker(calls),
  });
  assert.equal(result.outcome, "completed");
  assert.equal(result.resultSummary.testsDiscovered, 200);
  assert.ok(calls.every((call) => call.executable === DOCKER_EXE));
  assert.ok(calls.every((call) => call.options.shell === false));
  assert.ok(calls.every((call) => !Object.keys(call.options.env).some((key) =>
    /TOKEN|SECRET|KEY|PASSWORD|HOME|USERPROFILE/i.test(key)
  )));

  const acquisition = calls.find((call) => call.args.includes("acquire-source"));
  const runner = calls.find((call) => call.args.includes("run-verification"));
  assert.ok(acquisition.args.includes("--isolation=hyperv"));
  assert.ok(acquisition.args.includes("--network=nat"));
  assert.ok(runner.args.includes("--isolation=hyperv"));
  assert.ok(runner.args.includes("--network=none"));
  assert.ok(runner.args.includes(configuration.runnerImage));
  assert.ok(acquisition.args.includes(configuration.acquisitionImage));
  assert.equal(calls.some((call) => call.args.some((value) =>
    /^(git|npm|node|powershell(?:\.exe)?)$/i.test(value)
  )), false);
  assert.equal(calls.some((call) => call.args.some((value) =>
    /type=bind|docker\.sock|\\\.\\pipe/i.test(value)
  )), false);
});

test("host child environment is a fixed allowlist with no inherited secrets", () => {
  const environment = dockerChildEnvironment();
  assert.deepEqual(Object.keys(environment).sort(), [
    "DOCKER_CONTENT_TRUST",
    "PATH",
    "SystemDrive",
    "SystemRoot",
    "WINDIR",
  ]);
  assert.equal(environment.HOME, undefined);
  assert.equal(environment.GITHUB_TOKEN, undefined);
});

test("non-Windows container runtime fails before source acquisition", async () => {
  const calls = [];
  await assert.rejects(
    runIsolatedVerification(job(), configuration, {
      spawnFn: fakeDocker(calls, "linux|Docker Desktop"),
    }),
    /HYPERV_WINDOWS_CONTAINER_RUNTIME_REQUIRED/,
  );
  assert.equal(calls.some((call) => call.args.includes("acquire-source")), false);
});

for (const [resource, behavior] of [
  ["container", { remainingContainer: true }],
  ["volume", { remainingVolume: true }],
]) {
  test(`successful candidate result fails closed when cleanup leaves a ${resource}`, async () => {
    const calls = [];
    await assert.rejects(
      runIsolatedVerification(job(), configuration, {
        spawnFn: fakeDocker(calls, undefined, behavior),
      }),
      /ISOLATION_CLEANUP_FAILED/,
    );
    assert.equal(calls.some((call) => call.args.includes("run-verification")), true);
    assert.equal(calls.filter((call) => call.args[0] === "rm").length, 2);
    assert.equal(calls.filter((call) =>
      call.args[0] === "volume" && call.args[1] === "rm"
    ).length, 2);
  });
}

test("successful candidate result fails closed when cleanup readback is unavailable", async () => {
  const calls = [];
  await assert.rejects(
    runIsolatedVerification(job(), configuration, {
      spawnFn: fakeDocker(calls, undefined, { cleanupReadbackFailure: true }),
    }),
    /ISOLATION_CLEANUP_FAILED/,
  );
  assert.equal(calls.some((call) => call.args.includes("run-verification")), true);
});
