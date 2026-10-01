-- Philippine government providers with documented APIs.
-- Catalog presence is discovery only. Credentialless providers become
-- Connected only through the tenant-bound safe-read commit below.

insert into public.pandora_provider_manifests(
  provider_key, manifest_version, display_name, lifecycle_state, auth_scheme,
  regions, data_residency, data_handling, deprecation_policy, runbook_ref, escalation_ref
) values
(
  'ph.psa.openstat', '1.0.0', 'PSA OpenSTAT', 'active', 'public',
  array['PH'], array['provider-managed:PH','pandora-evidence:policy-controlled'],
  '{"classification":"public_government_data","readOnly":true,"credentialsServerSideOnly":true,"rawResponseLogging":false,"bodyDigestOnly":true}'::jsonb,
  '{"strategy":"monitor_official_documentation_and_fail_closed","compatibilityWindowDays":0}'::jsonb,
  'docs/connections/PHILIPPINE_GOVERNMENT_CONNECTIONS.md', 'government-provider-request-activation'
),
(
  'ph.psa.psgc', '1.0.0', 'PSA PSGC', 'active', 'api_token',
  array['PH'], array['provider-managed:PH','pandora-evidence:policy-controlled'],
  '{"classification":"public_government_data","readOnly":true,"credentialsServerSideOnly":true,"rawResponseLogging":false,"bodyDigestOnly":true}'::jsonb,
  '{"strategy":"monitor_official_documentation_and_fail_closed","compatibilityWindowDays":0}'::jsonb,
  'docs/connections/PHILIPPINE_GOVERNMENT_CONNECTIONS.md', 'government-provider-request-activation'
),
(
  'ph.phivolcs.hazard_gis', '1.0.0', 'PHIVOLCS Hazard GIS', 'active', 'public',
  array['PH'], array['provider-managed:PH','pandora-evidence:policy-controlled'],
  '{"classification":"public_government_data","readOnly":true,"credentialsServerSideOnly":true,"rawResponseLogging":false,"bodyDigestOnly":true}'::jsonb,
  '{"strategy":"monitor_official_documentation_and_fail_closed","compatibilityWindowDays":0}'::jsonb,
  'docs/connections/PHILIPPINE_GOVERNMENT_CONNECTIONS.md', 'government-provider-request-activation'
),
(
  'ph.namria.geoportal', '1.0.0', 'NAMRIA Geoportal Philippines', 'active', 'public',
  array['PH'], array['provider-managed:PH','pandora-evidence:policy-controlled'],
  '{"classification":"public_government_data","readOnly":true,"credentialsServerSideOnly":true,"rawResponseLogging":false,"bodyDigestOnly":true}'::jsonb,
  '{"strategy":"monitor_official_documentation_and_fail_closed","compatibilityWindowDays":0}'::jsonb,
  'docs/connections/PHILIPPINE_GOVERNMENT_CONNECTIONS.md', 'government-provider-request-activation'
)
on conflict do nothing;

insert into private.pandora_connection_manifest_contracts_v1(
  provider_key, manifest_version, auth, scopes, callback, health, capabilities, risk_class,
  account_identity, credential_policy, write_authorization, residency_policy, recovery
) values
(
  'ph.psa.openstat', '1.0.0',
  '{"type":"service_credential","credentialMode":"none"}'::jsonb,
  '{"required":["statistics.catalog.read"],"optional":[],"leastPrivilege":"read-first"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"statistics.catalog.read","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"statistics.catalog.read","mode":"read"}]'::jsonb,
  'low', '{"subject":"providerIdentity","label":"providerIdentity","tenant":"organization_id","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"credentialMode":"none","refresh":false,"revoke":false,"rotationDays":null}'::jsonb,
  '{"required":false,"mode":"read_only","forModes":[]}'::jsonb,
  '{"mode":"provider_managed_ph","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidReadback":"reverify"}'::jsonb
),
(
  'ph.psa.psgc', '1.0.0',
  '{"type":"api_key","credential":"psa_issued_query_token"}'::jsonb,
  '{"required":["geography.psgc.read"],"optional":[],"leastPrivilege":"read-first"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"geography.psgc.read","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"geography.psgc.read","mode":"read"}]'::jsonb,
  'medium', '{"subject":"providerIdentity","label":"providerIdentity","tenant":"organization_id","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"credentialMode":"vault_query_token","refresh":false,"revoke":true,"rotationDays":90}'::jsonb,
  '{"required":false,"mode":"read_only","forModes":[]}'::jsonb,
  '{"mode":"provider_managed_ph","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidCredential":"replace_credential"}'::jsonb
),
(
  'ph.phivolcs.hazard_gis', '1.0.0',
  '{"type":"service_credential","credentialMode":"none"}'::jsonb,
  '{"required":["hazard.layer.read"],"optional":[],"leastPrivilege":"read-first"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"hazard.layer.read","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"hazard.layer.read","mode":"read"}]'::jsonb,
  'low', '{"subject":"providerIdentity","label":"providerIdentity","tenant":"organization_id","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"credentialMode":"none","refresh":false,"revoke":false,"rotationDays":null}'::jsonb,
  '{"required":false,"mode":"read_only","forModes":[]}'::jsonb,
  '{"mode":"provider_managed_ph","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidReadback":"reverify"}'::jsonb
),
(
  'ph.namria.geoportal', '1.0.0',
  '{"type":"service_credential","credentialMode":"none"}'::jsonb,
  '{"required":["geospatial.catalog.read"],"optional":[],"leastPrivilege":"read-first"}'::jsonb,
  '{"web":null,"mobile":null}'::jsonb,
  '{"probe":"geospatial.catalog.read","maxAgeSeconds":900,"expiryState":"needs_attention"}'::jsonb,
  '[{"key":"geospatial.catalog.read","mode":"read"}]'::jsonb,
  'low', '{"subject":"providerIdentity","label":"providerIdentity","tenant":"organization_id","required":true}'::jsonb,
  '{"storage":"supabase_vault","serverSideOnly":true,"credentialMode":"none","refresh":false,"revoke":false,"rotationDays":null}'::jsonb,
  '{"required":false,"mode":"read_only","forModes":[]}'::jsonb,
  '{"mode":"provider_managed_ph","selectionRequired":true}'::jsonb,
  '{"guidedReconnect":true,"invalidReadback":"reverify"}'::jsonb
)
on conflict do nothing;

create or replace function public.pandora_connection_commit_public_safe_read_v1(
  p_organization_id uuid,
  p_provider_key text,
  p_actor_user_id uuid,
  p_tenant_key text,
  p_provider_identity text,
  p_verified_at timestamptz,
  p_provider_readback jsonb
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','private','vault','auth','extensions','pg_temp' as $$
declare
  v_account private.pandora_connection_accounts_v1%rowtype;
  v_required text[];
  v_probe text;
  v_subject_hash text;
  v_readback_hash text;
  v_secret_id uuid;
  v_secret_name text;
  v_now timestamptz := clock_timestamp();
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  if p_provider_key not in ('ph.psa.openstat','ph.phivolcs.hazard_gis','ph.namria.geoportal')
     or length(trim(coalesce(p_tenant_key,''))) not between 1 and 320
     or length(trim(coalesce(p_provider_identity,''))) not between 1 and 320
     or p_verified_at is null
     or p_verified_at < v_now - interval '5 minutes'
     or p_verified_at > v_now + interval '1 minute'
     or p_provider_readback is null
     or jsonb_typeof(p_provider_readback) <> 'object'
     or octet_length(p_provider_readback::text) > 8192 then
    raise exception 'pandora_public_safe_read_invalid' using errcode='22023';
  end if;
  if not exists(
    select 1 from public.memberships m
    where m.organization_id=p_organization_id and m.user_id=p_actor_user_id
      and m.status='active' and m.role in ('owner','admin')
  ) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  if private.pandora_control_plane_json_has_secret_keys(p_provider_readback) then
    raise exception 'pandora_connection_readback_contains_secret_keys' using errcode='22023';
  end if;

  select array(select jsonb_array_elements_text(c.scopes->'required')),
         c.health->>'probe'
  into v_required, v_probe
  from private.pandora_connection_manifest_contracts_v1 c
  where c.provider_key=p_provider_key and c.manifest_version='1.0.0'
    and c.credential_policy->>'credentialMode'='none';
  if coalesce(cardinality(v_required),0)=0 or nullif(v_probe,'') is null then
    raise exception 'pandora_public_safe_read_manifest_unavailable' using errcode='55000';
  end if;

  if p_provider_readback->>'verificationState' <> 'provider_readback_verified'
     or p_provider_readback->>'providerKey' <> p_provider_key
     or p_provider_readback->>'organizationId' <> p_organization_id::text
     or p_provider_readback->>'tenantId' <> p_organization_id::text
     or p_provider_readback->>'tenantKey' <> trim(p_tenant_key)
     or p_provider_readback->>'providerIdentity' <> trim(p_provider_identity)
     or p_provider_readback#>>'{health,state}' <> 'healthy'
     or p_provider_readback#>>'{probe,capabilityKey}' <> v_probe
     or coalesce(p_provider_readback#>'{probe,ok}','false'::jsonb) <> 'true'::jsonb
     or coalesce(p_provider_readback->'credentialReturned','true'::jsonb) <> 'false'::jsonb
     or coalesce(p_provider_readback->'httpStatus','0'::jsonb) <> '200'::jsonb
     or coalesce(p_provider_readback->>'bodySha256','') !~ '^[0-9a-f]{64}$'
     or jsonb_typeof(p_provider_readback->'grantedScopes') <> 'array'
     or not (p_provider_readback->'grantedScopes' @> to_jsonb(v_required))
     or nullif(p_provider_readback->>'observedAt','') is null
     or (p_provider_readback->>'observedAt')::timestamptz <> p_verified_at then
    raise exception 'pandora_public_safe_read_readback_mismatch' using errcode='22023';
  end if;

  v_subject_hash := encode(extensions.digest(
    convert_to(p_provider_key||':'||trim(p_provider_identity),'UTF8'),'sha256'
  ),'hex');
  v_readback_hash := encode(extensions.digest(
    convert_to(p_provider_readback::text,'UTF8'),'sha256'
  ),'hex');

  select * into v_account
  from private.pandora_connection_accounts_v1 a
  where a.organization_id=p_organization_id and a.provider_key=p_provider_key
    and a.account_subject_hash=v_subject_hash and a.tenant_key=trim(p_tenant_key)
  for update;

  if v_account.id is null then
    v_secret_name := 'pandora_public_safe_read_'||
      replace(p_organization_id::text,'-','')||'_'||
      replace(p_provider_key,'.','_');
    v_secret_id := vault.create_secret(
      extensions.gen_random_uuid()::text||extensions.gen_random_uuid()::text,
      v_secret_name,
      'Opaque internal marker for a credentialless official public API connection'
    );
    insert into private.pandora_connection_accounts_v1(
      organization_id,provider_key,manifest_version,connected_by,
      account_subject_hash,account_label,tenant_key,tenant_label,
      credential_secret_id,credential_version,granted_scopes,granted_capabilities,
      status,health_state,last_verified_at,provider_readback_hash,metadata_redacted
    ) values(
      p_organization_id,p_provider_key,'1.0.0',p_actor_user_id,
      v_subject_hash,trim(p_provider_identity),trim(p_tenant_key),'Official public API',
      v_secret_id,1,v_required,array[v_probe],
      'connected','healthy',p_verified_at,v_readback_hash,
      jsonb_build_object(
        'connectionMode','public_safe_read','credentialMode','none',
        'providerIdentity',trim(p_provider_identity),'httpStatus',200,
        'bodySha256',p_provider_readback->>'bodySha256'
      )
    ) returning * into v_account;
  else
    update private.pandora_connection_accounts_v1 set
      connected_by=p_actor_user_id,
      account_label=trim(p_provider_identity),
      granted_scopes=v_required,
      granted_capabilities=array[v_probe],
      status='connected',
      health_state='healthy',
      last_verified_at=p_verified_at,
      revoked_at=null,
      failure_code=null,
      provider_readback_hash=v_readback_hash,
      metadata_redacted=jsonb_build_object(
        'connectionMode','public_safe_read','credentialMode','none',
        'providerIdentity',trim(p_provider_identity),'httpStatus',200,
        'bodySha256',p_provider_readback->>'bodySha256'
      ),
      updated_at=clock_timestamp()
    where id=v_account.id
    returning * into v_account;
  end if;

  insert into private.pandora_connection_active_accounts_v1(
    organization_id,provider_key,connection_id,tenant_key,selected_by,selected_at
  ) values(
    p_organization_id,p_provider_key,v_account.id,trim(p_tenant_key),p_actor_user_id,clock_timestamp()
  )
  on conflict (organization_id,provider_key) do update set
    connection_id=excluded.connection_id,
    tenant_key=excluded.tenant_key,
    selected_by=excluded.selected_by,
    selected_at=excluded.selected_at;

  perform private.append_audit_event(
    p_organization_id,null,null,'human'::public.audit_actor_type,p_actor_user_id,
    'connection.public_safe_read_connected',
    jsonb_build_object(
      'provider',p_provider_key,'connection_id',v_account.id,
      'tenant_key',v_account.tenant_key,'provider_readback_hash',v_readback_hash
    )
  );

  return jsonb_build_object(
    'ok',true,'provider',p_provider_key,'organizationId',p_organization_id,
    'tenantId',p_organization_id,'connectionId',v_account.id,
    'tenantKey',v_account.tenant_key,'state','connected',
    'healthState','healthy','verifiedAt',p_verified_at,
    'providerReadbackHash',v_readback_hash,'credentialReturned',false
  );
end;
$$;

revoke all on function public.pandora_connection_commit_public_safe_read_v1(
  uuid,text,uuid,text,text,timestamptz,jsonb
) from public, anon, authenticated;
grant execute on function public.pandora_connection_commit_public_safe_read_v1(
  uuid,text,uuid,text,text,timestamptz,jsonb
) to service_role;
