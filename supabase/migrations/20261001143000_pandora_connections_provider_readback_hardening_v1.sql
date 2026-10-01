-- Universal Connections provider-readback hardening.
-- A healthy flag alone cannot create Connected: the exact account, tenant,
-- scopes, capabilities, safe provider probe, freshness and credential state
-- must all agree.

create or replace function private.pandora_connection_required_capabilities_v1(
  p_provider_key text
) returns text[]
language sql stable security definer set search_path='' as $$
  select coalesce(array_agg(item->>'key' order by ord),array[]::text[])
  from private.pandora_connection_manifest_contracts_v1 c,
       jsonb_array_elements(c.capabilities) with ordinality x(item,ord)
  where c.provider_key=p_provider_key
    and c.manifest_version='1.0.0'
    and item->>'mode'<>'write';
$$;

revoke all on function private.pandora_connection_required_capabilities_v1(text)
  from public,anon,authenticated;

create or replace function public.pandora_connection_health_commit_v2(
  p_organization_id uuid,
  p_provider_key text,
  p_connection_id uuid,
  p_tenant_key text,
  p_provider_subject text,
  p_granted_scopes text[],
  p_granted_capabilities text[],
  p_provider_readback jsonb,
  p_healthy boolean,
  p_verified_at timestamptz,
  p_failure_code text default null
) returns jsonb
language plpgsql security definer
set search_path='pg_catalog','public','private','auth','extensions','pg_temp' as $$
declare
  v_account private.pandora_connection_accounts_v1%rowtype;
  v_manifest private.pandora_connection_manifest_contracts_v1%rowtype;
  v_subject_hash text;
  v_readback_hash text;
  v_required_scopes text[];
  v_required_capabilities text[];
  v_probe text;
  v_http_status integer;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  if p_healthy is not true
     or p_verified_at is null
     or p_verified_at<clock_timestamp()-interval '5 minutes'
     or p_verified_at>clock_timestamp()+interval '1 minute'
     or length(trim(coalesce(p_provider_subject,''))) not between 1 and 512
     or length(trim(coalesce(p_tenant_key,''))) not between 1 and 320
     or p_provider_readback is null
     or jsonb_typeof(p_provider_readback)<>'object'
     or octet_length(p_provider_readback::text)>8192 then
    raise exception 'pandora_connection_verified_readback_invalid' using errcode='22023';
  end if;
  if private.pandora_control_plane_json_has_secret_keys(p_provider_readback) then
    raise exception 'pandora_connection_readback_contains_secret_keys' using errcode='22023';
  end if;

  select * into v_account
  from private.pandora_connection_accounts_v1
  where id=p_connection_id
    and organization_id=p_organization_id
    and provider_key=p_provider_key
    and tenant_key=trim(p_tenant_key)
    and status<>'revoked'
    and revoked_at is null
  for update;
  if v_account.id is null then
    raise exception 'pandora_connection_account_not_found' using errcode='22023';
  end if;

  select * into v_manifest
  from private.pandora_connection_manifest_contracts_v1
  where provider_key=p_provider_key and manifest_version=v_account.manifest_version;
  if v_manifest.provider_key is null then
    raise exception 'pandora_connection_manifest_not_found' using errcode='22023';
  end if;

  v_subject_hash:=encode(
    extensions.digest(
      convert_to(p_provider_key||':'||trim(p_provider_subject),'UTF8'),
      'sha256'
    ),
    'hex'
  );
  if v_subject_hash<>v_account.account_subject_hash then
    raise exception 'pandora_connection_account_identity_mismatch' using errcode='42501';
  end if;

  v_required_scopes:=private.pandora_connection_required_scopes_v1(p_provider_key);
  v_required_capabilities:=private.pandora_connection_required_capabilities_v1(p_provider_key);
  if not (
    v_required_scopes<@coalesce(p_granted_scopes,array[]::text[])
    and coalesce(p_granted_scopes,array[]::text[])<@v_required_scopes
  ) then
    raise exception 'pandora_connection_required_scopes_missing' using errcode='42501';
  end if;
  if cardinality(v_required_capabilities)=0
     or not (
       v_required_capabilities<@coalesce(p_granted_capabilities,array[]::text[])
       and coalesce(p_granted_capabilities,array[]::text[])<@v_required_capabilities
     ) then
    raise exception 'pandora_connection_required_capabilities_missing' using errcode='42501';
  end if;

  v_probe:=nullif(trim(v_manifest.health->>'probe'),'');
  v_http_status:=case
    when p_provider_readback->>'httpStatus' ~ '^[0-9]{3}$'
      then (p_provider_readback->>'httpStatus')::integer
    else null
  end;
  if v_probe is null
     or p_provider_readback->>'probe'<>v_probe
     or coalesce((p_provider_readback->>'identityVerified')::boolean,false) is not true
     or v_http_status not between 200 and 299 then
    raise exception 'pandora_connection_safe_probe_not_verified' using errcode='42501';
  end if;

  v_readback_hash:=encode(
    extensions.digest(convert_to(p_provider_readback::text,'UTF8'),'sha256'),
    'hex'
  );
  update private.pandora_connection_accounts_v1 set
    granted_scopes=coalesce(p_granted_scopes,array[]::text[]),
    granted_capabilities=coalesce(p_granted_capabilities,array[]::text[]),
    status='connected',
    health_state='healthy',
    last_verified_at=p_verified_at,
    failure_code=null,
    provider_readback_hash=v_readback_hash,
    metadata_redacted=p_provider_readback||jsonb_build_object(
      'verifiedBy','provider_readback',
      'verifiedAt',p_verified_at
    ),
    updated_at=clock_timestamp()
  where id=v_account.id
  returning * into v_account;

  perform private.append_audit_event(
    v_account.organization_id,null,null,'provider'::public.audit_actor_type,null,
    'connection.health_verified',
    jsonb_build_object(
      'provider',v_account.provider_key,
      'connection_id',v_account.id,
      'tenant_key',v_account.tenant_key,
      'readback_hash',v_readback_hash,
      'probe',v_probe,
      'healthy',true
    )
  );
  return jsonb_build_object(
    'ok',true,
    'connectionId',v_account.id,
    'provider',v_account.provider_key,
    'tenantId',v_account.organization_id,
    'tenantKey',v_account.tenant_key,
    'accountIdentityVerified',true,
    'scopesVerified',true,
    'capabilitiesVerified',true,
    'probeVerified',true,
    'healthy',true,
    'verifiedAt',p_verified_at,
    'failureCode',null
  );
end; $$;

revoke all on function public.pandora_connection_health_commit_v2(
  uuid,text,uuid,text,text,text[],text[],jsonb,boolean,timestamptz,text
) from public,anon,authenticated;
grant execute on function public.pandora_connection_health_commit_v2(
  uuid,text,uuid,text,text,text[],text[],jsonb,boolean,timestamptz,text
) to service_role;

create or replace function public.pandora_live_connections_v1(p_organization_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','public','private','vault','auth','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_rows jsonb;
begin
  if v_uid is null or not private.is_org_member(p_organization_id) then
    raise exception 'pandora_connection_membership_required' using errcode='42501';
  end if;
  select coalesce(jsonb_agg(row_json order by row_json->>'provider'),'[]'::jsonb)
  into v_rows
  from (
    select jsonb_build_object(
      'provider',c.provider_key,
      'displayName',m.display_name,
      'riskClass',c.risk_class,
      'state',case
        when a.id is null then 'Needs authorization'
        when a.revoked_at is not null or a.status='revoked' then 'Needs attention'
        when a.credential_expires_at is not null and a.credential_expires_at<=clock_timestamp() then 'Needs attention'
        when a.rotation_due_at is null or a.rotation_due_at<=clock_timestamp() then 'Needs attention'
        when a.health_state<>'healthy' then 'Needs attention'
        when a.last_verified_at is null
          or a.last_verified_at>clock_timestamp()+interval '1 minute'
          or a.last_verified_at<clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
          then 'Needs attention'
        when not (
          private.pandora_connection_required_scopes_v1(c.provider_key)<@a.granted_scopes
          and a.granted_scopes<@private.pandora_connection_required_scopes_v1(c.provider_key)
        ) then 'Needs attention'
        when not (
          private.pandora_connection_required_capabilities_v1(c.provider_key)<@a.granted_capabilities
          and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(c.provider_key)
        ) then 'Needs attention'
        when a.provider_readback_hash is null
          or a.metadata_redacted->>'verifiedBy'<>'provider_readback'
          or a.metadata_redacted->>'probe'<>c.health->>'probe'
          or coalesce((a.metadata_redacted->>'identityVerified')::boolean,false) is not true
          then 'Needs attention'
        when not exists(select 1 from vault.secrets s where s.id=a.credential_secret_id) then 'Needs attention'
        else 'Connected'
      end,
      'connected',coalesce(
        a.id is not null
        and a.revoked_at is null
        and a.status='connected'
        and a.health_state='healthy'
        and (a.credential_expires_at is null or a.credential_expires_at>clock_timestamp())
        and a.rotation_due_at>clock_timestamp()
        and a.last_verified_at between
          clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
          and clock_timestamp()+interval '1 minute'
        and private.pandora_connection_required_scopes_v1(c.provider_key)<@a.granted_scopes
        and a.granted_scopes<@private.pandora_connection_required_scopes_v1(c.provider_key)
        and private.pandora_connection_required_capabilities_v1(c.provider_key)<@a.granted_capabilities
        and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(c.provider_key)
        and cardinality(private.pandora_connection_required_capabilities_v1(c.provider_key))>0
        and a.provider_readback_hash is not null
        and a.metadata_redacted->>'verifiedBy'='provider_readback'
        and a.metadata_redacted->>'probe'=c.health->>'probe'
        and coalesce((a.metadata_redacted->>'identityVerified')::boolean,false)
        and exists(select 1 from vault.secrets s where s.id=a.credential_secret_id),
        false
      ),
      'activeAccount',case when a.id is null then null else jsonb_build_object(
        'id',a.id,
        'label',a.account_label,
        'tenantId',a.organization_id,
        'tenantKey',a.tenant_key,
        'tenant',a.tenant_label,
        'scopes',to_jsonb(a.granted_scopes),
        'capabilities',to_jsonb(a.granted_capabilities),
        'lastVerifiedAt',a.last_verified_at,
        'expiresAt',a.credential_expires_at,
        'rotationDueAt',a.rotation_due_at,
        'health',a.health_state,
        'failureCode',a.failure_code,
        'providerReadbackVerified',
          a.provider_readback_hash is not null
          and a.metadata_redacted->>'verifiedBy'='provider_readback'
          and a.metadata_redacted->>'probe'=c.health->>'probe'
          and coalesce((a.metadata_redacted->>'identityVerified')::boolean,false)
      ) end,
      'accounts',coalesce((
        select jsonb_agg(jsonb_build_object(
          'id',aa.id,
          'label',aa.account_label,
          'tenantId',aa.organization_id,
          'tenantKey',aa.tenant_key,
          'tenant',aa.tenant_label,
          'selected',aa.id=a.id and aa.tenant_key=s.tenant_key,
          'health',aa.health_state,
          'lastVerifiedAt',aa.last_verified_at,
          'expiresAt',aa.credential_expires_at,
          'rotationDueAt',aa.rotation_due_at
        ) order by aa.account_label)
        from private.pandora_connection_accounts_v1 aa
        where aa.organization_id=p_organization_id
          and aa.provider_key=c.provider_key
          and aa.revoked_at is null
      ),'[]'::jsonb),
      'requiredScopes',to_jsonb(private.pandora_connection_required_scopes_v1(c.provider_key)),
      'requiredCapabilities',to_jsonb(private.pandora_connection_required_capabilities_v1(c.provider_key)),
      'healthContract',c.health,
      'recovery',c.recovery,
      'writeAuthorization',c.write_authorization,
      'authority','live_provider_readback'
    ) row_json
    from private.pandora_connection_manifest_contracts_v1 c
    join public.pandora_provider_manifests m using(provider_key,manifest_version)
    left join private.pandora_connection_active_accounts_v1 s
      on s.organization_id=p_organization_id and s.provider_key=c.provider_key
    left join private.pandora_connection_accounts_v1 a
      on a.id=s.connection_id
      and a.organization_id=s.organization_id
      and a.provider_key=s.provider_key
      and a.tenant_key=s.tenant_key
    where m.lifecycle_state='active'
  ) projected;
  return jsonb_build_object(
    'contractVersion','pandora-live-connections-v1',
    'organizationId',p_organization_id,
    'observedAt',clock_timestamp(),
    'authority','live_connections_not_catalog',
    'providers',v_rows
  );
end; $$;

revoke all on function public.pandora_live_connections_v1(uuid)
  from public,anon;
grant execute on function public.pandora_live_connections_v1(uuid)
  to authenticated,service_role;

create or replace function private.pandora_connection_reconcile_health_v1()
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','vault','extensions','pg_temp' as $$
declare
  v_row record;
  v_count integer:=0;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  for v_row in
    update private.pandora_connection_accounts_v1 a set
      status='needs_attention',
      health_state='unhealthy',
      failure_code=case
        when a.credential_expires_at is not null and a.credential_expires_at<=clock_timestamp()
          then 'CREDENTIAL_EXPIRED'
        when a.rotation_due_at is null or a.rotation_due_at<=clock_timestamp()
          then 'CREDENTIAL_ROTATION_DUE'
        when a.last_verified_at is null
          or a.last_verified_at>clock_timestamp()+interval '1 minute'
          or a.last_verified_at<clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
          then 'PROVIDER_READBACK_STALE'
        when not (
          private.pandora_connection_required_scopes_v1(a.provider_key)<@a.granted_scopes
          and a.granted_scopes<@private.pandora_connection_required_scopes_v1(a.provider_key)
        )
          then 'REQUIRED_SCOPES_MISSING'
        when not (
          private.pandora_connection_required_capabilities_v1(a.provider_key)<@a.granted_capabilities
          and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(a.provider_key)
        )
          then 'REQUIRED_CAPABILITIES_MISSING'
        when a.provider_readback_hash is null
          or a.metadata_redacted->>'verifiedBy'<>'provider_readback'
          or a.metadata_redacted->>'probe'<>c.health->>'probe'
          or coalesce((a.metadata_redacted->>'identityVerified')::boolean,false) is not true
          then 'PROVIDER_READBACK_UNVERIFIED'
        else 'CREDENTIAL_UNAVAILABLE'
      end,
      updated_at=clock_timestamp()
    from private.pandora_connection_manifest_contracts_v1 c
    where a.provider_key=c.provider_key
      and a.manifest_version=c.manifest_version
      and a.status='connected'
      and a.revoked_at is null
      and (
        (a.credential_expires_at is not null and a.credential_expires_at<=clock_timestamp())
        or a.rotation_due_at is null
        or a.rotation_due_at<=clock_timestamp()
        or a.last_verified_at is null
        or a.last_verified_at>clock_timestamp()+interval '1 minute'
        or a.last_verified_at<clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
        or not (
          private.pandora_connection_required_scopes_v1(a.provider_key)<@a.granted_scopes
          and a.granted_scopes<@private.pandora_connection_required_scopes_v1(a.provider_key)
        )
        or not (
          private.pandora_connection_required_capabilities_v1(a.provider_key)<@a.granted_capabilities
          and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(a.provider_key)
        )
        or a.provider_readback_hash is null
        or a.metadata_redacted->>'verifiedBy'<>'provider_readback'
        or a.metadata_redacted->>'probe'<>c.health->>'probe'
        or coalesce((a.metadata_redacted->>'identityVerified')::boolean,false) is not true
        or not exists(select 1 from vault.secrets s where s.id=a.credential_secret_id)
      )
    returning a.*
  loop
    v_count:=v_count+1;
    perform private.append_audit_event(
      v_row.organization_id,null,null,'provider'::public.audit_actor_type,null,
      'connection.health_needs_attention',
      jsonb_build_object(
        'provider',v_row.provider_key,
        'connection_id',v_row.id,
        'tenant_key',v_row.tenant_key,
        'failure_code',v_row.failure_code
      )
    );
  end loop;
  return jsonb_build_object('ok',true,'reconciled',v_count,'observedAt',clock_timestamp());
end; $$;

revoke all on function private.pandora_connection_reconcile_health_v1()
  from public,anon,authenticated;

do $schedule$
declare v_job record;
begin
  if to_regnamespace('cron') is not null
     and to_regprocedure('cron.schedule(text,text,text)') is not null then
    for v_job in execute
      'select jobid from cron.job where jobname=$1'
      using 'pandora-connections-health-reconcile-v1'
    loop
      execute 'select cron.unschedule($1)' using v_job.jobid;
    end loop;
    perform cron.schedule(
      'pandora-connections-health-reconcile-v1',
      '*/5 * * * *',
      'select private.pandora_connection_reconcile_health_v1();'
    );
  end if;
end;
$schedule$;

-- The seven-argument Google commit is service-only in its body; align its ACL.
revoke all on function public.pandora_google_workspace_oauth_commit_v1(
  text,text,text,text,text,text[],text
) from public,anon,authenticated;
grant execute on function public.pandora_google_workspace_oauth_commit_v1(
  text,text,text,text,text,text[],text
) to service_role;

comment on function public.pandora_connection_health_commit_v2(
  uuid,text,uuid,text,text,text[],text[],jsonb,boolean,timestamptz,text
) is 'Commits fresh provider health only when exact account identity, tenant, scopes, capabilities and the manifest safe-read probe are verified.';

comment on function private.pandora_connection_reconcile_health_v1()
is 'Five-minute fail-closed reconciliation for expired, rotation-due, stale, scope-deficient, capability-deficient or unverifiable connections.';
