import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const chatPath = new URL(
  '../apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  import.meta.url,
);

test('Universal Pandora entry never creates a Project just because intelligence is unavailable', async () => {
  const chat = await readFile(chatPath, 'utf8');

  assert.match(chat, /dependencies\.repository\.ask\(/);
  assert.match(chat, /idempotencyKey: token\.attemptId/);
  assert.doesNotMatch(chat, /CreateProjectExperienceScreen\(/);
  assert.doesNotMatch(
    chat,
    /if \(intelligence == null\) \{\s*if \(dependencies\.projectExperienceRepository != null\)/,
  );
});

test('empty Pandora chat is logo-only while the universal composer remains live', async () => {
  const chat = await readFile(chatPath, 'utf8');

  assert.match(chat, /pandora-logo-only-landing/);
  const composer = await readFile('apps/pandora-mobile/lib/features/simple/chat/pandora_chat_composer.dart', 'utf8');
  assert.match(chat, /PandoraChatComposer\(/);
  assert.match(composer, /Message Pandora…/);
  assert.doesNotMatch(
    chat,
    /What can I help with|What can you do for me now\?|Check my GitHub for failing CI|What needs my attention\?|_suggestions|_ObsidianSuggestion/,
  );
});
