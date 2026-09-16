
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
const executor = read(
  'apps/pandora-mobile/lib/core/device/pandora_calendar_action_executor.dart',
);

 test('mobile calendar facts enter Activity through the bounded RPC only', () => {
  assert.match(activityClient, /pandora_activity_device_fact_v1/);
  assert.doesNotMatch(activityClient, /pandora_activity_admit_event_v1/);
  assert.match(migration, /p_capability not in \('calendar\.events','reminder\.local'\)/);
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
  const parse = ask.indexOf('PandoraCalendarCommand.tryParse(');
  const model = ask.indexOf('intelligence.startChatExecution(');
  assert.ok(parse >= 0, 'calendar parser missing');
  assert.ok(model >= 0, 'model chat dispatch missing');
  assert.ok(parse < model, 'calendar execution must happen before model chat');
  assert.match(ask, /PandoraCalendarActionExecutor/);
  assert.match(ask, /startDeviceActivity/);
  assert.match(ask, /recordDeviceActivity/);
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
