import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import test from 'node:test';

const shellPath = new URL(
  '../apps/pandora-mobile/lib/app/pandora_chat_shell.dart',
  import.meta.url,
);
const gatePath = new URL(
  '../apps/pandora-mobile/lib/features/auth/auth_gate.dart',
  import.meta.url,
);
const intelligencePath = new URL(
  '../supabase/functions/pandora-intelligence-chat/index.ts',
  import.meta.url,
);

test('mobile runtime enters Pandora chat and uses side navigation', async () => {
  const shell = await readFile(shellPath, 'utf8');
  const gate = await readFile(gatePath, 'utf8');

  assert.match(shell, /AskPandoraScreen\(/);
  assert.match(shell, /Drawer\(/);
  assert.match(shell, /class _PandoraSidePanel/);
  assert.doesNotMatch(shell, /class _PandoraMobileRail/);
  assert.match(shell, /PandoraNavigationScope/);
  assert.doesNotMatch(shell, /bottomNavigationBar\s*:/);
  assert.match(
    gate,
    /dependencies\.intelligence == null[\s\S]*PandoraShell\(\)[\s\S]*PandoraChatShell\(\)/,
  );
});

test('Pandora chat keeps model access behind governed server routing', async () => {
  const intelligence = await readFile(intelligencePath, 'utf8');

  assert.match(intelligence, /provider===\"kimi\"/);
  assert.match(intelligence, /provider===\"openai\"/);
  assert.match(intelligence, /provider:\"gemini\"/);
  assert.match(intelligence, /pandora_kimi_chat_request_v1/);
  assert.match(intelligence, /pandora_openai_chat_request_v1/);
  assert.match(intelligence, /pandora_worker_b_gemini_request_20260829/);
  assert.match(intelligence, /credentialsAvailableToModel:false/);
});
