const fs = require('node:fs');
const test = require('node:test');
const assert = require('node:assert/strict');

const verifier = fs.readFileSync('.pandora-verifier/verify.sh', 'utf8');
const workflow = fs.readFileSync('.github/workflows/plp-pandora-enterprise-android.yml', 'utf8');
const physical = fs.readFileSync('apps/pandora-mobile/tool/verify_physical_android_candidate.py', 'utf8');
const localAi = fs.readFileSync('apps/pandora-mobile/lib/features/settings/local_ai_settings_screen.dart', 'utf8');
const config = fs.readFileSync('apps/pandora-mobile/lib/pandora_config.dart', 'utf8');
const shell = fs.readFileSync('apps/pandora-mobile/lib/app/plp_enterprise_shell.dart', 'utf8');
const migration = fs.readFileSync('supabase/migrations/20261001091518_plp_direct_source_v1.sql', 'utf8');

test('PLP verifier supports production signing without embedding a key', () => {
  assert.match(verifier, /PANDORA_PLP_RELEASE_KEYSTORE_B64/);
  assert.match(verifier, /production-candidate/);
  assert.match(verifier, /ba4c1df95b0f0858bb510dab90b412dd18724205f5ff3dfbb7c7c56c9931202e/);
  assert.match(config, /PANDORA_ARTIFACT_CLASS/);
  assert.doesNotMatch(verifier, /-----BEGIN .*PRIVATE KEY-----/);
  assert.match(verifier, /ZIPALIGN.*-P 16 -f 4/);
});

test('PLP exact-source and physical acceptance agree on Qwen3 4B', () => {
  const hash = '1571ec5115bcfed4b4327fc27b5f44ea284806caf5331eef89326191c9b031d6';
  assert.match(verifier, new RegExp(hash));
  assert.match(workflow, new RegExp(hash));
  assert.match(workflow, /Qwen3-4B-Instruct-2507-Q4_K_M\.gguf/);
  assert.match(localAi, /visible: true/);
  assert.match(localAi, /'p_organization_id': widget\.organizationId/);
  assert.match(shell, /organizationId: PandoraConfig\.plpOrganizationId/);
});

test('physical verifier can bind the dedicated PLP package and release signer', () => {
  assert.match(physical, /--expected-package/);
  assert.match(physical, /production-candidate/);
  assert.match(physical, /production_signer_verified/);
});

test('Pandora Direct is tenant scoped and never impersonates an external PMS', () => {
  assert.match(migration, /private\.plp_direct_source_bindings/);
  assert.match(migration, /enterprise_hospitality_rooms/);
  assert.match(migration, /externalPmsOtaConnected',false/);
  assert.match(migration, /source_status='healthy'/);
  assert.doesNotMatch(migration, /externalPmsOtaConnected',true/);
});
