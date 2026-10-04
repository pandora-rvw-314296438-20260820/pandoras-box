import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const ask = readFileSync('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart', 'utf8');
const adapters = readFileSync('apps/pandora-mobile/lib/features/simple/chat/pandora_chat_action_adapters.dart', 'utf8');
const store = readFileSync('apps/pandora-mobile/lib/core/chat/pandora_conversation_store.dart', 'utf8');
const api = readFileSync('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', 'utf8');
const calendar = readFileSync('apps/pandora-mobile/lib/core/device/pandora_calendar_command.dart', 'utf8');
const localAi = readFileSync('apps/pandora-mobile/lib/core/local_ai/pandora_local_ai.dart', 'utf8');
const edge = readFileSync('supabase/functions/pandora-intelligence-chat/index.ts', 'utf8');

test('Core scope and team administration reach authorization before calendar and local AI pre-routers', () => {
  assert.match(adapters, /final teamTurn = input\.coreScope \|\|\s*teamPending \|\|/s);
  assert.match(adapters, /final calendar = teamTurn\s*\?\s*null\s*:\s*PandoraCalendarCommand\.tryParse/s);
  assert.match(adapters, /final communication = teamTurn\s*\?\s*null/s);
  assert.match(adapters, /if \(!teamTurn &&[\s\S]*_executePhoneAi\(dispatch, input, forceLocal: forceLocal\)\)/);
});

test('multi-turn team clarification remains on the governed cloud lane', () => {
  assert.match(edge, /conversationLane:"team_admin"/);
  assert.match(api, /final String\? conversationLane;/);
  assert.match(api, /conversationLane: _optionalText\(json\['conversationLane'\]\)/);
  assert.match(ask, /'conversationLane': turn\.conversationLane/);
  assert.match(ask, /'needsClarification': turn\.needsClarification/);
  assert.match(adapters, /lane!\['conversationLane'\] == 'team_admin' &&\s*lane\['needsClarification'\] == true/);
  assert.match(adapters, /lane\?\.containsKey\('conversationLane'\) == true[\s\S]*_isTeamAdministrationClarification\(last\.reply\)/, 'structured receipts govern current turns; prose fallback only covers legacy history');
  assert.match(store, /'conversationLane'/);
  assert.match(store, /'needsClarification'/);
});

test('calendar parser explicitly rejects unqualified team administration creates', () => {
  assert.match(calendar, /final teamAdministration = RegExp\(/);
  assert.match(calendar, /if \(teamAdministration && !explicitCalendarContext\) return false;/);
});

test('phone-local AI refuses team mutations as external actions', () => {
  assert.match(localAi, /create\|add\|invite\|delete\|remove\|update\|change/);
  assert.match(localAi, /suspend\|disable\|deactivate\|revoke\|reactivate\|activate\|restore\|promote\|demote/);
});
