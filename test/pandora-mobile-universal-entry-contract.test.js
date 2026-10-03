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
  const emptyStart = chat.indexOf('class _EmptyConversation extends StatelessWidget');
  const conversationStart = chat.indexOf('class _Conversation extends StatefulWidget', emptyStart);
  assert.ok(emptyStart >= 0 && conversationStart > emptyStart);
  const genericLanding = chat.slice(emptyStart, conversationStart);

  assert.match(genericLanding, /pandora-logo-only-landing/);
  assert.match(chat, /Message Pandora…/);
  assert.doesNotMatch(
    genericLanding,
    /What can I help with|What can you do for me now\?|Check my GitHub for failing CI|What needs my attention\?|_suggestions|_ObsidianSuggestion/,
  );
  assert.match(chat, /plp-e7-chat-surface/);
});
