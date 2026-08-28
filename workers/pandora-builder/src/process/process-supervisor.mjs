import { spawn } from 'node:child_process';

function safeArgv(command, args) {
  if (typeof command !== 'string' || command.length === 0 || command.includes('\0')) throw new Error('INVALID_EXECUTABLE');
  if (!Array.isArray(args) || args.length > 128 || args.some((arg) => typeof arg !== 'string' || arg.includes('\0') || arg.length > 32_768)) {
    throw new Error('INVALID_ARGV');
  }
  return [command, [...args]];
}

function createBoundedCapture(maxBytes, redact = []) {
  let bytes = 0;
  let truncated = false;
  const chunks = [];
  const secrets = redact.filter((value) => typeof value === 'string' && value.length >= 4);
  return {
    push(chunk) {
      if (truncated) return;
      let data = Buffer.from(chunk);
      const remaining = maxBytes - bytes;
      if (remaining <= 0) { truncated = true; return; }
      if (data.length > remaining) { data = data.subarray(0, remaining); truncated = true; }
      chunks.push(data);
      bytes += data.length;
    },
    result() {
      let text = Buffer.concat(chunks).toString('utf8');
      for (const secret of secrets) text = text.split(secret).join('[REDACTED]');
      return { text, bytes, truncated };
    },
  };
}

async function terminateProcessTree(child, signal = 'SIGTERM') {
  if (!child || child.exitCode != null || !child.pid) return;
  if (process.platform === 'win32') {
    await new Promise((resolve) => {
      const killer = spawn('taskkill.exe', ['/PID', String(child.pid), '/T', '/F'], { shell: false, windowsHide: true, stdio: 'ignore' });
      killer.once('exit', resolve);
      killer.once('error', resolve);
    });
    return;
  }
  try { process.kill(-child.pid, signal); } catch (error) { if (error?.code !== 'ESRCH') throw error; }
}

async function runSupervised({ command, args = [], cwd, env, timeoutMs, maxOutputBytes, signal, redact = [] }) {
  safeArgv(command, args);
  if (!Number.isInteger(timeoutMs) || timeoutMs < 1 || timeoutMs > 30 * 60_000) throw new Error('INVALID_PROCESS_TIMEOUT');
  if (!Number.isInteger(maxOutputBytes) || maxOutputBytes < 1 || maxOutputBytes > 64 * 1024 ** 2) throw new Error('INVALID_OUTPUT_LIMIT');
  const startedAt = new Date().toISOString();
  const stdout = createBoundedCapture(maxOutputBytes, redact);
  const stderr = createBoundedCapture(maxOutputBytes, redact);
  let timedOut = false;
  let cancelled = signal?.aborted === true;
  let outputExceeded = false;
  let child;

  if (cancelled) {
    return { status: 'cancelled', exitCode: null, signal: null, startedAt, finishedAt: new Date().toISOString(), stdout: stdout.result(), stderr: stderr.result() };
  }

  const result = await new Promise((resolve, reject) => {
    child = spawn(command, args, {
      cwd,
      env,
      shell: false,
      windowsHide: true,
      detached: process.platform !== 'win32',
      stdio: ['ignore', 'pipe', 'pipe'],
    });
    const onData = (capture) => (chunk) => {
      capture.push(chunk);
      const aggregate = stdout.result().bytes + stderr.result().bytes;
      if (aggregate >= maxOutputBytes && !outputExceeded) {
        outputExceeded = true;
        void terminateProcessTree(child, 'SIGKILL');
      }
    };
    child.stdout.on('data', onData(stdout));
    child.stderr.on('data', onData(stderr));
    child.once('error', reject);
    const timer = setTimeout(() => {
      timedOut = true;
      void terminateProcessTree(child, 'SIGKILL');
    }, timeoutMs);
    timer.unref?.();
    const onAbort = () => {
      cancelled = true;
      void terminateProcessTree(child, 'SIGKILL');
    };
    signal?.addEventListener('abort', onAbort, { once: true });
    child.once('exit', (code, exitSignal) => {
      clearTimeout(timer);
      signal?.removeEventListener('abort', onAbort);
      resolve({ code, exitSignal });
    });
  });

  const finishedAt = new Date().toISOString();
  let status = result.code === 0 ? 'completed' : 'failed';
  let failureClass = result.code === 0 ? null : 'unknown';
  if (timedOut) { status = 'failed'; failureClass = 'timeout'; }
  if (outputExceeded) { status = 'failed'; failureClass = 'resource_limit'; }
  if (cancelled) { status = 'cancelled'; failureClass = 'cancelled'; }
  return {
    status,
    failureClass,
    exitCode: Number.isInteger(result.code) ? result.code : null,
    signal: result.exitSignal ?? null,
    startedAt,
    finishedAt,
    stdout: stdout.result(),
    stderr: stderr.result(),
  };
}

export { runSupervised, safeArgv, terminateProcessTree };
