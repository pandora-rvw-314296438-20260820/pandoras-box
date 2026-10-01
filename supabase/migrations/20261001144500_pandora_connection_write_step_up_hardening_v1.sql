-- Bind Supabase/Vercel write approvals to a currently verified live account and exact target.

create or replace function private.pandora_connection_is_current_live_v1(
  p_organization_id uuid,p_provider_key text,p_connection_id uuid,p_tenant_key text
) returns boolean language sql stable security definer
set search_path='pg_catalog','public','private','vault','pg_temp' as $$
  select exists(
    select 1
    from private.pandora_connection_active_accounts_v1 s
    join private.pandora_connection_accounts_v1 a
      on a.id=s.connection_id and a.organization_id=s.organization_id
      and a.provider_key=s.provider_key and a.tenant_key=s.tenant_key
    join private.pandora_connection_manifest_contracts_v1 c
      on c.provider_key=a.provider_key and c.manifest_version=a.manifest_version
    where s.organization_id=p_organization_id and s.provider_key=p_provider_key
      and s.connection_id=p_connection_id and s.tenant_key=trim(p_tenant_key)
      and a.status='connected' and a.health_state='healthy' and a.revoked_at is null
      and (a.credential_expires_at is null or a.credential_expires_at>clock_timestamp())
      and a.rotation_due_at>clock_timestamp()
      and a.last_verified_at between
        clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
        and clock_timestamp()+interval '1 minute'
      and private.pandora_connection_required_scopes_v1(a.provider_key)<@a.granted_scopes
      and a.granted_scopes<@private.pandora_connection_required_scopes_v1(a.provider_key)
      and private.pandora_connection_required_capabilities_v1(a.provider_key)<@a.granted_capabilities
      and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(a.provider_key)
      and cardinality(private.pandora_connection_required_capabilities_v1(a.provider_key))>0
      and a.provider_readback_hash is not null
      and a.metadata_redacted->>'verifiedBy'='provider_readback'
      and a.metadata_redacted->>'probe'=c.health->>'probe'
      and coalesce((a.metadata_redacted->>'identityVerified')::boolean,false)
      and exists(select 1 from vault.secrets v where v.id=a.credential_secret_id)
  );
$$;

revoke all on function private.pandora_connection_is_current_live_v1(uuid,text,uuid,text)
  from public,anon,authenticated;

create or replace function public.pandora_connection_write_preview_v1(
  p_organization_id uuid,p_provider_key text,p_connection_id uuid,p_tenant_key text,
  p_operation text,p_exact_target jsonb
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','extensions','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_hash text; v_id uuid; v_expires timestamptz:=clock_timestamp()+interval '10 minutes';
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  if p_provider_key not in ('supabase','vercel') or p_operation !~ '^[a-z][a-z0-9_.-]{2,79}$'
     or p_exact_target is null or jsonb_typeof(p_exact_target)<>'object' or p_exact_target='{}'::jsonb
     or octet_length(p_exact_target::text)>8192 then
    raise exception 'pandora_connection_write_preview_invalid' using errcode='22023';
  end if;
  if private.pandora_control_plane_json_has_secret_keys(p_exact_target) then
    raise exception 'pandora_connection_write_preview_contains_secret_keys' using errcode='22023';
  end if;
  if not private.pandora_connection_is_current_live_v1(p_organization_id,p_provider_key,p_connection_id,p_tenant_key) then
    raise exception 'pandora_connection_current_live_required' using errcode='42501';
  end if;
  update private.pandora_connection_write_approvals_v1 set status='expired'
  where organization_id=p_organization_id and provider_key=p_provider_key
    and connection_id=p_connection_id and tenant_key=trim(p_tenant_key)
    and status='pending' and expires_at<=clock_timestamp();
  v_hash:=encode(extensions.digest(convert_to(
    p_organization_id::text||'|'||p_provider_key||'|'||p_connection_id::text||'|'||trim(p_tenant_key)||'|'||p_operation||'|'||p_exact_target::text,
    'UTF8'),'sha256'),'hex');
  insert into private.pandora_connection_write_approvals_v1(
    organization_id,provider_key,connection_id,tenant_key,requested_by,operation,target_preview,target_hash,expires_at
  ) values(p_organization_id,p_provider_key,p_connection_id,trim(p_tenant_key),v_uid,p_operation,p_exact_target,v_hash,v_expires)
  returning id into v_id;
  perform private.append_audit_event(p_organization_id,null,null,'human'::public.audit_actor_type,v_uid,
    'connection.write_previewed',jsonb_build_object('provider',p_provider_key,'approval_id',v_id,'connection_id',p_connection_id,'tenant_key',trim(p_tenant_key),'operation',p_operation,'target_hash',v_hash));
  return jsonb_build_object('ok',true,'approvalId',v_id,'provider',p_provider_key,'connectionId',p_connection_id,
    'tenantId',p_organization_id,'tenantKey',trim(p_tenant_key),'operation',p_operation,'exactTargetPreview',p_exact_target,
    'targetHash',v_hash,'status','pending','expiresAt',v_expires,'stepUpRequired',true,'confirmationText',v_hash);
end; $$;

create or replace function public.pandora_connection_write_approve_v1(
  p_organization_id uuid,p_approval_id uuid,p_provider_key text,
  p_connection_id uuid,p_tenant_key text,p_confirmation_hash text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','pg_temp' as $$
declare v_uid uuid:=auth.uid(); v_row private.pandora_connection_write_approvals_v1%rowtype;
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_connection_active_admin_required' using errcode='42501';
  end if;
  if coalesce(auth.jwt()->>'aal','')<>'aal2' then
    raise exception 'pandora_connection_write_step_up_required' using errcode='42501';
  end if;
  update private.pandora_connection_write_approvals_v1 set status='approved',approved_by=v_uid,approved_at=clock_timestamp()
  where id=p_approval_id and organization_id=p_organization_id and provider_key=p_provider_key
    and connection_id=p_connection_id and tenant_key=trim(p_tenant_key) and status='pending'
    and expires_at>clock_timestamp() and target_hash=p_confirmation_hash
  returning * into v_row;
  if v_row.id is null then raise exception 'pandora_connection_write_approval_invalid_or_expired' using errcode='42501'; end if;
  perform private.append_audit_event(p_organization_id,null,null,'human'::public.audit_actor_type,v_uid,
    'connection.write_approved',jsonb_build_object('provider',v_row.provider_key,'approval_id',v_row.id,'connection_id',v_row.connection_id,'tenant_key',v_row.tenant_key,'operation',v_row.operation,'target_hash',v_row.target_hash,'aal','aal2'));
  return jsonb_build_object('ok',true,'approvalId',v_row.id,'provider',v_row.provider_key,'connectionId',v_row.connection_id,
    'tenantId',v_row.organization_id,'tenantKey',v_row.tenant_key,'operation',v_row.operation,'targetHash',v_row.target_hash,'status','approved','expiresAt',v_row.expires_at);
end; $$;

create or replace function public.pandora_connection_write_consume_v1(
  p_organization_id uuid,p_approval_id uuid,p_provider_key text,p_connection_id uuid,
  p_tenant_key text,p_operation text,p_target_hash text
) returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','auth','extensions','pg_temp' as $$
declare v_row private.pandora_connection_write_approvals_v1%rowtype;
begin
  if current_user not in ('service_role','postgres','supabase_admin')
     and coalesce(auth.jwt()->>'role','')<>'service_role' then
    raise exception 'pandora_connection_service_role_required' using errcode='42501';
  end if;
  if not private.pandora_connection_is_current_live_v1(p_organization_id,p_provider_key,p_connection_id,p_tenant_key) then
    raise exception 'pandora_connection_current_live_required' using errcode='42501';
  end if;
  update private.pandora_connection_write_approvals_v1 set status='consumed',consumed_at=clock_timestamp()
  where id=p_approval_id and organization_id=p_organization_id and provider_key=p_provider_key
    and connection_id=p_connection_id and tenant_key=trim(p_tenant_key) and operation=p_operation
    and target_hash=p_target_hash and status='approved' and expires_at>clock_timestamp()
    and target_hash=encode(extensions.digest(convert_to(
      organization_id::text||'|'||provider_key||'|'||connection_id::text||'|'||tenant_key||'|'||operation||'|'||target_preview::text,
      'UTF8'),'sha256'),'hex')
  returning * into v_row;
  if v_row.id is null then raise exception 'pandora_connection_write_approval_not_consumable' using errcode='42501'; end if;
  perform private.append_audit_event(p_organization_id,null,null,'system'::public.audit_actor_type,null,
    'connection.write_approval_consumed',jsonb_build_object('provider',v_row.provider_key,'approval_id',v_row.id,'connection_id',v_row.connection_id,'tenant_key',v_row.tenant_key,'operation',v_row.operation,'target_hash',v_row.target_hash));
  return jsonb_build_object('ok',true,'approvalId',v_row.id,'provider',v_row.provider_key,'connectionId',v_row.connection_id,
    'tenantId',v_row.organization_id,'tenantKey',v_row.tenant_key,'operation',v_row.operation,'exactTarget',v_row.target_preview,
    'targetHash',v_row.target_hash,'status','consumed');
end; $$;

comment on function private.pandora_connection_is_current_live_v1(uuid,text,uuid,text)
is 'Exact tuple and fresh provider-readback predicate for governed Supabase/Vercel writes.';
