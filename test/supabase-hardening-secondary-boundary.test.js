'use strict';

const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { test } = require('node:test');

const repository = path.resolve(__dirname, '..');
const script = path.join(repository, 'scripts/verify-supabase-hardening.mjs');
const policyRoot = 'ops/supabase/hardening';
const policies = ['edge-function-lifecycle-registry.json', 'security-advisor-dispositions.json', 'plane-boundary-policy.json'];
const policyBytes = Object.fromEntries(policies.map(name => [name, fs.readFileSync(path.join(repository, policyRoot, name))]));
const registry = JSON.parse(policyBytes[policies[0]]);
const secondary = registry.projects.secondary;
const runtimePath = 'apps/pandora-mobile/lib/core/config/pandora_runtime_binding.dart';
const testPath = 'apps/pandora-mobile/test/core/config/pandora_runtime_binding_test.dart';
const runtime = fs.readFileSync(path.join(repository, runtimePath), 'utf8');
const rejectionTest = fs.readFileSync(path.join(repository, testPath), 'utf8');
const guardStart = runtime.indexOf('    final ref = acceptanceProjectRef!;');
const guardEnd = runtime.indexOf('    if (!_matches(_organization', guardStart);
assert.ok(guardStart >= 0 && guardEnd > guardStart);
const rejectionGuard = runtime.slice(guardStart, guardEnd);

function replace(source, before, after) {
  assert.ok(source.includes(before), `fixture mutation must reach ${before}`);
  return source.replace(before, after);
}

function runGuard(t, overrides = {}) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'pandora-secondary-boundary-'));
  t.after(() => fs.rmSync(directory, { recursive: true, force: true }));
  for (const [name, bytes] of Object.entries(policyBytes)) {
    const target = path.join(directory, policyRoot, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, bytes);
  }
  for (const [name, source] of Object.entries({ [runtimePath]: runtime, [testPath]: rejectionTest, ...overrides })) {
    const target = path.join(directory, name);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, source);
  }
  const result = spawnSync(process.execPath, [script], { cwd: directory, encoding: 'utf8', timeout: 10000 });
  assert.equal(result.error, undefined);
  return result;
}

test('real hardening guard permits the reviewed executable denial and its actual rejection test', t => {
  const result = runGuard(t);
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Supabase hardening registry checks passed/);
});

test('reviewed denial tokens remain valid with harmless formatting and nested comments', t => {
  const result = runGuard(t, {
    [runtimePath]: replace(runtime, 'final ref = acceptanceProjectRef!;', 'final /* outer /* nested */ comment */ ref =\n acceptanceProjectRef!;'),
    [testPath]: ('/* harmless registration comment */\n' + rejectionTest).replaceAll('\n', '\r\n'),
  });
  assert.equal(result.status, 0, result.stderr);
});

const cases = [
  ['negated runtime denial', runtimePath, replace(runtime, "const {'", "!const {'")],
  ['weakened runtime OR condition', runtimePath, replace(runtime, 'if (!_matches(_ref, ref) ||', 'if (!_matches(_ref, ref) &&')],
  ['runtime deny becomes an accepting return', runtimePath, replace(runtime, "throw const PandoraRuntimeBindingException('ACCEPTANCE_PROJECT_INVALID');", 'return production;')],
  ['runtime denial loses its throw', runtimePath, replace(runtime, "throw const PandoraRuntimeBindingException('ACCEPTANCE_PROJECT_INVALID');", '')],
  ['runtime denial adds a dispatch before throwing', runtimePath, replace(runtime, "throw const PandoraRuntimeBindingException('ACCEPTANCE_PROJECT_INVALID');", "dispatch(ref); throw const PandoraRuntimeBindingException('ACCEPTANCE_PROJECT_INVALID');")],
  ['runtime denial is nested in an unreachable branch', runtimePath, replace(runtime, rejectionGuard, `if (false) {\n${rejectionGuard}}\n`)],
  ['runtime denial is copied into a comment', runtimePath, replace(runtime, rejectionGuard, `/* ${rejectionGuard} */\n`)],
  ['runtime denial is copied into a raw multiline string', runtimePath, replace(runtime, rejectionGuard, `final copy = r'''${rejectionGuard}''';\n`)],
  ['runtime denial is preceded by an early accepting return', runtimePath, replace(runtime, rejectionGuard, `return production;\n${rejectionGuard}`)],
  ['runtime denial is duplicated in a comment', runtimePath, runtime + `\n// ${secondary}\n`],
  ['test changes its expected denial to another result', testPath, replace(rejectionTest, "code('ACCEPTANCE_PROJECT_INVALID')", "code('ACCEPTANCE_TARGET_MISMATCH')")],
  ['test becomes a positive assertion', testPath, replace(rejectionTest, "code('ACCEPTANCE_PROJECT_INVALID')", 'returnsNormally')],
  ['test removes its assertion call', testPath, replace(rejectionTest, "      expect(\n          () => acceptanceProfileBinding(\n              overrides: {'acceptanceProjectRef': ref}),\n          code('ACCEPTANCE_PROJECT_INVALID'));", "      acceptanceProfileBinding(overrides: {'acceptanceProjectRef': ref});")],
  ['test is explicitly skipped', testPath, replace(rejectionTest, "          code('ACCEPTANCE_PROJECT_INVALID'));\n    });", "          code('ACCEPTANCE_PROJECT_INVALID'));\n    }, skip: true);")],
  ['test is nested in a false branch', testPath, replace(rejectionTest, '  for (final ref in [', '  if (false) for (final ref in [')],
  ['test main returns before registration', testPath, replace(rejectionTest, 'void main() {', 'void main() { return;')],
  ['test main exits before registration', testPath, replace(rejectionTest, 'void main() {', 'void main() { exit(0);')],
  ['test iterable runs interpolated code before registering its cases', testPath, replace(rejectionTest, "    'not-a-project',", "    '${(() { throw StateError(\"registration aborted\"); })()}',")],
  ['test library is skipped', testPath, "@Skip('disabled')\nlibrary;\n" + rejectionTest],
  ['test matcher is replaced with a positive matcher', testPath, replace(rejectionTest, 'Matcher code(String value) => throwsA(', 'Matcher code(String value) => returnsNormally(')],
  ['test helper is shadowed before main', testPath, replace(rejectionTest, 'void main() {', 'void test(Object name, Object body) {}\nvoid main() {')],
  ['test helper is shadowed after main', testPath, rejectionTest + '\nvoid test(Object name, Object body) {}\n'],
  ['test adds URL dispatch inside the accepted loop', testPath, replace(rejectionTest, "    test('rejects forbidden or malformed project $ref', () {", "    dispatch('https://$ref.supabase.co');\n    test('rejects forbidden or malformed project $ref', () {")],
  ['test contains an additional bare target', testPath, rejectionTest + `\nconst directTarget = '${secondary}';\n`],
];

for (const [name, file, source] of cases) {
  test(`real guard rejects ${name}`, t => {
    const result = runGuard(t, { [file]: source });
    assert.equal(result.status, 1, result.stdout);
    assert.match(result.stderr, /Simple Mode secondary reference:/);
  });
}

for (const file of [runtimePath, testPath, 'apps/pandora-mobile/lib/pandora_config.dart', 'apps/pandora-mobile/config.json']) {
  test(`a direct secondary URL is rejected even in ${file}`, t => {
    const original = file === runtimePath ? runtime : file === testPath ? rejectionTest : '';
    const source = file.endsWith('.json')
      ? JSON.stringify({ supabaseUrl: `https://${secondary}.supabase.co` })
      : original + `\nconst target = 'https://${secondary}.supabase.co';\n`;
    const result = runGuard(t, { [file]: source });
    assert.equal(result.status, 1, result.stdout);
    assert.match(result.stderr, /Simple Mode secondary reference:/);
  });
}

test('copying the complete approved denial into an unrelated mobile path is not an exemption', t => {
  const result = runGuard(t, { 'apps/pandora-mobile/lib/copied_guard.dart': runtime });
  assert.equal(result.status, 1, result.stdout);
  assert.match(result.stderr, /Simple Mode secondary reference:.*copied_guard\.dart/);
});

test('a commented or quoted test copy cannot supply an executable rejection test', t => {
  for (const source of [`/* ${rejectionTest} */`, `const copy = r'''${rejectionTest}''';`]) {
    const result = runGuard(t, { [testPath]: source });
    assert.equal(result.status, 1, result.stdout);
    assert.match(result.stderr, /Simple Mode secondary reference:/);
  }
});
