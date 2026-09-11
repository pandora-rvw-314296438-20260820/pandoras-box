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

test('empty Pandora chat prompts universal commands instead of project-only examples', async () => {
  const chat = await readFile(chatPath, 'utf8');

  assert.match(chat, /What can you do for me now\?/);
  assert.match(chat, /Check my GitHub for failing CI/);
  assert.match(chat, /What needs my attention\?/);
});
