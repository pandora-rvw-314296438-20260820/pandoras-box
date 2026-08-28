import { validateGeneratedConfig } from './generated-config-policy.mjs';

const REMOTE_ADD = /^\s*ADD\s+https?:\/\//im;
const SECRET_MOUNT = /--mount=type=secret|\/run\/secrets\//i;

function inspectDockerfile(text) {
  if (text == null) return null;
  if (typeof text !== 'string' || text.length > 512 * 1024) throw new Error('INVALID_DOCKERFILE');
  if (REMOTE_ADD.test(text)) throw new Error('DOCKERFILE_REMOTE_ADD_FORBIDDEN');
  if (SECRET_MOUNT.test(text)) throw new Error('DOCKERFILE_SECRET_MOUNT_FORBIDDEN');
  return Object.freeze({ present: true, executableByWorkerD: false });
}

function validateSafeGeneratedConfig({ packageJson = null, npmrc = null, dockerfile = null, allowLifecycleScripts = [] } = {}) {
  const base = validateGeneratedConfig({ packageJson, npmrc, allowLifecycleScripts });
  return Object.freeze({ ...base, dockerfile: inspectDockerfile(dockerfile) });
}

export { inspectDockerfile, validateSafeGeneratedConfig };
