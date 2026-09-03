const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');

const source = fs.readFileSync(
  'apps/pandora-mobile/lib/features/simple/project_create_experience.dart',
  'utf8',
);

test('project creation reuses one idempotency key for the same intent until the journey advances', () => {
  assert.equal(source.includes("String? _createIntent;"), true);
  assert.equal(source.includes("String? _createIdempotencyKey;"), true);
  assert.equal(
    source.includes('_createIntent == intent && _createIdempotencyKey != null'),
    true,
  );
  assert.equal(source.includes('idempotencyKey: createKey'), true);
  assert.equal(source.includes('_createIntent = null;'), true);
  assert.equal(source.includes('_createIdempotencyKey = null;'), true);
});

test('ambiguous create transport outcome tells the customer safe retry will resume instead of duplicate', () => {
  assert.equal(source.includes("import '../../core/network/pandora_api_error.dart';"), false);
  assert.equal(source.includes('on PandoraRepositoryException catch (error)'), true);
  assert.equal(source.includes('on PandoraApiError catch (error)'), false);
  assert.equal(source.includes('error.outcomeMayBeUnknown'), true);
  assert.equal(
    source.includes('Pandora will safely resume it instead of creating another project.'),
    true,
  );
});


test('build admission reuses one idempotency key until an admitted build is returned', () => {
  assert.equal(source.includes('String? _buildIdempotencyKey;'), true);
  assert.equal(source.includes('_buildIdempotencyKey ??='), true);
  assert.equal(source.includes('idempotencyKey: _buildIdempotencyKey!'), true);
  assert.equal(source.includes('_buildIdempotencyKey = null;'), true);
  assert.equal(
    source.includes('Keep the same admission key so retry cannot duplicate an already-admitted build.'),
    true,
  );
});
