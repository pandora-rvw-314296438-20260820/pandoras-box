import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const screen = await readFile(
  'apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  'utf8',
);
const api = await readFile(
  'apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
  'utf8',
);

// Exact-source mobile gates remain authoritative for format, analysis, tests, and builds.
test('composer keeps files and images while adding services and project context', () => {
  assert.match(screen, /ask-pandora-menu-camera/);
  assert.match(screen, /ask-pandora-menu-photos/);
  assert.match(screen, /ask-pandora-menu-files/);
  assert.match(screen, /ask-pandora-menu-services/);
  assert.match(screen, /ask-pandora-menu-project-context/);
});

test('services come from live capability registry truth instead of hardcoded connected state', () => {
  assert.match(screen, /capabilityRegistry\(\)/);
  assert.match(screen, /registry\.providers/);
  assert.match(screen, /provider\.state/);
  assert.match(screen, /provider\.canUseNow/);
  assert.doesNotMatch(screen, /Gmail is connected|GitHub is connected|Drive is connected/);
});

test('project context comes from existing non-archived ProjectOS projects and is passed explicitly', () => {
  assert.match(api, /Future<List<PandoraProjectContext>> projectContexts/);
  assert.match(api, /from\('projectos_projects'\)/);
  assert.match(api, /\.neq\('status', 'archived'\)/);
  assert.match(screen, /projectId: _projectContext\?\.id/);
  assert.match(screen, /associateThreadWithProject\(threadId, selected\.id\)/);
  assert.match(screen, /associateThreadWithProject\(threadId, null\)/);
});

test('selected contexts stay visible and removable without dashboard chrome', () => {
  assert.match(screen, /ask-pandora-service-context/);
  assert.match(screen, /ask-pandora-project-context/);
  assert.match(screen, /_removeServiceContext/);
  assert.match(screen, /_removeProjectContext/);
  assert.match(screen, /MenuAnchor/);
});
