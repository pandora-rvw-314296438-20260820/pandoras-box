import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';

const screen = (await Promise.all(['ask_pandora_screen.dart', 'chat/pandora_chat_context_actions.dart']
  .map(file => readFile(`apps/pandora-mobile/lib/features/simple/${file}`, 'utf8')))).join('\n');
const api = await readFile(
  'apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
  'utf8',
);

// Exact-source mobile gates remain authoritative for format, analysis, tests, and builds.
test('composer keeps files and images while adding services and project context', () => {
  assert.match(screen, /ValueKey<String>\('ask-pandora-menu-\$suffix'\)/);
  for (const [action, suffix, label] of [
    ['camera', 'camera', 'Camera'],
    ['photos', 'photos', 'Photos'],
    ['files', 'files', 'Files'],
    ['services', 'services', 'Services'],
    ['project', 'project-context', 'Project context'],
  ]) {
    assert.match(screen, new RegExp(`item\\(_AttachmentAction\\.${action}, '${suffix}',\\s*'${label}'`));
  }
  for (const action of ['_pickImage(camera: true)', '_pickImage(camera: false)',
    '_attach()', '_pickServiceContext()', '_pickProjectContext()']) {
    assert.ok(screen.includes(`await ${action}`), `${action} remains wired to its menu choice`);
  }
});

test('services come from live capability registry truth instead of hardcoded connected state', () => {
  assert.match(screen, /capabilityRegistry\(\)/);
  assert.match(screen, /registry\.providers/);
  assert.match(screen, /provider\.state/);
  assert.match(screen, /provider\.canUseNow/);
  assert.doesNotMatch(screen, /Gmail is connected|GitHub is connected|Drive is connected/);
});

test('project context comes from existing non-archived Pandora projects and is passed explicitly', () => {
  assert.match(api, /Future<List<PandoraProjectContext>> projectContexts/);
  assert.match(api, /from\('pandora_projects'\)/);
  assert.match(api, /\.neq\('status', 'archived'\)/);
  assert.match(screen, /projectId: _projectContext\?\.id/);
  assert.match(screen, /associateThreadWithProject\(threadId, selected\.id\)/);
  assert.match(screen, /associateThreadWithProject\(threadId, null\)/);
});

test('selected contexts stay visible and removable without dashboard chrome', () => {
  assert.match(screen, /context: _contextChips\(\)/);
  assert.match(screen, /_serviceContext!\.label/);
  assert.match(screen, /_projectContext!\.name/);
  assert.match(screen, /_removeServiceContext/);
  assert.match(screen, /_removeProjectContext/);
  assert.match(screen, /presentContextRoute<_AttachmentAction>\(\s*ModalBottomSheetRoute<_AttachmentAction>/);
  assert.match(screen, /backgroundColor: PandoraSimpleColors\.surface/);
  assert.match(screen, /useSafeArea: true/);
  assert.match(screen, /_presentation\.value\.intentRevision == intent/);
  assert.match(screen, /_presentation\.value\.surface == PandoraChatSurface\.context/);
});
