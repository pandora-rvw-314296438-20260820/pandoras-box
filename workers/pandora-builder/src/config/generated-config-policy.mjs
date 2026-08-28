const LIFECYCLE = new Set(['preinstall', 'install', 'postinstall', 'prepare']);
const SENSITIVE_NPM_KEYS = /(_authToken|_password|username|always-auth)\s*=/i;
function inspectPackageJson(packageJson, { allowLifecycleScripts = [] } = {}) {
  if (!packageJson || typeof packageJson !== 'object' || Array.isArray(packageJson)) throw new Error('INVALID_PACKAGE_JSON');
  const scripts = packageJson.scripts ?? {}; if (typeof scripts !== 'object' || Array.isArray(scripts)) throw new Error('INVALID_PACKAGE_SCRIPTS');
  const allowed = new Set(allowLifecycleScripts); const forbidden = [];
  for (const [name, command] of Object.entries(scripts)) { if (typeof command !== 'string' || command.length > 16_384) throw new Error('INVALID_PACKAGE_SCRIPT'); if (LIFECYCLE.has(name) && !allowed.has(name)) forbidden.push(name); }
  if (forbidden.length) { const error = new Error('PACKAGE_LIFECYCLE_SCRIPT_REQUIRES_EXPLICIT_AUTHORIZATION'); error.scripts = forbidden.sort(); throw error; }
  return Object.freeze({ lifecycleScripts: Object.freeze(Object.keys(scripts).filter((name) => LIFECYCLE.has(name)).sort()) });
}
function inspectNpmrc(text) { if (typeof text !== 'string') throw new Error('INVALID_NPMRC'); if (SENSITIVE_NPM_KEYS.test(text)) throw new Error('PERSISTED_REGISTRY_CREDENTIAL_FORBIDDEN'); const registries = [...text.matchAll(/^\s*registry\s*=\s*(\S+)\s*$/gmi)].map((match) => match[1]); for (const registry of registries) { const url = new URL(registry); if (url.protocol !== 'https:' || url.username || url.password) throw new Error('UNSAFE_PACKAGE_REGISTRY'); } return Object.freeze({ registries: Object.freeze(registries) }); }
function validateGeneratedConfig({ packageJson = null, npmrc = null, allowLifecycleScripts = [] } = {}) { const report = {}; if (packageJson) report.packageJson = inspectPackageJson(packageJson, { allowLifecycleScripts }); if (npmrc != null) report.npmrc = inspectNpmrc(npmrc); return Object.freeze(report); }
export { inspectNpmrc, inspectPackageJson, validateGeneratedConfig };
