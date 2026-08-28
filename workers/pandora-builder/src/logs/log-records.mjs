import { createHash } from 'node:crypto';

const TOKEN_PATTERNS = [
  /Bearer\s+[A-Za-z0-9._~+\/-]+=*/gi,
  /(?:api[_-]?key|token|secret|password)\s*[:=]\s*[^\s,;]+/gi,
  /gh[pousr]_[A-Za-z0-9_]{20,}/g,
];

function redactText(value, secrets = []) {
  let text = String(value ?? '');
  for (const secret of secrets.filter((v) => typeof v === 'string' && v.length >= 4)) text = text.split(secret).join('[REDACTED]');
  for (const pattern of TOKEN_PATTERNS) text = text.replace(pattern, '[REDACTED]');
  return text;
}

function createLogRecord({ stream, text, executionId, step, maxInlineBytes = 64 * 1024, secrets = [] }) {
  if (!['stdout', 'stderr', 'worker'].includes(stream)) throw new Error('INVALID_LOG_STREAM');
  const redacted = redactText(text, secrets);
  const bytes = Buffer.byteLength(redacted);
  const sha256 = createHash('sha256').update(redacted).digest('hex');
  return Object.freeze({ schemaVersion: 1, executionId, step, stream, sha256, bytes, inline: bytes <= maxInlineBytes ? redacted : null, artifactRequired: bytes > maxInlineBytes });
}

function ownerSafeSummary({ status, failureClass, step }) {
  if (status === 'completed') return `Completed ${step}.`;
  if (status === 'cancelled') return `Stopped ${step}.`;
  const label = ({ dependency: 'dependency setup', syntax: 'generated code', type: 'type checking', compile: 'build compilation', test: 'tests', timeout: 'time limit', resource_limit: 'resource limit', network: 'network access', configuration: 'configuration', filesystem: 'workspace files', sandbox: 'build sandbox', credential: 'temporary access' })[failureClass] ?? 'build execution';
  return `Could not complete ${step} because of ${label}.`;
}

export { createLogRecord, ownerSafeSummary, redactText };
