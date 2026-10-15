
import assert from 'node:assert/strict';
import test from 'node:test';
import { readFileSync } from 'node:fs';

const migration = readFileSync(
  'supabase/migrations/20261001093000_plp_resort_transactions_v1.sql',
  'utf8',
);

test('PLP resort actions are a bounded named capability surface', () => {
  for (const action of [
    'reservation.create',
    'reservation.update',
    'reservation.check_in',
    'reservation.check_out',
    'reservation.cancel',
    'guest.update',
    'room.update',
    'payment.record',
    'task.update',
  ]) {
    assert.match(migration, new RegExp("'" + action.replace('.', '\\\\.') + "'"));
  }
  assert.match(migration, /unsupported PLP resort action/);
  assert.doesNotMatch(migration, /execute\s+format\s*\(/i);
});

test('PLP resort writes require active membership and explicit roles', () => {
  assert.match(migration, /active PLP membership required/);
  assert.match(migration, /array\['owner','admin','operator'\]/);
  assert.match(migration, /array\['owner','admin'\]/);
  assert.match(migration, /array\['owner','admin','operator','member'\]/);
  assert.match(migration, /PLP role is not authorized for this action/);
});

test('PLP resort writes are idempotent and provider-readback verified', () => {
  assert.match(migration, /private\.plp_resort_action_receipts/);
  assert.match(migration, /request_sha256/);
  assert.match(migration, /request id collision/);
  assert.match(migration, /providerReadbackVerified/);
  assert.match(migration, /idempotentReplay/);
});

test('reservation lifecycle rejects conflicts and unsafe transitions', () => {
  assert.match(migration, /room is not available for the requested dates/);
  assert.match(migration, /guest count exceeds room capacity/);
  assert.match(migration, /room must be ready before check-in/);
  assert.match(migration, /outstanding balance must be resolved before check-out/);
  assert.match(migration, /reservation cannot be cancelled in its current state/);
});

test('room availability honors operational state and checkout creates cleaning work', () => {
  assert.match(migration, /operational_state/);
  assert.match(migration, /'cleaning','maintenance','out_of_service'/);
  assert.match(migration, /"cleaning"'::jsonb/);
  assert.match(migration, /'unavailable',rooms_unavailable/);
  assert.match(
    migration,
    /greatest\(rooms_total-rooms_occupied-rooms_unavailable,0\)/,
  );
});

test('guest contact remains selected-record only', () => {
  assert.match(migration, /plp_resort_guest_detail_v1/);
  assert.match(migration, /contactDetailsAuthorized/);
  assert.match(migration, /'contactDetailsExcluded',true/);
  assert.doesNotMatch(
    migration,
    /'rooms',rooms[\s\S]*'email'/,
    'command center must not embed guest email into broad room projection',
  );
});

test('client execute grants are narrow and private receipt table is not client-readable', () => {
  assert.match(
    migration,
    /revoke all on table private\.plp_resort_action_receipts[\s\S]*from public, anon, authenticated/,
  );
  assert.match(
    migration,
    /grant execute on function public\.plp_resort_action_v1\(text,text,uuid,jsonb\)[\s\S]*to authenticated,service_role/,
  );
});
