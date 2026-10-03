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

test('authorized owner launches Home inside the shared Pandora chat shell', async () => {
  const shell = await readFile(shellPath, 'utf8');
  const gate = await readFile(gatePath, 'utf8');

  assert.match(shell, /AskPandoraScreen\(/);
  assert.match(shell, /Drawer\(/);
  assert.match(shell, /class _PandoraSidePanel/);
  assert.doesNotMatch(shell, /class _PandoraMobileRail/);
  assert.match(shell, /PandoraNavigationScope/);
  assert.doesNotMatch(shell, /bottomNavigationBar\s*:/);
  assert.match(shell, /this\.startPage = PandoraStartPage\.chat/);
  assert.match(
    gate,
    /snapshot\.data != true[\s\S]*PandoraMemberWorkspaceGate\([\s\S]*dependencies\.intelligence == null[\s\S]*PandoraShell\(\)[\s\S]*PandoraChatShell\(\s*startPage: PandoraStartPage\.home/,
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


test('restores actual accepted old Pandora chat composition from 73cd688a', () => {
  assert.ok(!shell.includes('businessWorkspace: Offstage('));
  assert.ok(!shell.includes('active: index == _index && !_chatVisible'));
  assert.match(shell, /businessWorkspace: PandoraSharedConversationScope\(/);
  assert.match(ask, /final historyTop = topInset \+ 60/);
  assert.match(ask, /left: 8,[\s\S]*right: 8,[\s\S]*borderRadius: BorderRadius\.circular\(24\)/);
});

test('restores old Pandora composer source with model selection only inside its old menu', () => {
  assert.match(ask, /EdgeInsets\.fromLTRB\(12, 2, 8, 6\)/);
  assert.match(ask, /Icons\.add_rounded/);
  assert.match(ask, /Icons\.view_in_ar_outlined/);
  assert.match(ask, /ask-pandora-menu-model/);
  assert.match(ask, /ask-pandora-menu-reasoning/);
  assert.ok(!ask.includes("height: 54,\n                  decoration: BoxDecoration(\n                    color: const Color(0xFF151515)"));
});
