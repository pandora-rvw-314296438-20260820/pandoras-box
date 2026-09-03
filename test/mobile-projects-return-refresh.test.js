const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(process.cwd(), 'apps/pandora-mobile/lib/features/simple/projects_screen.dart'),
  'utf8',
);

test('systems create action awaits creation journey and reloads authoritative list', () => {
  assert.equal(source.includes('Future<void> _create() async {'), true);
  assert.equal(source.includes('await Navigator.of(context).push('), true);
  assert.equal(source.includes('builder: (_) => const CreateProjectExperienceScreen()'), true);
  assert.equal(source.includes('if (mounted) await _load();'), true);
  assert.equal(source.includes('onPressed: _create'), true);
  assert.equal(source.includes('onAction: _create'), true);
});
