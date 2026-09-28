import assert from "node:assert/strict";
import fs from "node:fs";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const disconnect = fs.readFileSync(
  path.join(root, "supabase/migrations/20260929044500_pandora_meta_disconnect_local_v1.sql"),
  "utf8",
);
const metaRuntime = fs.readFileSync(
  path.join(root, "supabase/migrations/20260925061000_pandora_meta_oauth_marketing_read_v1.sql"),
  "utf8",
);
const ownerApi = fs.readFileSync(
  path.join(root, "supabase/functions/pandora-owner-api/index.ts"),
  "utf8",
);

test("FB-014 disconnect is service-only, owner-bound and generation fenced", () => {
  assert.match(disconnect, /current_user not in \('service_role','postgres','supabase_admin'\)/);
  assert.match(disconnect, /m\.role in \('owner','admin'\)/);
  assert.match(disconnect, /i\.organization_id=p_organization_id[\s\S]*i\.provider='meta'/);
  assert.match(disconnect, /rotation_state='current'::public\.rotation_status/);
  assert.match(disconnect, /key_version is distinct from p_expected_key_version/);
  assert.match(disconnect, /MULTI_INSTALLATION_REQUIRES_EXPLICIT_SCOPE/);
  assert.match(disconnect, /revoke all on function public\.pandora_meta_disconnect_local_v1[\s\S]*public,anon,authenticated/);
  assert.match(disconnect, /grant execute on function public\.pandora_meta_disconnect_local_v1[\s\S]*service_role/);
});

test("FB-014 local disconnect atomically removes every Meta runtime authority used by Pandora", () => {
  assert.match(disconnect, /rotation_state='revoked'::public\.rotation_status/);
  assert.match(disconnect, /status='revoked'::public\.connector_status/);
  assert.match(disconnect, /set status='revoked'[\s\S]*last_error='locally_disconnected'/);
  assert.match(metaRuntime, /status='active'[\s\S]*rotation_state='current'/);
  assert.match(metaRuntime, /c\.status='connected'/);
  assert.doesNotMatch(disconnect, /vault\.(delete|update|create)_secret/i);
  assert.match(disconnect, /'providerRevocationAttempted',false/);
  assert.match(disconnect, /'vaultMaterialDeleted',false/);
});

test("FB-014 reconnect is a fresh OAuth commit and owner UI remains AAL2/governed", () => {
  assert.match(metaRuntime, /on conflict\(organization_id,provider,external_account_id\) do update[\s\S]*status='active'/);
  assert.match(metaRuntime, /key_version=public\.credential_refs\.key_version\+1[\s\S]*rotation_state='current'/);
  assert.match(metaRuntime, /on conflict\(organization_id\) do update[\s\S]*status='connected'/);
  assert.match(ownerApi, /action !== "test" && context\.aal !== "aal2"/);
  assert.match(ownerApi, /Disconnect \$\{provider\}[\s\S]*protected approval is valid/);
  assert.match(ownerApi, /acceptIntake\([\s\S]*connection:\$\{connectionId\}:\$\{action\}/);
});
