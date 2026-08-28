import { dependencyInstallPlan } from '../dependencies/dependency-plan.mjs';
import { classifyFailure } from '../failure/classify-failure.mjs';
import { networkDecision } from '../network/network-policy.mjs';

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

async function executeTrustedCommand({ sandbox, command, workspaceRoot, env, limits, networkPolicy, signal, redact = [] }) {
  assertSandbox(sandbox);
  if (!command || typeof command.executable !== 'string' || !Array.isArray(command.args)) throw new Error('TRUSTED_COMMAND_REQUIRED');
  if (['sh', 'bash', 'zsh', 'cmd', 'cmd.exe', 'powershell', 'powershell.exe', 'pwsh'].includes(command.executable.toLowerCase())) throw new Error('GENERIC_SHELL_FORBIDDEN');
  const result = await sandbox.execute({
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
  const failureClass = result.status === 'completed' && result.exitCode === 0 ? null : classifyFailure({
    stderr: result.stderr?.text ?? result.stderr ?? '',
    stdout: result.stdout?.text ?? result.stdout ?? '',
    exitCode: result.exitCode,
    timedOut: result.failureClass === 'timeout',
    cancelled: result.status === 'cancelled' || result.failureClass === 'cancelled',
    resourceLimit: result.failureClass === 'resource_limit',
  });
  return Object.freeze({ ...result, failureClass });
}

async function installDependencies({ sandbox, adapter, filenames, workspaceRoot, env, limits, networkPolicy, signal, redact }) {
  const plan = dependencyInstallPlan({ adapter, filenames });
  if (!plan) return Object.freeze({ status: 'completed', skipped: true, exitCode: 0, failureClass: null, plan: null });
  assertRequiredHosts(networkPolicy, plan.requiredHosts);
  const result = await executeTrustedCommand({ sandbox, command: { executable: plan.executable, args: plan.args, timeoutMs: limits.dependencyInstallMs }, workspaceRoot, env, limits, networkPolicy, signal, redact });
  return Object.freeze({ ...result, plan });
}

async function buildProject({ sandbox, adapter, workspaceRoot, env, limits, networkPolicy, signal, redact }) {
  if (!adapter.build) return Object.freeze({ status: 'completed', skipped: true, exitCode: 0, failureClass: null });
  return executeTrustedCommand({ sandbox, command: adapter.build, workspaceRoot, env, limits, networkPolicy, signal, redact });
}

async function runAdapterTests({ sandbox, adapter, workspaceRoot, env, limits, networkPolicy, signal, redact }) {
  const results = [];
  for (const test of adapter.tests ?? []) {
    const result = await executeTrustedCommand({ sandbox, command: test, workspaceRoot, env, limits, networkPolicy, signal, redact });
    results.push(Object.freeze({ category: test.category, optional: Boolean(test.optional), ...result }));
    if (result.status !== 'completed' && !test.optional) break;
  }
  return Object.freeze(results);
}

export { assertRequiredHosts, buildProject, executeTrustedCommand, installDependencies, runAdapterTests };
