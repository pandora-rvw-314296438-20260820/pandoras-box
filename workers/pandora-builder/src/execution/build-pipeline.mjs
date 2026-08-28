import { resolveBuildAdapter } from '../adapters/adapter-registry.mjs';
import { collectArtifacts } from '../artifacts/artifact-collector.mjs';
import { validateSafeGeneratedConfig } from '../config/safe-generated-config.mjs';
import { assertWorkerCAuthorization } from '../contracts/authorized-build-request.mjs';
import { validateBuildExecutionRequest } from '../contracts/build-execution.mjs';
import { buildStageEvent } from '../events/stage-events.mjs';
import { createBuildManifest } from '../manifest/build-manifest.mjs';
import { createMaterializationPlan, sourceDigest } from '../source/source-materializer.mjs';
import { validateToolchainInventory } from '../toolchains/toolchain-policy.mjs';
import { buildProject, installDependencies, runAdapterTests } from './operation-executor.mjs';

function createEmitter(request, sink = () => {}) {
  let sequence = 0;
  return (stage, detail = {}) => {
    const event = buildStageEvent({ executionId: request.executionId, buildJobId: request.buildJobId, projectId: request.projectId, attempt: request.attempt, stage, sequence: ++sequence, detail });
    sink(event);
    return event;
  };
}

function commandReceipt(result) {
  if (!result || result.skipped) return [];
  const plan = result.plan;
  return plan ? [{ executable: plan.executable, args: plan.args }] : [];
}

async function executeBuildPipeline({ request: rawRequest, gatewayAuthorization, workspace, sandbox, materializer, projectMetadata = {}, filenames = [], packageJson = null, npmrc = null, dockerfile = null, toolchainInventory = {}, environment = {}, credentialValues = [], eventSink, signal }) {
  const request = validateBuildExecutionRequest(rawRequest);
  const gateway = assertWorkerCAuthorization({ gateway: gatewayAuthorization, request });
  if (gateway.tool !== 'request_build') throw new Error('WORKER_C_BUILD_TOOL_REQUIRED');
  if (!workspace?.root) throw new Error('WORKSPACE_REQUIRED');
  if (!materializer || typeof materializer.materialize !== 'function') throw new Error('MATERIALIZER_REQUIRED');
  const emit = createEmitter(request, eventSink);
  const startedAt = new Date().toISOString();
  const events = [];
  const record = (stage, detail) => { const e = emit(stage, detail); events.push(e); return e; };

  record('workspace_preparing', { environment: request.environment });
  const sourcePlan = createMaterializationPlan(request.source);
  record('source_materializing', { kind: sourcePlan.kind });
  const materialized = await materializer.materialize({ plan: sourcePlan, workspace, networkPolicy: request.networkPolicy, signal });

  const adapter = resolveBuildAdapter({ metadata: projectMetadata, filenames, packageJson });
  const toolchains = validateToolchainInventory(adapter, toolchainInventory);
  validateSafeGeneratedConfig({ packageJson, npmrc, dockerfile });

  record('dependencies_installing', { adapter: adapter.id });
  const dependency = await installDependencies({ sandbox, adapter, filenames, workspaceRoot: workspace.root, env: environment, limits: request.resourceLimits, networkPolicy: request.networkPolicy, signal, redact: credentialValues });
  if (dependency.status !== 'completed') return Object.freeze({ status: dependency.status, failureClass: dependency.failureClass, adapter, events: Object.freeze(events), dependency });

  record('building', { adapter: adapter.id });
  const build = await buildProject({ sandbox, adapter, workspaceRoot: workspace.root, env: environment, limits: request.resourceLimits, networkPolicy: request.networkPolicy, signal, redact: credentialValues });
  if (build.status !== 'completed') return Object.freeze({ status: build.status, failureClass: build.failureClass, adapter, events: Object.freeze(events), dependency, build });

  record('testing', { adapter: adapter.id });
  const tests = await runAdapterTests({ sandbox, adapter, workspaceRoot: workspace.root, env: environment, limits: request.resourceLimits, networkPolicy: request.networkPolicy, signal, redact: credentialValues });
  const mandatoryFailure = tests.find((test) => !test.optional && test.status !== 'completed');
  if (mandatoryFailure) return Object.freeze({ status: 'failed', failureClass: mandatoryFailure.failureClass ?? 'test', adapter, events: Object.freeze(events), dependency, build, tests });

  record('artifact_collecting', { adapter: adapter.id });
  const collected = await collectArtifacts({ workspaceRoot: workspace.root, outputs: adapter.outputs, limits: request.resourceLimits });
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
    commands: [...commandReceipt(dependency), ...(adapter.build ? [adapter.build] : []), ...adapter.tests],
    attempt: request.attempt,
    startedAt,
    finishedAt,
  });
  record('ready_for_verification', { manifestSha256: manifest.manifestSha256, artifactCount: collected.artifacts.length });
  return Object.freeze({ status: 'completed', failureClass: null, adapter, materialized, dependency, build, tests, artifacts: collected, manifest, events: Object.freeze(events) });
}

export { executeBuildPipeline };
