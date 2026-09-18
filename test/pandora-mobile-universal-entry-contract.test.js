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

test('empty Pandora chat prompts PLP enterprise commands for branded home', async () => {
  const chat = await readFile(chatPath, 'utf8');

  assert.match(chat, /Give me today's PLP Boracay management briefing/);
  assert.match(chat, /Show me today's and upcoming PLP Boracay bookings/);
  assert.match(chat, /Analyze PLP Boracay business performance/);
  assert.match(chat, /I want Pandora to handle a change for PLP Boracay/);
  assert.match(chat, /PLP Boracay/);
});
