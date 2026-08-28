import { randomUUID } from 'node:crypto';
import path from 'node:path';

const IMAGE = /^[a-z0-9][a-z0-9._\/-]*(?::[A-Za-z0-9._-]+|@sha256:[0-9a-f]{64})$/;
const ENV = /^[A-Z][A-Z0-9_]{0,63}$/;

function assertWorkspaceRoot(workspaceRoot, platform) {
  if (typeof workspaceRoot !== 'string' || !workspaceRoot || workspaceRoot.includes('\0') || workspaceRoot.includes('\n') || workspaceRoot.includes('\r') || workspaceRoot.includes(',')) throw new Error('INVALID_SANDBOX_WORKSPACE');
  const flavor = platform === 'win32' ? path.win32 : path.posix;
  if (!flavor.isAbsolute(workspaceRoot)) throw new Error('SANDBOX_WORKSPACE_MUST_BE_ABSOLUTE');
}

function dockerCreateArgs({ name, image, workspaceRoot, limits, platform = process.platform, networkPolicy, cpuCount = 2, requireImageDigest = true }) {
  if (!IMAGE.test(image ?? '')) throw new Error('INVALID_SANDBOX_IMAGE');
  if (requireImageDigest && !image.includes('@sha256:')) throw new Error('MUTABLE_SANDBOX_IMAGE_FORBIDDEN');
  if (!name || !/^[A-Za-z0-9][A-Za-z0-9_.-]{0,127}$/.test(name)) throw new Error('INVALID_SANDBOX_IDENTITY');
  assertWorkspaceRoot(workspaceRoot, platform);
  if (networkPolicy?.mode === 'allowlist') throw new Error('SANDBOX_EGRESS_ALLOWLIST_PROVIDER_REQUIRED');
  if (!Number.isFinite(cpuCount) || cpuCount <= 0 || cpuCount > 64) throw new Error('INVALID_SANDBOX_CPU_CAP');
  const args = ['create', '--name', name, '--network', 'none', '--read-only', '--memory', String(limits.memoryBytes), '--cpus', String(cpuCount), '--pids-limit', String(limits.processCount)];
  if (platform === 'win32') {
    args.push('--isolation=hyperv', '--user', 'ContainerUser');
    args.push('--mount', `type=bind,src=${workspaceRoot},dst=C:\\workspace`, '--workdir', 'C:\\workspace');
  } else {
    args.push('--cap-drop', 'ALL', '--security-opt', 'no-new-privileges', '--user', '65532:65532');
    args.push('--mount', `type=bind,src=${workspaceRoot},dst=/workspace`, '--workdir', '/workspace');
  }
  args.push(image, platform === 'win32' ? 'powershell.exe' : 'node', ...(platform === 'win32' ? ['-NoLogo', '-NonInteractive', '-Command', 'while ($true) { Start-Sleep -Seconds 3600 }'] : ['-e', 'setInterval(()=>{},2147483647)']));
  return Object.freeze(args);
}

class DockerSandboxProvider {
  constructor({ runner, image, platform = process.platform, cpuCount = 2, runnerEnvironment = {}, requireImageDigest = true }) {
    if (!runner || typeof runner.run !== 'function') throw new Error('SANDBOX_RUNNER_REQUIRED');
    this.runner = runner; this.image = image; this.platform = platform; this.cpuCount = cpuCount; this.requireImageDigest = requireImageDigest;
    this.runnerEnvironment = Object.freeze({ ...runnerEnvironment }); this.records = new Map();
  }
  capabilities() { return Object.freeze({ cpu: false, memory: true, disk: false, processCount: true, wallClock: true, output: true, denyNetwork: true, networkAllowlist: false, hyperv: this.platform === 'win32' }); }
  async create({ workspaceRoot, limits, networkPolicy }) {
    const id = `pandora-${randomUUID()}`;
    const args = dockerCreateArgs({ name: id, image: this.image, workspaceRoot, limits, platform: this.platform, networkPolicy, cpuCount: this.cpuCount, requireImageDigest: this.requireImageDigest });
    await this.runner.run('docker', args, { shell: false, env: this.runnerEnvironment, inheritEnv: false });
    await this.runner.run('docker', ['start', id], { shell: false, env: this.runnerEnvironment, inheritEnv: false });
    this.records.set(id, { id, workspaceRoot, status: 'running' });
    return Object.freeze({ id, provider: 'docker', workspaceRoot });
  }
  async execute({ sandboxId, executable, args = [], env = {}, timeoutMs, maxOutputBytes, signal }) {
    if (!this.records.has(sandboxId)) throw new Error('SANDBOX_NOT_FOUND');
    const keys = Object.keys(env);
    if (keys.some((key) => !ENV.test(key))) throw new Error('INVALID_SANDBOX_ENVIRONMENT');
    const envArgs = keys.flatMap((key) => ['--env', key]);
    return this.runner.run('docker', ['exec', ...envArgs, sandboxId, executable, ...args], { shell: false, timeoutMs, maxOutputBytes, signal, env: Object.freeze({ ...this.runnerEnvironment, ...env }), inheritEnv: false });
  }
  async cancel(id) { if (!this.records.has(id)) return { status: 'absent' }; await this.runner.run('docker', ['kill', id], { shell: false, allowFailure: true, env: this.runnerEnvironment, inheritEnv: false }); this.records.get(id).status = 'cancelled'; return { status: 'cancelled' }; }
  async destroy(id) { await this.runner.run('docker', ['rm', '-f', id], { shell: false, allowFailure: true, env: this.runnerEnvironment, inheritEnv: false }); this.records.delete(id); return { status: 'destroyed' }; }
  async inspect(id) { return this.records.get(id) ? Object.freeze({ ...this.records.get(id) }) : null; }
}

export { DockerSandboxProvider, dockerCreateArgs };
