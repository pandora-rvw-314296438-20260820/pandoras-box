const ADAPTER_VERSION = '1.0.0';
function frozen(value) { return Object.freeze(value); }
const ADAPTERS = frozen({
  'static-web': frozen({ id: 'static-web', version: ADAPTER_VERSION, platform: 'web', dependencyKind: 'none', install: null, build: null, outputs: frozen([{ path: 'index.html', kind: 'entrypoint' }]), tests: frozen([]) }),
  'node-vite-web': frozen({ id: 'node-vite-web', version: ADAPTER_VERSION, platform: 'web', dependencyKind: 'node', install: frozen({ kind: 'dependency_install' }), build: frozen({ executable: 'node_modules/.bin/vite', args: ['build'] }), outputs: frozen([{ path: 'dist', kind: 'directory' }]), tests: frozen([{ category: 'unit', executable: 'node_modules/.bin/vitest', args: ['run'], optional: true }, { category: 'typecheck', executable: 'node_modules/.bin/tsc', args: ['--noEmit'], optional: true }]) }),
  'node-next-web': frozen({ id: 'node-next-web', version: ADAPTER_VERSION, platform: 'web', dependencyKind: 'node', install: frozen({ kind: 'dependency_install' }), build: frozen({ executable: 'node_modules/.bin/next', args: ['build'] }), outputs: frozen([{ path: '.next', kind: 'directory' }]), tests: frozen([{ category: 'typecheck', executable: 'node_modules/.bin/tsc', args: ['--noEmit'], optional: true }]) }),
  'flutter-web': frozen({ id: 'flutter-web', version: ADAPTER_VERSION, platform: 'web', dependencyKind: 'flutter', install: frozen({ kind: 'dependency_install' }), build: frozen({ executable: 'flutter', args: ['build', 'web', '--release'] }), outputs: frozen([{ path: 'build/web', kind: 'directory' }]), tests: frozen([{ category: 'unit', executable: 'flutter', args: ['test'], optional: false }, { category: 'lint', executable: 'flutter', args: ['analyze'], optional: false }]) }),
  'flutter-android-apk': frozen({ id: 'flutter-android-apk', version: ADAPTER_VERSION, platform: 'android', dependencyKind: 'flutter', install: frozen({ kind: 'dependency_install' }), build: frozen({ executable: 'flutter', args: ['build', 'apk', '--release'] }), outputs: frozen([{ path: 'build/app/outputs/flutter-apk/app-release.apk', kind: 'file' }]), tests: frozen([{ category: 'unit', executable: 'flutter', args: ['test'], optional: false }, { category: 'lint', executable: 'flutter', args: ['analyze'], optional: false }]) }),
});
function hasDependency(packageJson, name) { return Boolean(packageJson?.dependencies?.[name] || packageJson?.devDependencies?.[name]); }
function resolveBuildAdapter({ metadata = {}, filenames = [], packageJson = null } = {}) {
  const requested = metadata.buildAdapter ?? metadata.adapter ?? null;
  if (requested != null) { if (typeof requested !== 'string' || !ADAPTERS[requested]) throw new Error('UNSUPPORTED_BUILD_ADAPTER'); return ADAPTERS[requested]; }
  const files = new Set(filenames.map((value) => String(value).replaceAll('\\', '/')));
  if (files.has('pubspec.yaml')) { const platform = metadata.platform ?? (metadata.platforms?.includes?.('android') ? 'android' : 'web'); if (platform === 'android') return ADAPTERS['flutter-android-apk']; if (platform === 'web') return ADAPTERS['flutter-web']; throw new Error('UNSUPPORTED_FLUTTER_PLATFORM'); }
  if (files.has('package.json')) { if (hasDependency(packageJson, 'next')) return ADAPTERS['node-next-web']; if (hasDependency(packageJson, 'vite')) return ADAPTERS['node-vite-web']; throw new Error('NODE_FRAMEWORK_REQUIRES_EXPLICIT_ADAPTER'); }
  if (files.has('index.html')) return ADAPTERS['static-web'];
  throw new Error('BUILD_ADAPTER_UNRESOLVED');
}
export { ADAPTERS, ADAPTER_VERSION, resolveBuildAdapter };
