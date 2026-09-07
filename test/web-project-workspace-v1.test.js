const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const auth = read('apps/control-tower/auth.js');
const data = read('apps/control-tower/owner-data.js');
const app = read('apps/control-tower/owner-app.js');
const workspace = read('apps/control-tower/owner-project-workspace.js');
const experience = read('apps/control-tower/owner-screens-experience.js');
const first = read('apps/control-tower/owner-first.js');
const index = read('apps/control-tower/index.html');
const ownerContract = read('supabase/functions/pandora-owner-api/contract.ts');
const runtime = read('supabase/functions/pandora-project-runtime/index.ts');

test('Project Workspace is an internal route without changing Simple primary navigation', () => {
  assert.ok(data.includes("'home', 'projects', 'project', 'ask', 'needs', 'business'"));
  const navigation = experience.match(/const items = \[[\s\S]*?\n  \];/);
  assert.ok(navigation);
  const labels = [...navigation[0].matchAll(/\['[^']+', '([^']+)'/g)].map((match) => match[1]);
  assert.deepEqual(labels, ['Home', 'Projects', 'Ask Pandora', 'Needs You', 'Business']);
  assert.ok(app.includes("navigate('project', { resource: project.id })"));
});

test('browser project reads are fixed to owner/runtime boundaries and two member-safe projections', () => {
  assert.ok(auth.includes("'pandora-owner-api'"));
  assert.ok(auth.includes("'pandora-project-runtime'"));
  assert.ok(auth.includes('pandora_project_experience_projection'));
  assert.ok(auth.includes('pandora_build_theatre_projection'));
  assert.ok(auth.includes('PROJECT_PROJECTION_COLUMNS'));
  assert.ok(auth.includes('readProjectProjection'));
  assert.ok(auth.includes('edgeRequest'));
  assert.doesNotMatch(auth, /Github_supabase|SUPABASE_SERVICE_ROLE|gemini_api_key|openai_api_key|moonshot_api_key/i);
});

test('both canonical production web origins are explicitly allowed without wildcard CORS', () => {
  assert.ok(ownerContract.includes('"https://mcpmaster.vercel.app"'));
  assert.ok(ownerContract.includes('"https://pandoras-box-system.vercel.app"'));
  assert.ok(runtime.includes('"https://mcpmaster.vercel.app"'));
  assert.ok(runtime.includes('"https://pandoras-box-system.vercel.app"'));
  assert.doesNotMatch(ownerContract, /access-control-allow-origin["']?\s*[:,]\s*["']\*["']/i);
  assert.doesNotMatch(runtime, /access-control-allow-origin["']?\s*[:,]\s*["']\*["']/i);
});

test('Build Theatre is projection-driven and cannot independently declare Live', () => {
  assert.ok(workspace.includes('item.theatre'));
  assert.ok(workspace.includes("String(experience.experience_state || '').toUpperCase() !== 'LIVE'"));
  assert.ok(workspace.includes('experience.production_deployment_id'));
  assert.ok(workspace.includes('experience.production_version_id'));
  assert.ok(workspace.includes('runtime.production.id !== experience.production_deployment_id'));
  assert.ok(workspace.includes('runtime.production.version_id !== experience.production_version_id'));
});

test('Ready and Publish require canonical experience permission plus runtime publish eligibility', () => {
  assert.ok(workspace.includes('experience.can_publish === true && item.runtime?.verification?.publishEligible === true'));
  assert.ok(workspace.includes('experience.can_publish === true && item.runtime?.verification?.publishEligible === true && Boolean(candidateId)'));
  assert.ok(app.includes('expectedProductionVersionId: item.runtime?.production?.versionId ?? null'));
});

test('Undo is exact-current parent-bound, production-safe, and confirmation precedes mutation', () => {
  assert.ok(workspace.includes('function exactUndoIdentity()'));
  assert.ok(workspace.includes('experience.can_undo !== true'));
  assert.ok(workspace.includes('runtimeVersionId !== currentVersionId'));
  assert.ok(workspace.includes('currentVersionId === productionVersionId'));
  assert.ok(workspace.includes("new Set(['built', 'verification_pending', 'verified', 'preview_ready'])"));
  assert.ok(workspace.includes("action: 'prepare-workspace-undo'"));
  assert.ok(workspace.includes("'confirm-workspace-undo'"));
  assert.ok(app.includes('expectedVersionId: undoIdentity.currentVersionId'));
  assert.ok(app.includes('waitForUndoResolution'));
  assert.ok(app.includes('previewIdentity?.versionId === identity.parentVersionId'));
  assert.ok(app.includes('productionVersionId !== identity.productionVersionId'));
  assert.ok(app.includes('Pandora will not claim success yet'));
  assert.ok(app.includes('idempotencyKey:'));
  assert.ok(app.includes('crypto.randomUUID()'));
  assert.ok(app.indexOf('prepare-workspace-undo') < app.indexOf('confirm-workspace-undo'));
});

test('Publish has an explicit confirmation step before exact runtime mutation', () => {
  assert.ok(workspace.includes("action: 'prepare-workspace-publish'"));
  assert.ok(workspace.includes("'confirm-workspace-publish'"));
  assert.ok(app.includes("performWorkspaceMutation('publish')"));
  assert.ok(app.includes("expectedProductionVersionId: item.runtime?.production?.versionId ?? null"));
  assert.ok(app.indexOf('prepare-workspace-publish') < app.indexOf('confirm-workspace-publish'));
});

test('Tell Pandora carries the exact runtime project UUID through governed change admission', () => {
  assert.ok(app.includes('const projectId = state.projectWorkspace.runtime?.project?.id'));
  assert.ok(app.includes("request('/projects/' + encodeURIComponent(projectId) + '/change'"));
  assert.ok(app.includes('idempotencyKey: item.changeRequestKey'));
  assert.ok(app.includes('...(item.focusToken ? { focusToken: item.focusToken } : {})'));
  assert.ok(app.includes('nextVersion !== baselineVersion'));
  assert.ok(app.includes("nextVersion === candidateVersion && verification === 'passed'"));
  assert.ok(app.includes('nextVersion === currentVersion && experience.current_verified === true'));
  assert.ok(app.includes('previewIdentity?.versionId'));
});

test('Current, Live, and History are first-class workspace views', () => {
  assert.ok(workspace.includes("['current','Current']"));
  assert.ok(workspace.includes("['live','Live']"));
  assert.ok(workspace.includes("['history','History']"));
  assert.ok(workspace.includes('recentReleases'));
  assert.ok(workspace.includes('exactPreviewUrl'));
  assert.ok(workspace.includes('verifiedLiveUrl'));
});

test('project workspace assets are loaded under a distinct cache revision', () => {
  assert.ok(first.includes('owner-project-workspace.js'));
  assert.ok(first.includes('web-publish-truth-v2-20260907-1'));
  assert.ok(index.includes('owner-experience.css?v=web-professional-mode-v1-20260907-1'));
  assert.ok(index.includes('bootstrap.js?v=web-publish-truth-v2-20260907-1'));
});
