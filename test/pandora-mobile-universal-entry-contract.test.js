import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const chatPath = new URL(
  '../apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart',
  import.meta.url,
);

test('Universal Pandora entry never creates a Project just because intelligence is unavailable', async () => {
  const chat = await readFile(chatPath, 'utf8');

  assert.match(chat, /A Project is optional persistent context, never a prerequisite/);
  assert.match(chat, /_keys\.create\('simple-intake'\)/);
  assert.doesNotMatch(
    chat,
    /if \(intelligence == null\) \{\s*if \(dependencies\.projectExperienceRepository != null\)/,
  );
});

test('empty Pandora chat is logo-only while the universal composer remains live', async () => {
  const chat = await readFile(chatPath, 'utf8');

  assert.match(chat, /pandora-logo-only-landing/);
  assert.match(chat, /Message Pandora…/);
  const emptyStart = chat.indexOf('class _EmptyConversation');
  const emptyEnd = chat.indexOf('class _Conversation', emptyStart);
  assert.ok(emptyStart >= 0 && emptyEnd > emptyStart);
  const universalEmpty = chat.slice(emptyStart, emptyEnd);
  assert.doesNotMatch(
    universalEmpty,
    /What can I help with|What can you do for me now\?|Check my GitHub for failing CI|What needs my attention\?|_suggestions|_ObsidianSuggestion/,
  );
});
