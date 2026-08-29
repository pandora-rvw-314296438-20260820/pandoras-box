const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const test = require('node:test');

const root = join(__dirname, '..');

function read(path) {
  return readFileSync(join(root, path), 'utf8');
}

test('canonical source, Vercel identity, and live status are the recovery operating set', () => {
  const policy = JSON.parse(read('SOURCE_AUTHORITY_POLICY.json'));
  const denylist = read('docs/governance/DEPRECATED_SOURCE_DENYLIST.md');
  const identity = read('docs/status/CURRENT_OPERATING_IDENTITY.md');
  const recovery = read('docs/status/CURRENT_RECOVERY_POSTURE.md');
  const pack = JSON.parse(read('package.json'));
  const vercel = JSON.parse(read('vercel.json'));
  const historical = JSON.parse(read('docs/status/HISTORICAL_STATUS_SURFACES.json'));

  assert.equal(policy.mode, 'fail_closed');
  assert.equal(policy.canonical.source_repository, 'pandora-rvw-314296438-20260820/pandoras-box');
  assert.equal(policy.canonical.memory_repository, 'banataosystems/pandoras-box-memory');
  assert.equal(policy.canonical.vercel_project_id, 'prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk');
  assert.equal(policy.canonical.vercel_project_name, 'mcpmaster');
  assert.equal(policy.canonical.production_origin, 'https://mcpmaster.vercel.app');
  assert.equal(policy.canonical.live_status, 'GET /api/operator/status');
  assert.ok(policy.deprecated_operational_sources.some((source) =>
    source.type === 'github_owner' &&
    source.value === 'mbanatao' &&
    source.wildcard === 'mbanatao/*' &&
    source.status === 'historical_only'));
  assert.ok(policy.recovery_era_siblings.some((source) =>
    source.value === 'banataosystems/Pandoras-box' &&
    source.status === 'recovery_era_name_not_operational_remote'));
  assert.ok(policy.forbidden_uses.includes('cite_integrity_bound_historical_status_surfaces_as_current_state'));
  assert.ok(policy.forbidden_uses.includes('recreate_canonical_vercel_project_or_production_alias'));

  assert.match(denylist, /Canonical source repository: `pandora-rvw-314296438-20260820\/pandoras-box`/);
  assert.match(denylist, /prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk/);
  assert.match(denylist, /https:\/\/mcpmaster\.vercel\.app/);
  assert.match(denylist, /mbanatao\/\*/);
  assert.doesNotMatch(denylist, /Canonical source repository: `banataosystems\/Pandoras-box`/);

  assert.match(identity, /pandora-rvw-314296438-20260820\/pandoras-box/);
  assert.match(identity, /prj_Y5rZVcq8xJVzHVt4uvfmg9wPvXMk/);
  assert.match(identity, /https:\/\/mcpmaster\.vercel\.app/);
  assert.match(identity, /GET \/api\/operator\/status/);
  assert.match(identity, /mbanatao\/\* is historical evidence only/);
  assert.match(identity, /Never commit bypass secrets/);

  assert.match(recovery, /Do not rewrite `RECOVERY_STATUS\.md`/);
  assert.match(recovery, /Do not treat a green CI SHA as a production release/);
  assert.match(recovery, /cc0421f4461219bd6a9e864295d70743e8cd32dc/);

  assert.equal(pack.repository.url, 'git+https://github.com/pandora-rvw-314296438-20260820/pandoras-box.git');
  assert.equal(vercel.env.PROJECTOS_MCP_RESOURCE_ORIGIN, 'https://mcpmaster.vercel.app');
  assert.equal(historical.supersededBy, '/api/operator/status');
  assert.equal(historical.classification, 'historical_only');
  assert.equal(
    historical.surfaces.some((surface) => surface.path === 'docs/status/CURRENT_OPERATING_IDENTITY.md'),
    false,
  );
  assert.equal(
    historical.surfaces.some((surface) => surface.path === 'docs/status/CURRENT_RECOVERY_POSTURE.md'),
    false,
  );
});

test('product screen master plan does not invent a 112-page inventory or production verification', () => {
  const plan = read('docs/product/PANDORA_SCREEN_MASTER_PLAN.md');
  assert.match(plan, /Implemented on canonical native Android/);
  assert.match(plan, /Remaining owner-facing surfaces/);
  assert.match(plan, /documented \/ implemented \/ tested \/ deployed \/ production verified/);
  assert.match(plan, /No literal 112-page inventory exists in canonical source/);
  assert.match(plan, /Not production-verified/);
  assert.doesNotMatch(plan, /112 screens implemented/);
});
