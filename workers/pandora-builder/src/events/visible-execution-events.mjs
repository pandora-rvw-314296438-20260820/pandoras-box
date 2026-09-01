import { redactText } from '../logs/log-records.mjs';

const VISIBLE_EXECUTION_EVENT_TYPES = new Set([
  'command_started',
  'stdout_chunk',
  'stderr_chunk',
  'command_completed',
  'compile_started',
  'compile_diagnostic',
  'compile_completed',
  'test_started',
  'test_result',
  'test_completed',
  'repair_started',
  'repair_completed',
  'file_started',
  'code_chunk',
  'file_completed',
]);

const SECRET_KEY = /(?:secret|token|password|authorization|cookie|private.?key|api.?key|credential)/i;

function assertNoSecretKeys(value, path = 'payload') {
  if (value == null || typeof value !== 'object') return;
  if (Array.isArray(value)) {
    value.forEach((entry, index) => assertNoSecretKeys(entry, `${path}[${index}]`));
    return;
  }
  for (const [key, child] of Object.entries(value)) {
    if (SECRET_KEY.test(key)) throw new Error(`UNSAFE_VISIBLE_EVENT_KEY:${path}.${key}`);
    assertNoSecretKeys(child, `${path}.${key}`);
  }
}

function safeDisplayCommand(command, secrets = []) {
  if (!command || typeof command.executable !== 'string' || !Array.isArray(command.args)) {
    throw new Error('VISIBLE_COMMAND_REQUIRED');
  }
  const args = command.args.map((arg) => {
    if (/^(?:\/|[A-Za-z]:[\\/])/.test(arg)) return '<project-path>';
    return redactText(arg, secrets);
  });
  const argv = [command.executable, ...args].join(' ');
  return redactText(argv, secrets).replace(/\s+/g, ' ').trim().slice(0, 512);
}

function createVisibleExecutionEvent({
  type,
  request,
  stepKey,
  commandClass = null,
  payload = {},
  filePath = null,
  contentChunk = null,
  at = new Date().toISOString(),
}) {
  if (!VISIBLE_EXECUTION_EVENT_TYPES.has(type)) throw new Error('INVALID_VISIBLE_EXECUTION_EVENT_TYPE');
  if (!request?.buildJobId || !request?.projectId || !request?.organizationId) {
    throw new Error('VISIBLE_EXECUTION_IDENTITY_REQUIRED');
  }
  if (typeof stepKey !== 'string' || stepKey.length < 1 || stepKey.length > 160) {
    throw new Error('VISIBLE_EXECUTION_STEP_REQUIRED');
  }
  const sourceEvent = ['file_started', 'code_chunk', 'file_completed'].includes(type);
  const pathEvent = sourceEvent || type === 'compile_diagnostic';
  if (pathEvent && filePath != null) {
    if (typeof filePath !== 'string' || !filePath || filePath.startsWith('/') || filePath.includes('..') || filePath.includes('\\')) {
      throw new Error('VISIBLE_SOURCE_FILE_PATH_INVALID');
    }
  }
  if (sourceEvent) {
    if (typeof filePath !== 'string') throw new Error('VISIBLE_SOURCE_FILE_PATH_INVALID');
    if (type === 'code_chunk' && (typeof contentChunk !== 'string' || contentChunk.length === 0)) {
      throw new Error('VISIBLE_SOURCE_CONTENT_REQUIRED');
    }
    if (type !== 'code_chunk' && contentChunk != null) throw new Error('VISIBLE_SOURCE_CONTENT_FORBIDDEN');
  } else if (contentChunk != null || (filePath != null && type !== 'compile_diagnostic')) {
    throw new Error('VISIBLE_SOURCE_FIELDS_FORBIDDEN');
  }

  const safePayload = {
    step_key: stepKey,
    attempt: request.attempt,
    ...(commandClass ? { command_class: commandClass } : {}),
    ...payload,
  };
  assertNoSecretKeys(safePayload);
  if (Buffer.byteLength(JSON.stringify(safePayload)) > 16 * 1024) {
    throw new Error('VISIBLE_EXECUTION_PAYLOAD_TOO_LARGE');
  }
  return Object.freeze({
    schemaVersion: 2,
    eventType: type,
    executionId: request.executionId ?? null,
    organizationId: request.organizationId,
    projectId: request.projectId,
    projectVersionId: request.projectVersionId ?? null,
    buildJobId: request.buildJobId,
    attempt: request.attempt ?? null,
    at,
    filePath: pathEvent ? filePath : null,
    contentChunk: type === 'code_chunk' ? contentChunk : null,
    safePayload: Object.freeze(safePayload),
  });
}

async function emitVisibleExecutionEvent(eventSink, event) {
  if (typeof eventSink !== 'function') return null;
  return eventSink(event);
}

export {
  VISIBLE_EXECUTION_EVENT_TYPES,
  createVisibleExecutionEvent,
  emitVisibleExecutionEvent,
  safeDisplayCommand,
};
