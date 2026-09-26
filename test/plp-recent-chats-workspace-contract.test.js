import fs from 'node:fs';
import test from 'node:test';
import assert from 'node:assert/strict';

const api = fs.readFileSync(
  'apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
  'utf8',
);
const shell = fs.readFileSync(
  'apps/pandora-mobile/lib/app/plp_enterprise_shell.dart',
  'utf8',
);

test('PLP recent chats match the workspace identity actually persisted by Enterprise chat', () => {
  assert.match(api, /selected\['workspaceSlug'\]/);
  assert.match(api, /selected\['workspaceKey'\]/);
  assert.match(api, /messageWorkspace != normalized/);
  assert.doesNotMatch(
    api,
    /contains\('structured_response',[\s\S]*?'workspaceKey': normalized/,
  );
});

test('PLP reloads recent conversations whenever the drawer opens', () => {
  assert.match(
    shell,
    /onDrawerChanged:\s*\(open\)[\s\S]*?_loadRecentChats\(force: true\)/,
  );
});
