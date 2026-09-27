'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const dir = 'supabase/migrations';
const finalizer = '20260925090001_pandora_authorization_replay_finalizer.sql';
const guardedMetaFollowup = '20260926121500_pandora_meta_business_login_config_id_v1.sql';
test('authorization finalizer follows every authoritative protected function definition', () => {
  assert.ok(fs.existsSync(path.join(dir, finalizer)));
  const protectedDefinition = /create\s+(?:or\s+replace\s+)?function\s+public\.(?:pandora_chat_capability_dispatch_native_v1|pandora_chat_universal_dispatch_v9|pandora_meta_oauth_prepare_v1|pandora_tax_guard_rule_support_mutation_v1)\s*\(/i;
  for (const name of fs.readdirSync(dir).filter((name) => name.endsWith('.sql'))) {
    if (name === finalizer) continue;
    const source = fs.readFileSync(path.join(dir, name), 'utf8');
    if (!protectedDefinition.test(source)) continue;
    if (name < finalizer) continue;
    assert.equal(name, guardedMetaFollowup, `Protected definition ${name} would override final authorization guards`);
    assert.match(source, /if not private\.pandora_is_active_org_admin_v1\(p_organization_id\) then/i,
      'Later Meta OAuth definition must retain the active organization-admin guard');
  }
});

test('Meta Business Login requires a valid configuration ID before issuing OAuth state', () => {
  const source = fs.readFileSync(path.join(dir, guardedMetaFollowup), 'utf8');
  assert.match(source, /name='pandora_meta_oauth_config_id'/);
  const configCheck = source.indexOf("coalesce(trim(v_config_id),'') !~ '^[1-9][0-9]{0,63}$'");
  const stateInsert = source.indexOf('insert into private.pandora_meta_oauth_states');
  assert.ok(configCheck >= 0 && stateInsert > configCheck);
  assert.match(source, /'&config_id='\|\|extensions\.urlencode\(v_config_id\)/);
  assert.match(source, /'&override_default_response_type=true'/);
  assert.doesNotMatch(source, /'&scope='/);
  assert.match(source, /insert into private\.pandora_meta_oauth_states\(organization_id,user_id,state_hash,redirect_uri,required_scopes,expires_at\)/);
  assert.match(source, /values\(p_organization_id,v_uid,v_state_hash,v_redirect,v_scopes,v_expires\)/);
  assert.match(source, /https:\/\/mcpmaster\.vercel\.app\/oauth\/meta\/callback/);
});
