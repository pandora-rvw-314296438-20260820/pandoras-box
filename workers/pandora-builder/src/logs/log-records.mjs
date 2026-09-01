import { createHash } from 'node:crypto';

const TOKEN_PATTERNS = [
  /Authorization\s*:\s*(?:Bearer|Basic)\s+[^\s]+/gi,
  /Bearer\s+[A-Za-z0-9._~+\/-]+=*/gi,
  /(?:api[_-]?key|access[_-]?token|refresh[_-]?token|token|secret|password|private[_-]?key)\s*[:=]\s*["']?[^\s,;}"']+/gi,
  /(?:^|\s)(?:GITHUB_TOKEN|GITHUB_PAT|GITHUB_SUPABASE|VERCEL_TOKEN|SUPABASE_SERVICE_ROLE|SERVICE_ROLE_KEY|GEMINI_API_KEY|DATABASE_URL)\s*=\s*[^\s]+/gim,
  /gh[pousr]_[A-Za-z0-9_]{20,}/g,
  /(?:sbp|vcp|vercel)_[A-Za-z0-9_-]{20,}/gi,
  /AIza[A-Za-z0-9_-]{20,}/g,
  /eyJ[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}\.[A-Za-z0-9_-]{12,}/g,
  /-----BEGIN [A-Z ]*PRIVATE KEY-----[\s\S]*?-----END [A-Z ]*PRIVATE KEY-----/g,
  /https?:\/\/[^/\s:@]+:[^@\s/]+@/gi,
];

function redactText(value, secrets = []) {
  let text = String(value ?? '');
  for (const secret of secrets.filter((v) => typeof v === 'string' && v.length >= 4)) {
    text = text.split(secret).join('[REDACTED]');
  }
  for (const pattern of TOKEN_PATTERNS) text = text.replace(pattern, '[REDACTED]');
  return text;
}

function splitUtf8Bounded(text, maxChunkBytes) {
  if (!Number.isInteger(maxChunkBytes) || maxChunkBytes < 128 || maxChunkBytes > 8192) {
    throw new Error('INVALID_CUSTOMER_LOG_CHUNK_LIMIT');
  }
  const chunks = [];
  let current = '';
  let bytes = 0;
  for (const char of String(text ?? '')) {
    const charBytes = Buffer.byteLength(char);
    if (bytes + charBytes > maxChunkBytes && current) {
      chunks.push(current);
      current = '';
      bytes = 0;
    }
    current += char;
    bytes += charBytes;
  }
  if (current) chunks.push(current);
  return chunks;
}

function createCustomerOutputChunks({
  stream,
  text,
  secrets = [],
  maxChunkBytes = 2048,
  maxTotalBytes = 16 * 1024,
}) {
  if (!['stdout', 'stderr'].includes(stream)) throw new Error('INVALID_CUSTOMER_LOG_STREAM');
  if (!Number.isInteger(maxTotalBytes) || maxTotalBytes < maxChunkBytes || maxTotalBytes > 128 * 1024) {
    throw new Error('INVALID_CUSTOMER_LOG_TOTAL_LIMIT');
  }
  const redacted = redactText(text, secrets);
  const sourceBytes = Buffer.byteLength(redacted);
  const chunks = [];
  let displayedBytes = 0;
  let truncated = false;
  for (const chunk of splitUtf8Bounded(redacted, maxChunkBytes)) {
    const chunkBytes = Buffer.byteLength(chunk);
    if (displayedBytes + chunkBytes > maxTotalBytes) {
      truncated = true;
      break;
    }
    chunks.push(Object.freeze({ text: chunk, bytes: chunkBytes }));
    displayedBytes += chunkBytes;
  }
  if (displayedBytes < sourceBytes) truncated = true;
  return Object.freeze({
    stream,
    chunks: Object.freeze(chunks),
    sourceBytes,
    displayedBytes,
    truncated,
  });
}

function createLogRecord({ stream, text, executionId, step, maxInlineBytes = 64 * 1024, secrets = [] }) {
  if (!['stdout', 'stderr', 'worker'].includes(stream)) throw new Error('INVALID_LOG_STREAM');
  const redacted = redactText(text, secrets);
  const bytes = Buffer.byteLength(redacted);
  const sha256 = createHash('sha256').update(redacted).digest('hex');
  return Object.freeze({
    schemaVersion: 1,
    executionId,
    step,
    stream,
    sha256,
    bytes,
    inline: bytes <= maxInlineBytes ? redacted : null,
    artifactRequired: bytes > maxInlineBytes,
  });
}

function ownerSafeSummary({ status, failureClass, step }) {
  if (status === 'completed') return `Completed ${step}.`;
  if (status === 'cancelled') return `Stopped ${step}.`;
  const label = ({
    dependency: 'dependency setup',
    syntax: 'generated code',
    type: 'type checking',
    compile: 'build compilation',
    test: 'tests',
    timeout: 'time limit',
    resource_limit: 'resource limit',
    network: 'network access',
    configuration: 'configuration',
    filesystem: 'workspace files',
    sandbox: 'build sandbox',
    credential: 'temporary access',
  })[failureClass] ?? 'build execution';
  return `Could not complete ${step} because of ${label}.`;
}

export {
  TOKEN_PATTERNS,
  createCustomerOutputChunks,
  createLogRecord,
  ownerSafeSummary,
  redactText,
  splitUtf8Bounded,
};
