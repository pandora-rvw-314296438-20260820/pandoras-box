import { resolveBuildAdapter } from '../adapters/adapter-registry.mjs';
import { collectArtifacts } from '../artifacts/artifact-collector.mjs';
import { validateSafeGeneratedConfig } from '../config/safe-generated-config.mjs';
import { assertWorkerCAuthorization } from '../contracts/authorized-build-request.mjs';
import { validateBuildExecutionRequest } from '../contracts/build-execution.mjs';
import { diagnosticSetFingerprint, parseCompileDiagnostics } from '../diagnostics/compile-diagnostics.mjs';
import { buildStageEvent } from '../events/stage-events.mjs';
import { createVisibleExecutionEvent, emitVisibleExecutionEvent } from '../events/visible-execution-events.mjs';
import { selectVerificationDefinitions, validateImpactPlan } from '../impact/change-impact.mjs';
import { createBuildManifest } from '../manifest/build-manifest.mjs';
import { createMaterializationPlan, sourceDigest } from '../source/source-materializer.mjs';
import { validateToolchainInventory } from '../toolchains/toolchain-policy.mjs';
import { buildProject, installDependencies, runAdapterTests } from './operation-executor.mjs';

function createEmitter(request, sink = async () => {}) {
  let sequence = 0;
  return async (stage, detail = {}) => {
    const event = buildStageEvent({
      executionId: request.executionId,
      buildJobId: request.buildJobId,
      projectId: request.projectId,
      attempt: request.attempt,
      stage,
      sequence: ++sequence,
      detail,
    });
    await sink(event);
    return event;
  };
}

function commandReceipt(result) {
  if (!result || result.skipped) return [];
  const plan = result.plan;
  return plan ? [{ executable: plan.executable, args: plan.args }] : [];
}

function outputText(value) {
  return value?.text ?? value ?? '';
}

async function emitVisible(eventSink, request, type, stepKey, payload, commandClass = null) {
  if (typeof eventSink !== 'function') return null;
  return emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
    type,
    request,
    stepKey,
    commandClass,
    payload,
  }));
}

async function executeBuildPipeline({
  request: rawRequest,
  gatewayAuthorization,
  workspace,
  sandbox,
  materializer,
  projectMetadata = {},
  filenames = [],
  packageJson = null,
  npmrc = null,
  dockerfile = null,
  toolchainInventory = {},
  environment = {},
  credentialValues = [],
  eventSink,
  signal,
}) {
  const request = validateBuildExecutionRequest(rawRequest);
  const gateway = assertWorkerCAuthorization({ gateway: gatewayAuthorization, request });
  if (gateway.tool !== 'request_build') throw new Error('WORKER_C_BUILD_TOOL_REQUIRED');
  if (!workspace?.root) throw new Error('WORKSPACE_REQUIRED');
  if (!materializer || typeof materializer.materialize !== 'function') throw new Error('MATERIALIZER_REQUIRED');

  const emit = createEmitter(request, eventSink);
  const startedAt = new Date().toISOString();
  const events = [];
  const record = async (stage, detail) => {
    const event = await emit(stage, detail);
    events.push(event);
    return event;
  };

  await record('workspace_preparing', { environment: request.environment });
  const sourcePlan = createMaterializationPlan(request.source);
  await record('source_materializing', { kind: sourcePlan.kind });
  const materialized = await materializer.materialize({
    plan: sourcePlan,
    workspace,
    networkPolicy: request.networkPolicy,
    signal,
  });

  const adapter = resolveBuildAdapter({ metadata: projectMetadata, filenames, packageJson });
  const impactPlan = validateImpactPlan(request.arguments?.change_impact);
  await record('impact_classified', {
    authoritative: impactPlan.authoritative,
    impactTier: impactPlan.impactTier,
    impactClass: impactPlan.impactClass,
    buildScope: impactPlan.buildScope,
    verificationScope: impactPlan.verificationScope,
  });
  const toolchains = validateToolchainInventory(adapter, toolchainInventory);
  validateSafeGeneratedConfig({ packageJson, npmrc, dockerfile });

  await record('dependencies_installing', { adapter: adapter.id });
  const dependency = await installDependencies({
    sandbox,
    adapter,
    filenames,
    workspaceRoot: workspace.root,
    env: environment,
    limits: request.resourceLimits,
    networkPolicy: request.networkPolicy,
    signal,
    redact: credentialValues,
    eventSink,
    eventContext: request,
    stepKey: 'dependencies',
  });
  if (dependency.status !== 'completed') {
    return Object.freeze({
      status: dependency.status,
      failureClass: dependency.failureClass,
      adapter,
      events: Object.freeze(events),
      dependency,
    });
  }

  await record('building', { adapter: adapter.id });
  if (adapter.build) {
    await emitVisible(eventSink, request, 'compile_started', 'compile', {
      tool: adapter.id,
      started_at: new Date().toISOString(),
    }, 'compile');
  }
  const build = await buildProject({
    sandbox,
    adapter: { ...adapter, tests: testDefinitions },
    workspaceRoot: workspace.root,
    env: environment,
    limits: request.resourceLimits,
    networkPolicy: request.networkPolicy,
    signal,
    redact: credentialValues,
    eventSink,
    eventContext: request,
    stepKey: 'compile',
  });
  const diagnostics = build.skipped ? Object.freeze([]) : parseCompileDiagnostics({
    stdout: outputText(build.stdout),
    stderr: outputText(build.stderr),
    tool: adapter.id,
    workspaceRoot: workspace.root,
    secrets: credentialValues,
  });
  if (adapter.build) {
    for (const diagnostic of diagnostics) {
      await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
        type: 'compile_diagnostic',
        request,
        stepKey: 'compile',
        commandClass: 'compile',
        filePath: diagnostic.filePath,
        payload: {
          tool: diagnostic.tool,
          severity: diagnostic.severity,
          error_code: diagnostic.errorCode,
          line: diagnostic.line,
          column: diagnostic.column,
          message: diagnostic.message,
          fingerprint: diagnostic.fingerprint,
        },
      }));
    }
    await emitVisible(eventSink, request, 'compile_completed', 'compile', {
      tool: adapter.id,
      status: build.status,
      exit_code: build.exitCode ?? null,
      failure_class: build.failureClass,
      error_count: diagnostics.filter((item) => item.severity === 'error').length,
      warning_count: diagnostics.filter((item) => item.severity === 'warning').length,
      diagnostic_fingerprint: diagnosticSetFingerprint(diagnostics),
      completed_at: build.finishedAt ?? new Date().toISOString(),
    }, 'compile');
  }
  if (build.status !== 'completed') {
    return Object.freeze({
      status: build.status,
      failureClass: build.failureClass,
      adapter,
      events: Object.freeze(events),
      dependency,
      build,
      diagnostics,
    });
  }

  await record('testing', { adapter: adapter.id });
  const testDefinitions = selectVerificationDefinitions(adapter.tests ?? [], impactPlan);
  if (testDefinitions.length) {
    await emitVisible(eventSink, request, 'test_started', 'tests', {
      suite_count: testDefinitions.length,
      started_at: new Date().toISOString(),
    }, 'test');
  }
  const tests = await runAdapterTests({
    sandbox,
    adapter: { ...adapter, tests: testDefinitions },
    workspaceRoot: workspace.root,
    env: environment,
    limits: request.resourceLimits,
    networkPolicy: request.networkPolicy,
    signal,
    redact: credentialValues,
    eventSink,
    eventContext: request,
  });
  let passed = 0;
  let failed = 0;
  let skipped = 0;
  for (let index = 0; index < tests.length; index += 1) {
    const result = tests[index];
    const status = result.status === 'completed' && result.exitCode === 0 ? 'passed' : result.status === 'cancelled' ? 'cancelled' : 'failed';
    if (status === 'passed') passed += 1;
    else if (status === 'failed') failed += 1;
    if (result.skipped) skipped += 1;
    await emitVisible(eventSink, request, 'test_result', `test:${result.category ?? index + 1}`, {
      suite: result.category ?? `test-${index + 1}`,
      status,
      optional: Boolean(result.optional),
      exit_code: result.exitCode ?? null,
      failure_class: result.failureClass,
      duration_ms: Number(result.durationMs ?? 0) || null,
    }, 'test');
  }
  if (testDefinitions.length) {
    await emitVisible(eventSink, request, 'test_completed', 'tests', {
      executed: tests.length,
      passed,
      failed,
      skipped,
      completed_at: new Date().toISOString(),
    }, 'test');
  }
  const mandatoryFailure = tests.find((test) => !test.optional && test.status !== 'completed');
  if (mandatoryFailure) {
    return Object.freeze({
      status: 'failed',
      failureClass: mandatoryFailure.failureClass ?? 'test',
      adapter,
      events: Object.freeze(events),
      dependency,
      build,
      diagnostics,
      tests,
    });
  }

  await record('artifact_collecting', { adapter: adapter.id });
  const collected = await collectArtifacts({
    workspaceRoot: workspace.root,
    outputs: adapter.outputs,
    limits: request.resourceLimits,
  });
  const finishedAt = new Date().toISOString();
  const manifest = createBuildManifest({
    projectId: request.projectId,
    projectVersionId: request.projectVersionId,
    source: request.source,
    sourceDigest: sourceDigest(request.source),
    adapter,
    toolchains,
    environmentProfile: request.environment,
    artifacts: collected.artifacts,
    tests,
    commands: [...commandReceipt(dependency), ...(adapter.build ? [adapter.build] : []), ...testDefinitions],
    attempt: request.attempt,
    startedAt,
    finishedAt,
  });
  await record('ready_for_verification', {
    manifestSha256: manifest.manifestSha256,
    artifactCount: collected.artifacts.length,
  });
  return Object.freeze({
    status: 'completed',
    failureClass: null,
    adapter,
    materialized,
    dependency,
    build,
    diagnostics,
    tests,
    artifacts: collected,
    manifest,
    impactPlan,
    events: Object.freeze(events),
  });
}

export { executeBuildPipeline };
