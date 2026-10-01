import fs from "node:fs";
import test from "node:test";
import assert from "node:assert/strict";

const migration = fs.readFileSync(
  new URL("../supabase/migrations/20261001050000_plp_resort_lifecycle_v1.sql", import.meta.url),
  "utf8",
);
const api = fs.readFileSync(
  new URL("../apps/pandora-mobile/lib/core/data/plp_resort_lifecycle_api.dart", import.meta.url),
  "utf8",
);

test("PLP lifecycle mutations are role-gated, idempotent and provider-verified", () => {
  assert.match(migration, /plp_operation_receipts/);
  assert.match(migration, /pg_advisory_xact_lock/);
  assert.match(migration, /private\.plp_actor_context_v1/);
  assert.match(migration, /array\['owner','admin','operator'\]/);
  assert.match(migration, /providerReadbackVerified/);
  assert.match(migration, /idempotentReplay/);
});

test("PLP lifecycle exposes normal reservation, guest, payment and room operations", () => {
  for (const name of [
    "plp_reservation_create_v1",
    "plp_reservation_update_v1",
    "plp_reservation_transition_v1",
    "plp_guest_update_v1",
    "plp_payment_record_v1",
    "plp_room_update_v1",
    "plp_reservation_detail_v1",
  ]) {
    assert.match(migration, new RegExp(name));
    assert.match(api, new RegExp(name));
  }
  assert.match(migration, /room is not available for the requested dates/);
  assert.match(migration, /guest count exceeds room capacity/);
  assert.match(migration, /payment amount exceeds outstanding balance/);
});

test("PLP lifecycle never grants mutation RPCs to anon", () => {
  assert.doesNotMatch(migration, /grant execute[\s\S]*to anon/i);
  assert.match(migration, /revoke all on function public\.plp_reservation_create_v1/);
  assert.match(migration, /revoke all on function public\.plp_payment_record_v1/);
});
