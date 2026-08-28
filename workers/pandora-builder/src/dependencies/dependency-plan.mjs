const REGISTRY_HOSTS = Object.freeze({ npm: ['registry.npmjs.org'], pnpm: ['registry.npmjs.org'], yarn: ['registry.yarnpkg.com', 'registry.npmjs.org'], flutter: ['pub.dev', 'storage.googleapis.com'] });
function nodeDependencyPlan(filenames) {
  const files = new Set(filenames);
  if (files.has('pnpm-lock.yaml')) return Object.freeze({ manager: 'pnpm', lockfile: 'pnpm-lock.yaml', executable: 'pnpm', args: ['install', '--frozen-lockfile', '--ignore-scripts'], requiredHosts: REGISTRY_HOSTS.pnpm, lifecycleScripts: 'disabled' });
  if (files.has('yarn.lock')) return Object.freeze({ manager: 'yarn', lockfile: 'yarn.lock', executable: 'yarn', args: ['install', '--immutable', '--mode=skip-builds'], requiredHosts: REGISTRY_HOSTS.yarn, lifecycleScripts: 'disabled' });
  if (files.has('npm-shrinkwrap.json')) return Object.freeze({ manager: 'npm', lockfile: 'npm-shrinkwrap.json', executable: 'npm', args: ['ci', '--ignore-scripts', '--no-audit', '--no-fund'], requiredHosts: REGISTRY_HOSTS.npm, lifecycleScripts: 'disabled' });
  if (files.has('package-lock.json')) return Object.freeze({ manager: 'npm', lockfile: 'package-lock.json', executable: 'npm', args: ['ci', '--ignore-scripts', '--no-audit', '--no-fund'], requiredHosts: REGISTRY_HOSTS.npm, lifecycleScripts: 'disabled' });
  throw new Error('NODE_LOCKFILE_REQUIRED');
}
function dependencyInstallPlan({ adapter, filenames = [] }) {
  if (adapter.dependencyKind === 'none') return null;
  if (adapter.dependencyKind === 'node') return nodeDependencyPlan(filenames);
  if (adapter.dependencyKind === 'flutter') { if (!filenames.includes('pubspec.lock')) throw new Error('FLUTTER_LOCKFILE_REQUIRED'); return Object.freeze({ manager: 'flutter-pub', lockfile: 'pubspec.lock', executable: 'flutter', args: ['pub', 'get'], requiredHosts: REGISTRY_HOSTS.flutter, lifecycleScripts: 'not_applicable' }); }
  throw new Error('UNSUPPORTED_DEPENDENCY_KIND');
}
export { REGISTRY_HOSTS, dependencyInstallPlan, nodeDependencyPlan };
