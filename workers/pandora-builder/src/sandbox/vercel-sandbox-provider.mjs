
import { randomUUID } from 'node:crypto';
import { validateBuildExecutionRequest } from '../contracts/build-execution.mjs';
import { SandboxProvider } from './sandbox-manager.mjs';

const TEAM_ID = /^team_[A-Za-z0-9]+$/;
const PROJECT_ID = /^prj_[A-Za-z0-9]+$/;
const SESSION_ID = /^sbx_[A-Za-z0-9]+$/;
const COMMAND_ID = /^cmd_[A-Za-z0-9]+$/;
const SAFE_NAME = /^[a-z0-9][a-z0-9-]{0,62}$/;
const SAFE_EXECUTABLE = /^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/;
const FORBIDDEN_EXECUTABLES = new Set(['sh','bash','zsh','cmd','cmd.exe','powershell','powershell.exe','pwsh']);
const SECRET_ENV = /(?:^|_)(?:TOKEN|SECRET|PASSWORD|API_KEY|PRIVATE_KEY|AUTHORIZATION|COOKIE)(?:_|$)/i;

function required(value, field, pattern) {
  if (typeof value !== 'string' || !pattern.test(value)) throw new Error(`INVALID_${field.toUpperCase()}`);
  return value;
}

function responseBody(response) {
  if (!response || typeof response.status !== 'number') throw new Error('VERCEL_SANDBOX_TRANSPORT_INVALID');
  if (response.status < 200 || response.status >= 300) {
    const error = new Error('VERCEL_SANDBOX_PROVIDER_ERROR');
    error.status = response.status;
    error.providerBody = response.body ?? null;
    throw error;
  }
  return response.body && typeof response.body === 'object' ? response.body : {};
}

function scoped(path, teamId, extra = {}) {
  const url = new URL(`https://api.vercel.com${path}`);
  url.searchParams.set('teamId', teamId);
  for (const [key, value] of Object.entries(extra)) if (value != null && value !== '') url.searchParams.set(key, String(value));
  return `${url.pathname}${url.search}`;
}

function sandboxName(executionId) {
  const compact = executionId.replaceAll('-', '').toLowerCase();
  return `pandora-d-${compact.slice(0, 32)}`;
}

function networkPolicy(policy) {
  if (!policy || policy.mode === 'deny') return Object.freeze({ mode: 'deny-all' });
  if (policy.mode !== 'allowlist' || !Array.isArray(policy.allow) || policy.allow.length > 64) throw new Error('INVALID_NETWORK_POLICY');
  const allowedDomains = [...new Set(policy.allow.map((host) => {
    if (typeof host !== 'string' || !/^(?:\*\.)?[a-z0-9](?:[a-z0-9.-]{0,251}[a-z0-9])?$/i.test(host)) throw new Error('INVALID_NETWORK_POLICY_HOST');
    return host.toLowerCase();
  }))];
  return Object.freeze({ mode: 'custom', allowedDomains, allowedCIDRs: [], deniedCIDRs: [] });
}

function normalizedSession(body, fallback = {}) {
  const sandbox = body?.sandbox && typeof body.sandbox === 'object' ? body.sandbox : {};
  const candidate = body?.session && typeof body.session === 'object'
    ? body.session
    : sandbox?.session && typeof sandbox.session === 'object'
      ? sandbox.session
      : body?.currentSession && typeof body.currentSession === 'object'
        ? body.currentSession
        : body;
  const sessionId = required(candidate?.id ?? candidate?.sessionId, 'session_id', SESSION_ID);
  const name = String(sandbox?.name ?? body?.name ?? candidate?.sourceSandboxName ?? fallback.name ?? '');
  if (!SAFE_NAME.test(name)) throw new Error('INVALID_SANDBOX_NAME');
  return Object.freeze({
    provider: 'vercel-sandbox',
    name,
    sessionId,
    projectId: fallback.projectId,
    teamId: fallback.teamId,
    executionId: fallback.executionId,
    buildJobId: fallback.buildJobId,
    environment: fallback.environment,
    cwd: typeof candidate?.cwd === 'string' && candidate.cwd.startsWith('/') ? candidate.cwd : '/vercel/sandbox',
    status: String(candidate?.status ?? 'running').toLowerCase(),
    networkPolicy: fallback.networkPolicy,
  });
}

function normalizeOperation(operation, handle) {
  if (!operation || typeof operation !== 'object' || Array.isArray(operation)) throw new Error('INVALID_SANDBOX_OPERATION');
  const executable = required(operation.executable, 'executable', SAFE_EXECUTABLE);
  if (FORBIDDEN_EXECUTABLES.has(executable.toLowerCase())) throw new Error('GENERIC_SHELL_FORBIDDEN');
  if (!Array.isArray(operation.args) || operation.args.length > 128 || operation.args.some((arg) => typeof arg !== 'string' || arg.length > 4096 || arg.includes('\0'))) throw new Error('INVALID_SANDBOX_ARGUMENTS');
  const cwd = operation.cwd ?? handle.cwd;
  if (typeof cwd !== 'string' || !cwd.startsWith('/') || cwd.includes('\0') || cwd.includes('/../')) throw new Error('INVALID_SANDBOX_CWD');
  const env = operation.env ?? {};
  if (!env || typeof env !== 'object' || Array.isArray(env) || Object.keys(env).length > 128) throw new Error('INVALID_SANDBOX_ENV');
  for (const [key, value] of Object.entries(env)) {
    if (!/^[A-Za-z_][A-Za-z0-9_]{0,127}$/.test(key) || SECRET_ENV.test(key) || typeof value !== 'string' || value.length > 8192) throw new Error('SANDBOX_CREDENTIAL_ENV_FORBIDDEN');
  }
  const timeoutMs = Number(operation.timeoutMs ?? 15 * 60_000);
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1000 || timeoutMs > 30 * 60_000) throw new Error('INVALID_SANDBOX_TIMEOUT');
  return Object.freeze({ executable, args: [...operation.args], cwd, env: { ...env }, timeoutMs, signal: operation.signal ?? null });
}

function commandRecord(body) {
  const command = body?.command && typeof body.command === 'object' ? body.command : body;
  const id = required(command?.id, 'command_id', COMMAND_ID);
  const exitCode = command?.exitCode == null ? null : Number(command.exitCode);
  return { id, exitCode: Number.isInteger(exitCode) ? exitCode : null, durationMs: Number(command?.durationMs ?? 0) || 0 };
}

function delay(ms, signal) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(resolve, ms);
    if (signal) signal.addEventListener('abort', () => { clearTimeout(timer); reject(Object.assign(new Error('SANDBOX_CANCELLED'), { code: 'ABORT_ERR' })); }, { once: true });
  });
}

class VercelSandboxProvider extends SandboxProvider {
  constructor({ transport, teamId, projectId, pollIntervalMs = 250, maxPolls = 7200 }) {
    super();
    if (!transport || typeof transport.request !== 'function') throw new Error('VERCEL_SANDBOX_TRANSPORT_REQUIRED');
    this.transport = transport;
    this.teamId = required(teamId, 'team_id', TEAM_ID);
    this.projectId = required(projectId, 'project_id', PROJECT_ID);
    this.pollIntervalMs = Math.max(50, Math.min(Number(pollIntervalMs) || 250, 5000));
    this.maxPolls = Math.max(1, Math.min(Number(maxPolls) || 7200, 10000));
  }

  async create(rawRequest) {
    const request = validateBuildExecutionRequest(rawRequest);
    const name = sandboxName(request.executionId);
    const policy = networkPolicy(request.networkPolicy);
    const memoryMiB = Math.max(2048, Math.min(8192, Math.ceil(request.resourceLimits.memoryBytes / 1024 / 1024)));
    const body = responseBody(await this.transport.request('POST', scoped('/v2/sandboxes', this.teamId), {
      name,
      projectId: this.projectId,
      runtime: 'node24',
      persistent: false,
      timeout: String(request.timeoutMs),
      resources: { vcpus: '2', memory: String(memoryMiB) },
      networkPolicy: policy,
      env: {},
      ports: [],
      tags: { pandora: 'worker-d', execution: request.executionId.slice(0, 36) },
    }));
    return normalizedSession(body, { name, projectId: this.projectId, teamId: this.teamId, executionId: request.executionId, buildJobId: request.buildJobId, environment: request.environment, networkPolicy: policy });
  }

  async resume(handle) {
    const name = required(handle?.name, 'sandbox_name', SAFE_NAME);
    const body = responseBody(await this.transport.request('GET', scoped(`/v2/sandboxes/${encodeURIComponent(name)}`, this.teamId, { projectId: this.projectId, resume: 'true' }), null));
    return normalizedSession(body, { ...handle, name, projectId: this.projectId, teamId: this.teamId });
  }

  async execute(handle, rawOperation) {
    const sessionId = required(handle?.sessionId, 'session_id', SESSION_ID);
    const operation = normalizeOperation(rawOperation, handle);
    const cmdId = `cmd_${randomUUID().replaceAll('-', '')}`;
    const started = responseBody(await this.transport.request('POST', scoped(`/v2/sandboxes/sessions/${sessionId}/cmd`, this.teamId, { cmdId }), {
      command: operation.executable,
      args: operation.args,
      cwd: operation.cwd,
      env: operation.env,
      sudo: false,
      wait: false,
      logs: false,
      timeout: operation.timeoutMs,
    }));
    let command = commandRecord(started);
    const startedAt = new Date().toISOString();
    for (let i = 0; command.exitCode == null && i < this.maxPolls; i += 1) {
      if (operation.signal?.aborted) {
        await this.transport.request('POST', scoped(`/v2/sandboxes/sessions/${sessionId}/cmd/${command.id}/kill`, this.teamId), null).catch(() => null);
        return Object.freeze({ status: 'cancelled', exitCode: null, failureClass: 'cancelled', stdout: { text: '' }, stderr: { text: '' }, startedAt, finishedAt: new Date().toISOString(), commandId: command.id });
      }
      await delay(this.pollIntervalMs, operation.signal).catch(async () => {
        await this.transport.request('POST', scoped(`/v2/sandboxes/sessions/${sessionId}/cmd/${command.id}/kill`, this.teamId), null).catch(() => null);
        throw Object.assign(new Error('SANDBOX_CANCELLED'), { code: 'ABORT_ERR' });
      });
      const polled = responseBody(await this.transport.request('GET', scoped(`/v2/sandboxes/sessions/${sessionId}/cmd/${command.id}`, this.teamId), null));
      command = commandRecord(polled);
    }
    if (command.exitCode == null) {
      await this.transport.request('POST', scoped(`/v2/sandboxes/sessions/${sessionId}/cmd/${command.id}/kill`, this.teamId), null).catch(() => null);
      return Object.freeze({ status: 'failed', exitCode: null, failureClass: 'timeout', stdout: { text: '' }, stderr: { text: '' }, startedAt, finishedAt: new Date().toISOString(), commandId: command.id });
    }
    return Object.freeze({ status: command.exitCode === 0 ? 'completed' : 'failed', exitCode: command.exitCode, failureClass: command.exitCode === 0 ? null : 'unknown', stdout: { text: '' }, stderr: { text: '' }, startedAt, finishedAt: new Date().toISOString(), durationMs: command.durationMs, commandId: command.id });
  }

  async cancel(handle, reason = 'cancelled') {
    const sessionId = required(handle?.sessionId, 'session_id', SESSION_ID);
    const body = responseBody(await this.transport.request('POST', scoped(`/v2/sandboxes/sessions/${sessionId}/stop`, this.teamId), { reason: String(reason).slice(0, 160) }));
    return Object.freeze({ stopped: true, sessionId, provider: 'vercel-sandbox', providerStatus: body?.session?.status ?? body?.status ?? null });
  }

  async destroy(handle) {
    const name = required(handle?.name, 'sandbox_name', SAFE_NAME);
    responseBody(await this.transport.request('DELETE', scoped(`/v2/sandboxes/${encodeURIComponent(name)}`, this.teamId, { projectId: this.projectId }), null));
    return Object.freeze({ destroyed: true, name, provider: 'vercel-sandbox' });
  }

  async inspect(handle) {
    const name = required(handle?.name, 'sandbox_name', SAFE_NAME);
    const body = responseBody(await this.transport.request('GET', scoped(`/v2/sandboxes/${encodeURIComponent(name)}`, this.teamId, { projectId: this.projectId, resume: 'false' }), null));
    return normalizedSession(body, { ...handle, name, projectId: this.projectId, teamId: this.teamId });
  }
}

export { VercelSandboxProvider, networkPolicy as vercelSandboxNetworkPolicy };
