import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

const history = readFileSync(
  'apps/pandora-mobile/lib/features/simple/project_history_screen.dart',
  'utf8',
);

test('Task 79 keeps historical proposals collapsed while newest proposal stays primary', () => {
  assert.match(history, /String\? latestProposalId/);
  assert.match(history, /item\.isProposal && item\.id != latestProposalId/);
  assert.match(history, /Show proposal/);
});

test('Task 80 collapses completed build history to durable summary first', () => {
  assert.match(history, /\|\|\s*item\.isBuild/);
  assert.match(history, /history-compact-summary-/);
  assert.match(history, /item\.summary/);
  assert.match(history, /Show build details/);
});

test('Task 81 keeps a persistent return control to current work', () => {
  assert.match(history, /history-return-current-work/);
  assert.match(history, /Back to current work/);
  assert.match(history, /onPressed:\s*\(\) => Navigator\.of\(context\)\.pop\(\)/);
});
