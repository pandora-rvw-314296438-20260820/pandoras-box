import { createHash } from 'node:crypto';

export const CONTRACT = 'pandora-ares-host-v1';
export const PACKAGES = Object.freeze([
  'com.banataosystems.pandora_mobile',
  'com.banataosystems.pandora.plp',
]);
export const OPERATIONS = Object.freeze({
  'ares.health.read': { risk: 'read', app: false },
  'ares.emulator.start': { risk: 'preview', app: false },
  'ares.emulator.stop': { risk: 'preview', app: false },
  'ares.apk.install': { risk: 'preview', app: true, artifact: true },
  'ares.apk.uninstall': { risk: 'destructive', app: true, artifact: true },
  'ares.app.clear_data': { risk: 'destructive', app: true, artifact: true },
  'ares.ui.test': { risk: 'preview', app: true, artifact: true },
  'ares.test.run': { risk: 'preview', app: true, artifact: true },
  'ares.evidence.read': { risk: 'read', app: true },
  'ares.permission.change': { risk: 'destructive', app: true, artifact: true },
  'ares.network.configure': { risk: 'preview', app: false },
});
export const RUNTIME_PERMISSIONS = Object.freeze([
  'android.permission.CAMERA',
  'android.permission.RECORD_AUDIO',
  'android.permission.POST_NOTIFICATIONS',
  'android.permission.ACCESS_COARSE_LOCATION',
  'android.permission.ACCESS_FINE_LOCATION',
]);
const UUID = /^[a-f0-9]{8}-[a-f0-9]{4}-[1-5][a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$/;
export const SHA256 = /^[a-f0-9]{64}$/;
const SOURCE = /^[a-f0-9]{40}$/;
const IDENTIFIER = /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,159}$/;
const SECRET = /(?:github_pat_[A-Za-z0-9_]{12,}|gh[pousr]_[A-Za-z0-9_]{16,}|sb_secret_[A-Za-z0-9_-]{12,}|AIza[A-Za-z0-9_-]{20,}|Bearer\s+[A-Za-z0-9._~-]{12,}|-----BEGIN [^-]*PRIVATE KEY)/i;

export class AresError extends Error {
  constructor(code, { sideEffectPossible = false } = {}) {
    super(/^ARES_[A-Z0-9_]{1,80}$/.test(code) ? code : 'ARES_INTERNAL_ERROR');
    this.name = 'AresError';
    this.code = this.message;
    this.sideEffectPossible = sideEffectPossible === true;
  }
}
export function demand(condition, code) {
  if (!condition) throw new AresError(code);
}
export function plain(x) {
  return x !== null && typeof x === 'object' && !Array.isArray(x)
    && [Object.prototype, null].includes(Object.getPrototypeOf(x));
}
export function exact(x, keys, code = 'ARES_FIELDS_INVALID') {
  demand(plain(x) && Object.keys(x).every(k => keys.includes(k)), code);
}
export function integer(x, low, high, code = 'ARES_INTEGER_INVALID') {
  demand(Number.isSafeInteger(x) && x >= low && x <= high, code);
  return x;
}
export function identifier(x, code = 'ARES_IDENTITY_INVALID') {
  demand(typeof x === 'string' && IDENTIFIER.test(x), code);
  return x;
}
export function immutable(x) {
  if (x && typeof x === 'object' && !Object.isFrozen(x)) {
    for (const v of Object.values(x)) immutable(v);
    Object.freeze(x);
  }
  return x;
}
export function canonical(x) {
  if (x === null || typeof x !== 'object') return JSON.stringify(x);
  if (Array.isArray(x)) return '[' + x.map(canonical).join(',') + ']';
  return '{' + Object.keys(x).sort().map(k => JSON.stringify(k) + ':' + canonical(x[k])).join(',') + '}';
}
export function sha256(x) {
  return createHash('sha256').update(x).digest('hex');
}
export function actionDigest(job) { return sha256(canonical(job)); }
export function rejectSecrets(x) {
  const visit = value => {
    if (value && typeof value === 'object') {
      for (const [key, v] of Object.entries(value)) {
        demand(!/^(?:password|secret|token|apikey|api_key|authorization|credential|privatekey|private_key|service_role|servicerole|env|environmentvariables)$/i.test(key), 'ARES_SECRET_INPUT_DENIED');
        visit(v);
      }
    } else if (typeof value === 'string') demand(!SECRET.test(value), 'ARES_SECRET_INPUT_DENIED');
  };
  visit(x);
}
export function portForSerial(serial) {
  demand(typeof serial === 'string' && /^emulator-[0-9]{4}$/.test(serial), 'ARES_EMULATOR_ONLY');
  const port = Number(serial.slice(9));
  demand(port >= 5554 && port <= 5682 && port % 2 === 0, 'ARES_EMULATOR_PORT_INVALID');
  return port;
}
function normalizeStep(s) {
  exact(s, ['kind', 'x', 'y', 'x2', 'y2', 'durationMs', 'text']);
  const keys = {
    launch: ['kind'], force_stop: ['kind'], back: ['kind'],
    tap: ['kind', 'x', 'y'],
    swipe: ['kind', 'x', 'y', 'x2', 'y2', 'durationMs'],
    type: ['kind', 'text'],
  };
  demand(keys[s.kind], 'ARES_UI_STEP_DENIED');
  exact(s, keys[s.kind]);
  if (s.kind === 'tap' || s.kind === 'swipe') {
    for (const key of (s.kind === 'tap' ? ['x', 'y'] : ['x', 'y', 'x2', 'y2'])) integer(s[key], 0, 16384);
  }
  if (s.kind === 'swipe') integer(s.durationMs, 1, 10000);
  if (s.kind === 'type') demand(typeof s.text === 'string' && /^[A-Za-z0-9 ._-]{1,200}$/.test(s.text), 'ARES_UNSAFE_TEXT');
  return structuredClone(s);
}
export function normalizeJob(raw) {
  exact(raw, ['version', 'requestId', 'organizationId', 'projectId', 'taskId', 'workerId', 'nodeId', 'leaseId', 'generation', 'sourceSha', 'operation', 'target', 'artifactRef', 'parameters', 'timeoutMs', 'profileSha256']);
  demand(raw.version === 1, 'ARES_CONTRACT_VERSION');
  demand(typeof raw.profileSha256 === 'string' && SHA256.test(raw.profileSha256), 'ARES_PROFILE_DIGEST_REQUIRED');
  for (const key of ['organizationId', 'projectId', 'leaseId']) demand(typeof raw[key] === 'string' && UUID.test(raw[key]), 'ARES_SCOPE_INVALID');
  for (const key of ['requestId', 'taskId', 'workerId', 'nodeId']) identifier(raw[key]);
  demand(raw.requestId.length >= 8, 'ARES_REQUEST_ID_INVALID');
  integer(raw.generation, 1, Number.MAX_SAFE_INTEGER);
  demand(typeof raw.sourceSha === 'string' && SOURCE.test(raw.sourceSha), 'ARES_EXACT_SOURCE_REQUIRED');
  const definition = OPERATIONS[raw.operation];
  demand(definition, 'ARES_OPERATION_NOT_REGISTERED');
  exact(raw.target, ['serial', 'avdName', 'packageName']);
  portForSerial(raw.target.serial);
  demand(typeof raw.target.avdName === 'string' && /^[A-Za-z0-9][A-Za-z0-9_.-]{0,79}$/.test(raw.target.avdName) && !raw.target.avdName.includes('..'), 'ARES_AVD_INVALID');
  const packageName = raw.target.packageName ?? null;
  if (packageName !== null) demand(PACKAGES.includes(packageName), 'ARES_PACKAGE_DENIED');
  if (definition.app) demand(PACKAGES.includes(packageName), 'ARES_PACKAGE_REQUIRED');
  const artifactRef = raw.artifactRef ?? null;
  if (artifactRef !== null) demand(typeof artifactRef === 'string' && /^(?:artifact|github-artifact|sha256):[A-Za-z0-9_./:-]{8,300}$/.test(artifactRef), 'ARES_ARTIFACT_REF_INVALID');
  if (definition.artifact) demand(artifactRef !== null, 'ARES_ARTIFACT_REQUIRED');
  const parameters = raw.parameters ?? {};
  demand(plain(parameters), 'ARES_PARAMETERS_INVALID');
  let normalized = structuredClone(parameters);
  switch (raw.operation) {
    case 'ares.ui.test':
      exact(parameters, ['steps']);
      demand(Array.isArray(parameters.steps) && parameters.steps.length >= 1 && parameters.steps.length <= 50, 'ARES_UI_LIMIT');
      normalized = {steps: parameters.steps.map(normalizeStep)};
      break;
    case 'ares.evidence.read':
      exact(parameters, ['kind', 'seconds']);
      demand(['package', 'screenshot', 'video', 'crashes'].includes(parameters.kind), 'ARES_EVIDENCE_KIND');
      if (parameters.kind === 'video') integer(parameters.seconds, 1, 30);
      else demand(parameters.seconds === undefined, 'ARES_UNEXPECTED_PARAMETER');
      break;
    case 'ares.test.run':
      exact(parameters, ['suiteId']);
      identifier(parameters.suiteId, 'ARES_TEST_SUITE_REQUIRED');
      break;
    case 'ares.permission.change':
      exact(parameters, ['permission', 'mode']);
      demand(RUNTIME_PERMISSIONS.includes(parameters.permission) && ['grant', 'revoke'].includes(parameters.mode), 'ARES_PERMISSION_DENIED');
      break;
    case 'ares.network.configure':
      exact(parameters, ['speed', 'delay']);
      demand(['full', 'gsm', 'hscsd', 'gprs', 'edge', 'umts', 'hsdpa', 'lte', 'evdo'].includes(parameters.speed), 'ARES_NETWORK_SPEED');
      demand(['none', 'gprs', 'edge', 'umts'].includes(parameters.delay), 'ARES_NETWORK_DELAY');
      break;
    default: exact(parameters, []);
  }
  rejectSecrets(raw);
  demand(Buffer.byteLength(JSON.stringify(raw), 'utf8') <= 24000, 'ARES_PAYLOAD_LIMIT');
  return immutable({
    version: 1, requestId: raw.requestId, organizationId: raw.organizationId,
    projectId: raw.projectId, taskId: raw.taskId, workerId: raw.workerId,
    nodeId: raw.nodeId, leaseId: raw.leaseId, generation: raw.generation,
    sourceSha: raw.sourceSha, profileSha256: raw.profileSha256, operation: raw.operation,
    target: {serial: raw.target.serial, avdName: raw.target.avdName, packageName},
    artifactRef, parameters: normalized,
    timeoutMs: integer(raw.timeoutMs ?? 60000, 100, 300000, 'ARES_TIMEOUT_INVALID'),
  });
}

export function publicError(error) {
  return error instanceof AresError ? error.code : 'ARES_INTERNAL_ERROR';
}
