const fs = require('node:fs');
const test = require('node:test');
const assert = require('node:assert/strict');

const migration = fs.readFileSync(
  'supabase/migrations/20260921112000_plp_realtime_resort_updates_v1.sql',
  'utf8',
);
const shell = fs.readFileSync(
  'apps/pandora-mobile/lib/app/plp_enterprise_shell.dart',
  'utf8',
);
const activity = fs.readFileSync(
  'apps/pandora-mobile/lib/features/enterprise/plp_activity_screen.dart',
  'utf8',
);

test('PLP realtime transport publishes only safe invalidation signals', () => {
  assert.match(migration, /enterprise_realtime_signals/);
  assert.match(migration, /enterprise_realtime_signals_member_read/);
  assert.match(migration, /alter publication supabase_realtime/);
  for (const topic of [
    'bookings',
    'guests',
    'staff_tasks',
    'hospitality',
    'business_activity',
    'source_health',
    'pandora_activity',
  ]) {
    assert.match(migration, new RegExp("'" + topic + "'"));
  }
  assert.doesNotMatch(
    migration,
    /full_name|email|phone|special_requests|provider_secret|prompt|model_name/i,
  );
});

test('PLP shell refetches protected bootstrap after live resort changes', () => {
  assert.match(shell, /channel\('plp-enterprise-live-\$organizationId'\)/);
  assert.match(shell, /table: 'enterprise_realtime_signals'/);
  assert.match(shell, /_scheduleRealtimeRefresh\(\)/);
  assert.match(shell, /organizationId: _organizationId\(bootstrap\)/);
});

test('PLP Activity refetches business and Pandora logs from live signals', () => {
  assert.match(activity, /channel\('plp-activity-live-\$organizationId'\)/);
  assert.match(activity, /table: 'enterprise_realtime_signals'/);
  assert.match(activity, /unawaited\(_loadBusiness\(\)\)/);
  assert.match(activity, /if \(_logsLoaded\) unawaited\(_loadLogs\(\)\)/);
});
