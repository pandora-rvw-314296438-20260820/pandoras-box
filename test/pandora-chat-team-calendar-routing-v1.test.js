import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const ask = readFileSync('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart', 'utf8');
const api = readFileSync('apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart', 'utf8');
const calendar = readFileSync('apps/pandora-mobile/lib/core/device/pandora_calendar_command.dart', 'utf8');
const localAi = readFileSync('apps/pandora-mobile/lib/core/local_ai/pandora_local_ai.dart', 'utf8');
const edge = readFileSync('supabase/functions/pandora-intelligence-chat/index.ts', 'utf8');

test('team administration is classified before calendar and local AI pre-routers', () => {
  assert.match(ask, /final teamAdministrationTurn\s*=\s*_teamAdministrationPending\s*\|\|/s);
  assert.match(ask, /final calendarParse = teamAdministrationTurn\s*\?\s*null\s*:\s*PandoraCalendarCommand\.tryParse/s);
  assert.match(ask, /final deviceCommunication = teamAdministrationTurn\s*\?\s*null/s);
  assert.match(ask, /if \(!teamAdministrationTurn && await _trySubmitLocalAi\(objective\)\)/);
});

test('multi-turn team clarification remains on the governed cloud lane', () => {
  assert.match(edge, /conversationLane:"team_admin"/);
  assert.match(api, /final String\? conversationLane;/);
  assert.match(api, /conversationLane: _optionalText\(json\['conversationLane'\]\)/);
  assert.match(ask, /turn\.needsClarification\s*&&[\s\S]*turn\.conversationLane == 'team_admin'/);
  assert.match(ask, /_isTeamAdministrationClarification\(history\.last\.content\)/);
});

test('calendar parser explicitly rejects unqualified team administration creates', () => {
  assert.match(calendar, /final teamAdministration = RegExp\(/);
  assert.match(calendar, /if \(teamAdministration && !explicitCalendarContext\) return false;/);
});

test('phone-local AI refuses team mutations as external actions', () => {
  assert.match(localAi, /create\|add\|invite\|delete\|remove\|update\|change/);
  assert.match(localAi, /suspend\|disable\|deactivate\|revoke\|reactivate\|activate\|restore\|promote\|demote/);
});
