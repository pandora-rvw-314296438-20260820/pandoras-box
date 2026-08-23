const assert = require('node:assert/strict');
const { createHash } = require('node:crypto');
const { existsSync, readFileSync } = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const root = path.resolve(__dirname, '..');
const historical = require('../docs/status/HISTORICAL_STATUS_SURFACES.json');
const triage = require('../docs/status/OPEN_PR_TRIAGE.json');

function sha256(file) {
  return createHash('sha256').update(readFileSync(path.join(root, file))).digest('hex');
}

test('every stale status surface is integrity-bound and classified historical', () => {
  assert.equal(historical.classification, 'historical_only');
  assert.equal(historical.supersededBy, '/api/operator/status');
  for (const surface of historical.surfaces) {
    assert.match(surface.contentSha256, /^[0-9a-f]{64}$/);
    assert.equal(sha256(surface.path), surface.contentSha256, surface.path);
  }
  for (const legacyPath of [
    'apps/control-tower/projectos-status.json',
    'public/control-tower/projectos-status.json',
    'apps/control-tower/release.json',
    'public/control-tower/release.json',
  ]) {
    assert.equal(existsSync(path.join(root, legacyPath)), false, legacyPath);
  }
});

test('dated custom-instruction and mirror-manifest state cannot masquerade as current truth', () => {
  const instructionPath = 'PROJECT_CUSTOM_INSTRUCTION.md';
  const manifestPath = 'docs/operating-contracts/GITHUB_PANDORA_MIRROR_MANIFEST.csv';
  const instruction = readFileSync(path.join(root, instructionPath), 'utf8');
  const manifest = readFileSync(path.join(root, manifestPath), 'utf8');
  const classified = new Map(
    historical.surfaces.map((surface) => [surface.path, surface]),
  );

  assert.equal(
    classified.get(instructionPath)?.classification,
    'normative_instruction_with_historical_operational_sections',
  );
  assert.equal(
    classified.get(manifestPath)?.classification,
    'historical_mirror_integrity_snapshot',
  );
  assert.match(instruction, /Operational-status notice/);
  assert.match(instruction, /Historical verified-state snapshot \(2026-08-08\)/);
  assert.match(instruction, /Historical dependency-ordered roadmap \(2026-08-08\)/);
  assert.match(instruction, /Historical immediate highest-value safe action \(2026-08-08\)/);
  assert.match(instruction, /authenticated `\/api\/operator\/status`/);
  assert.doesNotMatch(instruction, /Pandora Memory is the operating source of truth/);

  assert.match(manifest, /# classification: historical_only/);
  assert.match(
    manifest,
    /# current_operational_truth: authenticated \/api\/operator\/status/,
  );
  assert.match(manifest, /# historical_blocker_at_capture:/);
  assert.match(manifest, /# historical_next_action_at_capture:/);
  assert.doesNotMatch(manifest, /^# current_blocker:/m);
  assert.doesNotMatch(manifest, /^# next_autonomous_action:/m);
  const rows = manifest
    .trim()
    .split(/\r?\n/)
    .filter((line) => !line.startsWith('#'))
    .map((line) => line.split(','));
  const header = rows.shift();
  const projectKey = header.indexOf('project_key');
  const canonStatus = header.indexOf('canon_status');
  const pandorasBox = rows.find(
    (row) => row[projectKey] === 'mcpmaster-pandoras-box',
  );
  assert.equal(pandorasBox[canonStatus], 'historical_snapshot');
  assert.equal(
    rows.filter((row) => row[projectKey] !== 'mcpmaster-pandoras-box')
      .every((row) => row[canonStatus] === 'hard_canon'),
    true,
    'unrelated normative mirror records were reclassified',
  );
});

test('Control Tower consumes the authenticated canonical pack, not the dead projectos route', () => {
  const loader = readFileSync(path.join(root, 'apps/control-tower/projectos-live-fetch.js'), 'utf8');
  assert.match(loader, /legacyStatusRequest \? '\/api\/operator\/status'/);
  assert.doesNotMatch(loader, /legacyStatusRequest \? '\/api\/projectos'/);
  const app = readFileSync(path.join(root, 'apps/control-tower/app.js'), 'utf8');
  const ownerData = readFileSync(path.join(root, 'apps/control-tower/owner-data.js'), 'utf8');
  assert.match(app, /projectos\.authoritative === true/);
  assert.match(app, /projectos\.status === "current"/);
  assert.match(ownerData, /projection\.authoritative === true/);
  assert.match(ownerData, /projection\.status === 'current'/);
});

test('legacy status URLs are quarantined before static serving', () => {
  const container = readFileSync(path.join(root, 'src/projectos-container-server.js'), 'utf8');
  const vercel = readFileSync(path.join(root, 'vercel.json'), 'utf8');
  assert.match(container, /HISTORICAL_STATUS_SURFACE_GONE/);
  assert.match(container, /response\.status\(410\)/);
  assert.match(vercel, /"source": "\/control-tower\/projectos-status\.json", "destination": "\/api\/operator\/status"/);
  assert.match(vercel, /"source": "\/control-tower\/release\.json", "destination": "\/api\/operator\/status"/);
});

test('the shared container wires the canonical status and worker-context providers', () => {
  const container = readFileSync(path.join(root, 'src/projectos-container-server.js'), 'utf8');
  assert.match(container, /createCanonicalStatusProviderFromEnvironment/);
  assert.match(container, /new worker_plan_context_provider_js_1\.WorkerPlanContextProvider/);
  assert.match(container, /statusProvider,/);
  assert.match(container, /workerContextProvider,/);
  assert.match(container, /__canonicalVercelOidcToken/);
  assert.match(container, /environment\.VERCEL === '1'/);
});

test('the open-PR triage has one exact decision per denominator item', () => {
  assert.equal(triage.total, 41);
  assert.equal(triage.decisions.length, triage.total);
  assert.deepEqual(triage.counts, { land: 1, consolidate: 9, archive: 31, close: 0 });
  assert.equal(new Set(triage.decisions.map((entry) => entry.number)).size, triage.total);
  assert.equal(new Set(triage.decisions.map((entry) => entry.headSha)).size, triage.total);
  for (const decision of triage.decisions) {
    assert.match(decision.headSha, /^[0-9a-f]{40}$/);
    assert.ok(['land', 'consolidate', 'archive', 'close'].includes(decision.decision));
  }
});
