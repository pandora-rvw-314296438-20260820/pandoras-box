
'use strict';

const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');
const assert = require('node:assert/strict');

const root = path.resolve(__dirname, '..');
const read = (file) => fs.readFileSync(path.join(root, file), 'utf8');

const migration = read(
  'supabase/migrations/20260916102000_m4_018_calendar_device_activity_v1.sql',
);
const nativeCalendar = read(
  'apps/pandora-mobile/platform/android/app/src/main/kotlin/com/banataosystems/pandora_mobile/PandoraCalendarChannel.kt',
);
const activityClient = read(
  'apps/pandora-mobile/lib/core/data/pandora_activity_stream_api.dart',
);
const intelligence = read(
  'apps/pandora-mobile/lib/core/data/pandora_intelligence_api.dart',
);
const ask = read('apps/pandora-mobile/lib/features/simple/ask_pandora_screen.dart');
const adapters = read(
  'apps/pandora-mobile/lib/features/simple/chat/pandora_chat_action_adapters.dart',
);
const executor = read(
  'apps/pandora-mobile/lib/core/device/pandora_calendar_action_executor.dart',
);

 test('mobile calendar facts enter Activity through the bounded RPC only', () => {
  assert.match(activityClient, /pandora_activity_device_fact_v1/);
  assert.doesNotMatch(activityClient, /pandora_activity_admit_event_v1/);
  assert.match(migration, /v_capability not in \('calendar\.events','reminder\.local'\)/);
  assert.match(migration, /v_job\.requested_by <> v_uid/);
  assert.match(migration, /v_operation !~ '\^\[A-Za-z0-9\._:-\]\{8,128\}\$'/);
});

test('canonical result facts require device verification evidence', () => {
  assert.match(migration, /'device_event','relation','verification'/);
  assert.match(migration, /'verification_receipt','relation','verification'/);
  assert.match(migration, /'physicalDevice',false/);
  assert.match(migration, /terminal_state=case when v_state in \('result','failed','cancelled'\)/);
});

test('permission and ambiguity become truthful Needs You blockers', () => {
  assert.match(migration, /'authorization_required'/);
  assert.match(migration, /'external_blocker_only_user_can_resolve'/);
  assert.match(migration, /'missing_consequential_user_choice'/);
  assert.match(executor, /needs_permission/);
  assert.match(executor, /needs_special_access/);
  assert.match(executor, /needs_choice/);
});

test('Android surfaces device timezone and connected-calendar truth', () => {
  assert.match(nativeCalendar, /"deviceTimeZoneId" to TimeZone\.getDefault\(\)\.id/);
  assert.match(nativeCalendar, /CalendarContract\.Calendars\.ACCOUNT_TYPE/);
  assert.match(nativeCalendar, /CalendarContract\.Calendars\.SYNC_EVENTS/);
  assert.match(nativeCalendar, /"providerKind" to providerKind\(accountType\)/);
  assert.match(nativeCalendar, /"providerKind" to calendarInfo\["providerKind"\]/);
});

test('Ask Pandora executes calendar commands before model chat', () => {
  const route = ask.indexOf('await _executeLocalRoute(dispatch, input, dependencies)');
  const cloud = ask.indexOf('intelligence.executeChatTurn(dispatch)', route);
  assert.ok(route >= 0, 'native action adapter is not called');
  assert.ok(cloud > route, 'native routing must finish before cloud dispatch');
  assert.match(ask.slice(route, cloud), /if \(handled \|\| !_current\(token\)\) return;/);
  assert.match(ask, /part 'chat\/pandora_chat_action_adapters\.dart'/);
  assert.match(adapters, /PandoraCalendarCommand\.tryParse\(dispatch\.message/);
  assert.match(adapters, /await _executeCalendar\(dispatch, calendar\.command!, dependencies\)/);

  const start = adapters.indexOf('Future<String> _executeCalendar(');
  const end = adapters.indexOf('Future<String> _executeCommunication(', start);
  assert.ok(start >= 0 && end > start, 'calendar execution adapter missing');
  const calendar = adapters.slice(start, end);
  assert.match(calendar, /final operationId = dispatch\.token\.attemptId;/);
  assert.match(calendar, /PandoraCalendarActionExecutor\(/);
  assert.match(calendar, /startDeviceActivity\([\s\S]*?requestId: operationId/);
  assert.match(calendar, /recordDeviceActivity\([\s\S]*?operationId: operationId/);
  assert.match(calendar, /beforeEffect: \(\) => _beginEffect\(dispatch, 'device'\)/);
  assert.match(calendar, /final result = await executor\.execute\(command, operationId: operationId\);/);
  assert.doesNotMatch(calendar, /if \(!_beginEffect\(dispatch, 'device'\)\)/);
  for (const method of ['createEvent', 'updateEvent', 'deleteEvent', 'scheduleLocalReminder']) {
    const nativeCall = executor.indexOf(`await _runtime.${method}(`);
    assert.ok(nativeCall >= 0, `${method} native dispatch missing`);
    assert.match(executor.slice(Math.max(0, nativeCall - 150), nativeCall), /if \(_beforeEffect\?\.call\(\) == false\) return _cancelled\('[^']+'\);\s*final (?:result|scheduled) = $/);
  }
  assert.match(calendar, /return result\.reply;/);
  assert.match(executor, /if \(_text\(result\['state'\]\) != successState\)/);
  assert.match(executor, /final event = _map\(result\['event'\]\);\s*if \(event\.isEmpty\)/);
  assert.match(intelligence, /class PandoraDeviceActivityExecution/);
});

test('local reminders are verified from Android persisted state', () => {
  assert.match(executor, /scheduleLocalReminder/);
  assert.match(executor, /getLocalReminderStatus/);
  assert.match(executor, /continue locally without cloud access/);
  assert.match(nativeCalendar, /PandoraReminderStateStore/);
  assert.match(nativeCalendar, /setExactAndAllowWhileIdle/);
  assert.match(nativeCalendar, /setAndAllowWhileIdle/);
});
