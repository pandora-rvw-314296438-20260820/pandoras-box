-- FB-012: make Meta readiness fail closed on membership, expiry, permissions and health.
create or replace function public.pandora_meta_connection_v1(p_organization_id uuid)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,private,auth,pg_temp
as $fn$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_row private.pandora_meta_connections%rowtype;
  v_installations jsonb:='[]'::jsonb;
  v_required text[]:=private.pandora_meta_required_scopes_v1();
  v_scopes_verified boolean:=false;
  v_token_expiry_known boolean:=false;
  v_token_expired boolean:=false;
  v_health_verified boolean:=false;
  v_can_use boolean:=false;
  v_state text;
  v_guidance text;
begin
  if v_uid is null then
    raise exception 'pandora_meta_connection_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;

  if v_role is null or v_role not in ('owner','admin') then
    raise exception 'pandora_meta_connection_owner_required' using errcode='42501';
  end if;

  select * into v_row
  from private.pandora_meta_connections
  where organization_id=p_organization_id;

  if v_row.organization_id is null then
    return jsonb_build_object(
      'ok',true,'provider','meta','connected',false,
      'state','Needs authorization','canUseNow',false,
      'scopesVerified',false,'tokenExpiryKnown',false,'tokenExpired',false,'healthVerified',false,
      'guidance','Connect Facebook to authorize the required account and assets.'
    );
  end if;

  v_scopes_verified:=v_required <@ coalesce(v_row.scopes,array[]::text[]);
  v_token_expiry_known:=v_row.token_expires_at is not null;
  v_token_expired:=not v_token_expiry_known
    or v_row.token_expires_at<=clock_timestamp();
  v_health_verified:=v_row.last_verified_at is not null
    and v_row.last_verified_at>=clock_timestamp()-interval '24 hours'
    and v_row.last_error is null
    and coalesce(v_row.last_http_status between 200 and 299,false);

  v_can_use:=v_row.status='connected'
    and v_token_expiry_known
    and not v_token_expired
    and v_scopes_verified
    and v_health_verified;

  v_state:=case
    when v_row.status<>'connected' then 'Reconnect required'
    when not v_token_expiry_known then 'Reconnect required'
    when v_token_expired then 'Reconnect required'
    when not v_scopes_verified then 'Permissions incomplete'
    when not v_health_verified then 'Verification required'
    else 'Connected'
  end;

  v_guidance:=case
    when v_row.status<>'connected' then 'Reconnect Facebook before using Meta.'
    when not v_token_expiry_known then 'Reconnect Facebook to establish a verifiable token expiry.'
    when v_token_expired then 'Reconnect Facebook to refresh the expired access token.'
    when not v_scopes_verified then 'Reconnect Facebook and grant all required permissions.'
    when not v_health_verified then 'Refresh connection health or reconnect Facebook before using Meta.'
    else 'Connection is verified and usable.'
  end;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'installationId',c.id,'pageId',c.external_account_id,'pageName',c.display_name,
      'status',c.status,
      'scopesVerified',v_required <@ coalesce(c.scopes,array[]::text[]),
      'healthVerified',c.last_health_check_at is not null
        and c.last_health_check_at>=clock_timestamp()-interval '24 hours'
        and c.status='active'::public.connector_status,
      'canUseNow',c.status='active'::public.connector_status
        and v_required <@ coalesce(c.scopes,array[]::text[])
        and c.last_health_check_at is not null
        and c.last_health_check_at>=clock_timestamp()-interval '24 hours',
      'lastVerifiedAt',c.last_health_check_at
    )
    order by c.display_name
  ),'[]'::jsonb)
  into v_installations
  from public.connector_installations c
  where c.organization_id=p_organization_id and c.provider='meta';

  return jsonb_build_object(
    'ok',true,'provider','meta','connected',v_row.status='connected',
    'state',v_state,'canUseNow',v_can_use,'guidance',v_guidance,
    'account',jsonb_build_object(
      'id',v_row.provider_user_id,
      'label',coalesce(v_row.display_name,'Meta account'),
      'verified',v_health_verified
    ),
    'scopes',to_jsonb(v_row.scopes),'requiredScopes',to_jsonb(v_required),
    'scopesVerified',v_scopes_verified,'tokenExpiryKnown',v_token_expiry_known,
    'tokenExpired',v_token_expired,'healthVerified',v_health_verified,
    'pages',v_row.pages,'adAccounts',v_row.ad_accounts,'installations',v_installations,
    'tokenExpiresAt',v_row.token_expires_at,'lastVerifiedAt',v_row.last_verified_at,
    'lastHttpStatus',v_row.last_http_status,'lastError',v_row.last_error,
    'rawStatus',v_row.status
  );
end;
$fn$;

revoke all on function public.pandora_meta_connection_v1(uuid) from public,anon;
grant execute on function public.pandora_meta_connection_v1(uuid) to authenticated;

comment on function public.pandora_meta_connection_v1(uuid) is
  'Owner/admin Meta connection projection. canUseNow requires active tenant membership, connected state, known future token expiry, all required scopes and recent successful verification.';
