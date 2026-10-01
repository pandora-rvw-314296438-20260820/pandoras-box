import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const read = (path) => fs.readFileSync(path, 'utf8');

const migration = read(
  'supabase/migrations/20261001134500_plp_resort_transaction_v1.sql',
);
const action = read(
  'apps/pandora-mobile/lib/features/enterprise/plp_resort_transaction_action.dart',
);
const screens = read(
  'apps/pandora-mobile/lib/features/enterprise/plp_resort_transaction_screens.dart',
);
const shell = read('apps/pandora-mobile/lib/app/plp_enterprise_shell.dart');
const workspace = read(
  'apps/pandora-mobile/lib/features/enterprise/plp_resort_workspace.dart',
);
const records = read(
  'apps/pandora-mobile/lib/features/enterprise/plp_resort_operational_screens.dart',
);

test('PLP resort writes are active-member and operator scoped', () => {
  assert.match(migration, /uid uuid := auth\.uid\(\)/);
  assert.match(migration, /m\.status::text='active'/);
  assert.match(
    migration,
    /actor_role not in \('owner','admin','operator'\)/,
  );
  assert.match(
    migration,
    /only owner or admin may (override room rate|change room rates)/,
  );
  assert.match(
    migration,
    /only owner or admin may mark a room out of order/,
  );
});

test('PLP resort mutations are idempotent and auditable', () => {
  assert.match(migration, /plp_resort_write_receipts/);
  assert.match(migration, /payload_sha256/);
  assert.match(migration, /extensions\.digest\(payload::text,'sha256'\)/);
  assert.match(migration, /idempotentReplay/);
  assert.match(migration, /plp_resort_audit/);
  assert.match(migration, /providerReadbackVerified',true/);
  assert.match(migration, /plp_resort_audit_v1/);
});

test('PLP reservation lifecycle rejects unsafe booking states', () => {
  assert.match(migration, /create_booking/);
  assert.match(migration, /update_booking/);
  assert.match(migration, /check_in/);
  assert.match(migration, /check_out/);
  assert.match(migration, /cancel_booking/);
  assert.match(migration, /daterange\(b\.check_in,b\.check_out,'\[\)'\)/);
  assert.match(migration, /guest count exceeds room capacity/);
  assert.match(migration, /booking must be checked in before check-out/);
  assert.match(migration, /checked-in stay must be checked out or owner-forced/);
  assert.match(migration, /checked-out booking cannot be cancelled/);
});

test('PLP finance, task, room and channel mutations are bounded', () => {
  assert.match(migration, /record_manual_payment/);
  assert.match(migration, /payment amount exceeds outstanding balance/);
  assert.match(migration, /verification_status.*'VERIFIED'/s);
  assert.match(migration, /set_room_state/);
  assert.match(migration, /set_room_rate/);
  assert.match(migration, /update_task/);
  assert.match(migration, /resolve_conflict/);
  assert.match(migration, /operational_state in \('ready','cleaning','maintenance','out_of_order'\)/);
});

test('PLP write tables stay behind the security-definer RPC', () => {
  for (const table of [
    'plp_room_operations',
    'plp_resort_write_receipts',
    'plp_resort_audit',
  ]) {
    assert.match(
      migration,
      new RegExp(
        'revoke all on table plp_runtime\\.' + table +
          '[\\s\\S]*from public,anon,authenticated',
      ),
    );
  }
  assert.match(
    migration,
    /revoke execute on function public\.plp_resort_transaction_v1\(text,text,jsonb\)[\s\S]*from public,anon/,
  );
  assert.match(
    migration,
    /grant execute on function public\.plp_resort_transaction_v1\(text,text,jsonb\)[\s\S]*to authenticated/,
  );
});

test('mobile resort actions use provider-verified transaction readback', () => {
  assert.match(action, /plp_resort_transaction_v1/);
  assert.match(action, /providerReadbackVerified/);
  assert.match(action, /result\.requestId != normalizedRequestId/);
  assert.match(action, /result\.action != normalizedAction/);
});

test('normal resort UI exposes reservation and record actions outside chat', () => {
  assert.match(workspace, /label: 'New reservation'/);
  assert.match(shell, /PlpReservationCreateScreen/);
  assert.match(shell, /PlpResortMutationScreen/);
  assert.match(records, /plp-record-action-/);
  for (const id of [
    'edit_booking',
    'check_in',
    'check_out',
    'cancel_booking',
    'update_guest',
    'manual_payment',
    'room_state',
    'room_rate',
    'task_done',
    'resolve_conflict',
  ]) {
    assert.match(screens, new RegExp("'" + id + "'"));
  }
});
