const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(process.cwd(), 'apps/pandora-mobile/lib/features/simple/simple_home_screen.dart'),
  'utf8',
);

test('home refreshes authoritative project summary after returning from creation journey', () => {
  assert.equal(source.includes('Future<void> _create(String value) async {'), true);
  assert.equal(source.includes('await Navigator.of(context).push('), true);
  assert.equal(source.includes('CreateProjectExperienceScreen(initialIntent: value)'), true);
  assert.equal(source.includes('if (mounted) await _load();'), true);
});

test('creation navigation is not fire-and-forget', () => {
  assert.equal(source.includes('void _create(String value) => Navigator.of(context).push('), false);
});
