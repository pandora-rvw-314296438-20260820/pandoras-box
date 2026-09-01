import { dependencyInstallPlan } from '../dependencies/dependency-plan.mjs';
import { classifyFailure } from '../failure/classify-failure.mjs';
import { createCustomerOutputChunks } from '../logs/log-records.mjs';
import { networkDecision } from '../network/network-policy.mjs';
import {
  createVisibleExecutionEvent,
  emitVisibleExecutionEvent,
  safeDisplayCommand,
} from '../events/visible-execution-events.mjs';

function assertSandbox(sandbox) {
  if (!sandbox || typeof sandbox.execute !== 'function') throw new Error('SANDBOX_EXECUTOR_REQUIRED');
}

function assertRequiredHosts(policy, hosts = []) {
  for (const host of hosts) {
    const decision = networkDecision(policy, host);
    if (!decision.allowed) {
      const error = new Error('NETWORK_POLICY_DENIES_REQUIRED_HOST');
      error.host = decision.host;
      throw error;
    }
  }
  return true;
}

async function emitOutput({
  eventSink,
  eventContext,
  stepKey,
  commandClass,
  stream,
  text,
  redact,
  maxChunkBytes,
  maxTotalBytes,
}) {
  const output = createCustomerOutputChunks({
    stream,
    text,
    secrets: redact,
    maxChunkBytes,
    maxTotalBytes,
  });
  let outputIndex = 0;
  for (const chunk of output.chunks) {
    outputIndex += 1;
    await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
      type: stream === 'stdout' ? 'stdout_chunk' : 'stderr_chunk',
      request: eventContext,
      stepKey,
      commandClass,
      payload: {
        output_index: outputIndex,
        text: chunk.text,
        bytes: chunk.bytes,
      },
    }));
  }
  return output;
}

async function executeTrustedCommand({
  sandbox,
  command,
  workspaceRoot,
  env,
  limits,
  networkPolicy,
  signal,
  redact = [],
  eventSink = null,
  eventContext = null,
  commandClass = 'build',
  stepKey = 'command',
  maxCustomerChunkBytes = 2048,
  maxCustomerOutputBytes = 16 * 1024,
}) {
  assertSandbox(sandbox);
  if (!command || typeof command.executable !== 'string' || !Array.isArray(command.args)) throw new Error('TRUSTED_COMMAND_REQUIRED');
  if (['sh', 'bash', 'zsh', 'cmd', 'cmd.exe', 'powershell', 'powershell.exe', 'pwsh'].includes(command.executable.toLowerCase())) {
    throw new Error('GENERIC_SHELL_FORBIDDEN');
  }
  if (eventSink && !eventContext) throw new Error('VISIBLE_EXECUTION_CONTEXT_REQUIRED');

  const startedAt = new Date().toISOString();
  if (eventSink) {
    await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
      type: 'command_started',
      request: eventContext,
      stepKey,
      commandClass,
      payload: {
        display_command: safeDisplayCommand(command, redact),
        started_at: startedAt,
      },
    }));
  }

  let result;
  try {
    result = await sandbox.execute({
      executable: command.executable,
      args: command.args,
      cwd: workspaceRoot,
      env,
      timeoutMs: command.timeoutMs ?? limits.wallClockMs,
      maxOutputBytes: limits.outputBytes,
      resourceLimits: limits,
      networkPolicy,
      signal,
      redact,
    });
  } catch (error) {
    if (eventSink) {
      await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
        type: 'command_completed',
        request: eventContext,
        stepKey,
        commandClass,
        payload: {
          status: signal?.aborted ? 'cancelled' : 'failed',
          exit_code: null,
          failure_class: signal?.aborted ? 'cancelled' : 'sandbox',
          completed_at: new Date().toISOString(),
          output_truncated: false,
        },
      }));
    }
    throw error;
  }

  const stdoutText = result.stdout?.text ?? result.stdout ?? '';
  const stderrText = result.stderr?.text ?? result.stderr ?? '';
  const failureClass = result.status === 'completed' && result.exitCode === 0 ? null : classifyFailure({
    stderr: stderrText,
    stdout: stdoutText,
    exitCode: result.exitCode,
    timedOut: result.failureClass === 'timeout',
    cancelled: result.status === 'cancelled' || result.failureClass === 'cancelled',
    resourceLimit: result.failureClass === 'resource_limit',
  });
  const normalized = Object.freeze({ ...result, failureClass });

  let stdoutDisplay = null;
  let stderrDisplay = null;
  if (eventSink) {
    stdoutDisplay = await emitOutput({
      eventSink,
      eventContext,
      stepKey,
      commandClass,
      stream: 'stdout',
      text: stdoutText,
      redact,
      maxChunkBytes: maxCustomerChunkBytes,
      maxTotalBytes: maxCustomerOutputBytes,
    });
    stderrDisplay = await emitOutput({
      eventSink,
      eventContext,
      stepKey,
      commandClass,
      stream: 'stderr',
      text: stderrText,
      redact,
      maxChunkBytes: maxCustomerChunkBytes,
      maxTotalBytes: maxCustomerOutputBytes,
    });
    await emitVisibleExecutionEvent(eventSink, createVisibleExecutionEvent({
      type: 'command_completed',
      request: eventContext,
      stepKey,
      commandClass,
      payload: {
        status: normalized.status,
        exit_code: normalized.exitCode ?? null,
        failure_class: normalized.failureClass,
        duration_ms: Number(normalized.durationMs ?? 0) || null,
        completed_at: normalized.finishedAt ?? new Date().toISOString(),
        output_truncated: Boolean(stdoutDisplay.truncated || stderrDisplay.truncated),
        stdout_bytes: stdoutDisplay.sourceBytes,
        stderr_bytes: stderrDisplay.sourceBytes,
      },
    }));
  }

  return normalized;
}

async function installDependencies({
  sandbox,
  adapter,
  filenames,
  workspaceRoot,
  env,
  limits,
  networkPolicy,
  signal,
  redact,
  eventSink = null,
  eventContext = null,
  stepKey = 'dependencies',
}) {
  const plan = dependencyInstallPlan({ adapter, filenames });
  if (!plan) return Object.freeze({ status: 'completed', skipped: true, exitCode: 0, failureClass: null, plan: null });
  assertRequiredHosts(networkPolicy, plan.requiredHosts);
  const result = await executeTrustedCommand({
    sandbox,
    command: { executable: plan.executable, args: plan.args, timeoutMs: limits.dependencyInstallMs },
    workspaceRoot,
    env,
    limits,
    networkPolicy,
    signal,
    redact,
    eventSink,
    eventContext,
    commandClass: 'dependency',
    stepKey,
  });
  return Object.freeze({ ...result, plan });
}

async function buildProject({
  sandbox,
  adapter,
  workspaceRoot,
  env,
  limits,
  networkPolicy,
  signal,
  redact,
  eventSink = null,
  eventContext = null,
  stepKey = 'compile',
}) {
  if (!adapter.build) return Object.freeze({ status: 'completed', skipped: true, exitCode: 0, failureClass: null });
  return executeTrustedCommand({
    sandbox,
    command: adapter.build,
    workspaceRoot,
    env,
    limits,
    networkPolicy,
    signal,
    redact,
    eventSink,
    eventContext,
    commandClass: 'compile',
    stepKey,
  });
}

async function runAdapterTests({
  sandbox,
  adapter,
  workspaceRoot,
  env,
  limits,
  networkPolicy,
  signal,
  redact,
  eventSink = null,
  eventContext = null,
}) {
  const results = [];
  let index = 0;
  for (const test of adapter.tests ?? []) {
    index += 1;
    const result = await executeTrustedCommand({
      sandbox,
      command: test,
      workspaceRoot,
      env,
      limits,
      networkPolicy,
      signal,
      redact,
      eventSink,
      eventContext,
      commandClass: 'test',
      stepKey: `test:${test.category ?? index}`,
    });
    results.push(Object.freeze({ category: test.category, optional: Boolean(test.optional), ...result }));
    if (result.status !== 'completed' && !test.optional) break;
  }
  return Object.freeze(results);
}

export { assertRequiredHosts, buildProject, executeTrustedCommand, installDependencies, runAdapterTests };
