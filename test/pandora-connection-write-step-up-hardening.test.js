import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const sql = fs.readFileSync(path.join(root, "supabase/migrations/20261001144500_pandora_connection_write_step_up_hardening_v1.sql"), "utf8");

test("write preview and consume require an exact current live provider tuple", () => {
  assert.match(sql, /pandora_connection_is_current_live_v1/);
  assert.match(sql, /a\.rotation_due_at>clock_timestamp\(\)/);
  assert.match(sql, /a\.last_verified_at between/);
  assert.match(sql, /a\.granted_scopes<@private\.pandora_connection_required_scopes_v1/);
  assert.match(sql, /a\.granted_capabilities<@private\.pandora_connection_required_capabilities_v1/);
  assert.match(sql, /provider_readback_hash is not null/);
  assert.match(sql, /exists\(select 1 from vault\.secrets/);
  assert.equal((sql.match(/not private\.pandora_connection_is_current_live_v1/g) || []).length, 2);
});

test("approval requires AAL2 and consumption re-hashes the stored exact target", () => {
  assert.match(sql, /auth\.jwt\(\)->>'aal',''\)<>'aal2'/);
  assert.match(sql, /pandora_connection_write_step_up_required/);
  assert.match(sql, /target_preview::text/);
  assert.match(sql, /connection\.write_previewed/);
  assert.match(sql, /connection\.write_approved/);
  assert.match(sql, /connection\.write_approval_consumed/);
});
