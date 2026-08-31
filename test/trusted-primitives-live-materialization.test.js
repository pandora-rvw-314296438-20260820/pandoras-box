'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const source = fs.readFileSync(
  path.join(__dirname, '..', 'supabase', 'functions', 'pandora-source-convergence-worker', 'index.ts'),
  'utf8',
);

test('live source worker re-reads exact Worker E trusted primitive source before materialization', () => {
  assert.match(source, /pandora_worker_i_resolve_project_spec_primitives_20260831/);
  assert.match(source, /p_require_trusted:\s*true/);
  assert.match(source, /trustState !== "TRUSTED"/);
  assert.match(source, /workerEEvidenceRef/);
  assert.match(source, /raw\.githubusercontent\.com\/pandora-rvw-314296438-20260820\/pandoras-box\/\$\{commit\}/);
  assert.match(source, /sha256\(path\\0file_sha256\\n sorted by path\)/);
  assert.match(source, /computedBundleDigest !== sourceDigest/);
  assert.match(source, /actualSha !== expectedSha/);
});

test('model cannot own primitive-core files and exact primitive files enter the canonical artifact', () => {
  assert.match(source, /Do not create, modify, duplicate, or reference files under pandora-primitives\//);
  assert.match(source, /path\.startsWith\("pandora-primitives\/"\).*INVALID_GENERATED_SOURCE/s);
  assert.match(source, /materializedPath = `pandora-primitives\/\$\{name\}\/\$\{path\}`/);
  assert.match(source, /canonicalBundle\([\s\S]*primitiveMaterialization\.files/);
  assert.match(source, /PRIMITIVE_SOURCE_COLLISION/);
  assert.match(source, /PRIMITIVE_SOURCE_MISMATCH/);
});

test('Worker D lineage is persisted against the exact resulting project version before queue success', () => {
  assert.match(source, /persistTrustedPrimitiveComposition/);
  assert.match(source, /pandora_project_version_compositions/);
  assert.match(source, /pandora_project_version_primitives/);
  assert.match(source, /manifest_digest:\s*selectionDigest/);
  assert.match(source, /materialization_plan_digest:\s*materialization\.planDigest/);
  assert.match(source, /source_digest:\s*sourceDigest/);
  const intake = source.indexOf('const result = rec(intake.data);');
  const persist = source.indexOf('await persistTrustedPrimitiveComposition(', intake);
  const succeeded = source.indexOf('status: "succeeded"', persist);
  assert.ok(intake >= 0 && persist > intake && succeeded > persist, 'composition must persist after exact build intake and before source queue success');
});

test('legacy build replay cannot bypass missing primitive composition', () => {
  assert.match(source, /requiredPrimitiveCount = primitiveMaterialization\.selections\.length/);
  assert.match(source, /hasPrimitiveComposition = requiredPrimitiveCount === 0/);
  assert.match(source, /pandora_project_version_compositions/);
  assert.match(source, /if \(hasPrimitiveComposition\)/);
});
