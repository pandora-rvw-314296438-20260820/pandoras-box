
import test from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const broker = fs.readFileSync(path.join(root, "supabase/migrations/20260926085943_pandora_coordinator_vault_merge_broker_v1.sql"), "utf8");
const hardening = fs.readFileSync(path.join(root, "supabase/migrations/20260926090143_pandora_coordinator_vault_merge_broker_superseded_check_fix_v1.sql"), "utf8");
const finalVerifier = fs.readFileSync(path.join(root, "supabase/migrations/20260926084425_operations_whole_sheet_native_verification_null_merge_sha_fix_v1.sql"), "utf8");

test("Vault-backed coordinator merge broker is fail-closed and source tracked", () => {
  assert.match(broker, /Github_supabase/);
  assert.match(broker, /pandora_coordinator_gate_complete_merge_v2/);
  assert.match(broker, /mergeable_state.*clean/s);
  assert.match(broker, /pandora-coordinator-vault-merge-v1/);
  assert.match(broker, /providerReadbackVerified/);
  assert.match(broker, /PANDORA_COORDINATOR_VAULT_CLAIM_EXPIRED/);
  assert.match(broker, /mergeParentsVerified/);
  assert.doesNotMatch(broker, /github_pat_[A-Za-z0-9_]+|ghp_[A-Za-z0-9]+/);
  assert.match(hardening, /current_check_run_id/);
  assert.match(hardening, /v_rule_context/);
  assert.match(finalVerifier, /OPS_WHOLE_SHEET_MERGE_PARENT_MISMATCH/);
});
