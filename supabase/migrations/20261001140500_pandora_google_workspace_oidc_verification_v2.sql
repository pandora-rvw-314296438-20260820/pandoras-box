-- Google Workspace OAuth/OIDC verification hardening v2.
-- This forward migration preserves Lane A authority while invalidating in-flight
-- requests created before exact least-privilege and nonce readback enforcement.

delete from private.pandora_google_workspace_oauth_states
where consumed_at is null;

create or replace function public.pandora_google_workspace_oauth_prepare_v1(p_organization_id uuid)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','vault','auth','extensions','pg_temp' as $$
declare
  v_uid uuid:=auth.uid(); v_client_id text; v_secret_ok boolean;
  v_state text; v_nonce text; v_verifier text; v_challenge text; v_state_hash text;
  v_redirect text:='https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-google-workspace-oauth/callback';
  v_scopes text[]:=private.pandora_google_workspace_required_scopes_v1();
  v_expires timestamptz:=clock_timestamp()+interval '10 minutes';
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_google_oauth_owner_required' using errcode='42501';
  end if;
  select decrypted_secret into v_client_id from vault.decrypted_secrets
    where name='pandora_google_workspace_oauth_client_id'
      and nullif(trim(decrypted_secret),'') is not null limit 1;
  select exists(
    select 1 from vault.decrypted_secrets
    where name='pandora_google_workspace_oauth_client_secret'
      and nullif(trim(decrypted_secret),'') is not null
  ) into v_secret_ok;
  if nullif(trim(v_client_id),'') is null or not v_secret_ok then
    return jsonb_build_object(
      'ok',false,'provider','google_workspace','state','needs_authorization_configuration',
      'reason','google_workspace_oauth_not_configured','needsYou',true,'redirectUri',v_redirect
    );
  end if;
  delete from private.pandora_google_workspace_oauth_states
  where organization_id=p_organization_id and user_id=v_uid
    and (expires_at<=clock_timestamp() or consumed_at is not null);
  v_state:=rtrim(translate(encode(extensions.gen_random_bytes(32),'base64'),'+/','-_'),'=');
  v_nonce:=rtrim(translate(encode(extensions.gen_random_bytes(32),'base64'),'+/','-_'),'=');
  v_verifier:=rtrim(translate(encode(extensions.gen_random_bytes(64),'base64'),'+/','-_'),'=');
  v_state_hash:=encode(extensions.digest(convert_to(v_state,'UTF8'),'sha256'),'hex');
  v_challenge:=rtrim(translate(encode(
    extensions.digest(convert_to(v_verifier,'UTF8'),'sha256'),'base64'
  ),'+/','-_'),'=');
  insert into private.pandora_google_workspace_oauth_states(
    organization_id,user_id,state_hash,nonce_hash,code_verifier,redirect_uri,required_scopes,expires_at
  ) values(
    p_organization_id,v_uid,v_state_hash,
    encode(extensions.digest(convert_to(v_nonce,'UTF8'),'sha256'),'hex'),
    v_verifier,v_redirect,v_scopes,v_expires
  );
  return jsonb_build_object(
    'ok',true,'provider','google_workspace','state','authorization_required',
    'redirectUri',v_redirect,'expiresAt',v_expires,'scopes',to_jsonb(v_scopes),
    'authorizationUrl','https://accounts.google.com/o/oauth2/v2/auth?'||extensions.urlencode(jsonb_build_object(
      'client_id',v_client_id,'redirect_uri',v_redirect,'response_type','code',
      'scope',array_to_string(v_scopes,' '),'access_type','offline','prompt','consent',
      'include_granted_scopes','false','state',v_state,'nonce',v_nonce,
      'code_challenge',v_challenge,'code_challenge_method','S256'
    ))
  );
end; $$;

create or replace function public.pandora_google_workspace_oauth_material_v1(p_state text)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','vault','extensions','pg_temp' as $$
declare
  v_hash text; v_row private.pandora_google_workspace_oauth_states%rowtype;
  v_client_id text; v_client_secret text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then
    raise exception 'pandora_google_oauth_service_role_required' using errcode='42501';
  end if;
  if p_state is null or length(p_state)<32 or length(p_state)>256 then
    raise exception 'pandora_google_oauth_state_invalid' using errcode='22023';
  end if;
  v_hash:=encode(extensions.digest(convert_to(p_state,'UTF8'),'sha256'),'hex');
  update private.pandora_google_workspace_oauth_states set claimed_at=clock_timestamp()
  where state_hash=v_hash and nonce_hash is not null and consumed_at is null
    and claimed_at is null and expires_at>clock_timestamp()
  returning * into v_row;
  if v_row.id is null then
    raise exception 'pandora_google_oauth_state_invalid_or_replayed' using errcode='42501';
  end if;
  select decrypted_secret into v_client_id from vault.decrypted_secrets
    where name='pandora_google_workspace_oauth_client_id'
      and nullif(trim(decrypted_secret),'') is not null limit 1;
  select decrypted_secret into v_client_secret from vault.decrypted_secrets
    where name='pandora_google_workspace_oauth_client_secret'
      and nullif(trim(decrypted_secret),'') is not null limit 1;
  if nullif(v_client_id,'') is null or nullif(v_client_secret,'') is null then
    raise exception 'pandora_google_oauth_client_configuration_missing' using errcode='55000';
  end if;
  return jsonb_build_object(
    'organizationId',v_row.organization_id,'userId',v_row.user_id,
    'clientId',v_client_id,'clientSecret',v_client_secret,
    'codeVerifier',v_row.code_verifier,'nonceHash',v_row.nonce_hash,
    'redirectUri',v_row.redirect_uri,'requiredScopes',to_jsonb(v_row.required_scopes),
    'expiresAt',v_row.expires_at
  );
end; $$;

-- A Google row can only be Connected with the exact read-first scope set.
update private.pandora_connection_accounts_v1
set status='needs_attention',health_state='unhealthy',
    failure_code='GOOGLE_SCOPE_OVERPRIVILEGED',updated_at=clock_timestamp()
where provider_key='google_workspace' and status='connected' and not (
  cardinality(granted_scopes)=5
  and array_position(granted_scopes,null) is null
  and
  array[
    'openid','email','profile',
    'https://www.googleapis.com/auth/drive.metadata.readonly',
    'https://www.googleapis.com/auth/spreadsheets.readonly'
  ]::text[] <@ granted_scopes
  and granted_scopes <@ array[
    'openid','email','profile',
    'https://www.googleapis.com/auth/drive.metadata.readonly',
    'https://www.googleapis.com/auth/spreadsheets.readonly'
  ]::text[]
);

update private.pandora_google_workspace_connections
set status='problem',last_error='GOOGLE_SCOPE_OVERPRIVILEGED',updated_at=clock_timestamp()
where status='connected' and not (
  cardinality(scopes)=5 and array_position(scopes,null) is null
  and private.pandora_google_workspace_required_scopes_v1() <@ scopes
  and scopes <@ private.pandora_google_workspace_required_scopes_v1()
);

alter table private.pandora_connection_accounts_v1
  drop constraint if exists pandora_google_connected_exact_read_scopes_v2;
alter table private.pandora_connection_accounts_v1
  add constraint pandora_google_connected_exact_read_scopes_v2 check (
    provider_key<>'google_workspace' or status<>'connected' or (
      cardinality(granted_scopes)=5
      and array_position(granted_scopes,null) is null
      and
      array[
        'openid','email','profile',
        'https://www.googleapis.com/auth/drive.metadata.readonly',
        'https://www.googleapis.com/auth/spreadsheets.readonly'
      ]::text[] <@ granted_scopes
      and granted_scopes <@ array[
        'openid','email','profile',
        'https://www.googleapis.com/auth/drive.metadata.readonly',
        'https://www.googleapis.com/auth/spreadsheets.readonly'
      ]::text[]
    )
  ) not valid;
alter table private.pandora_connection_accounts_v1
  validate constraint pandora_google_connected_exact_read_scopes_v2;

create or replace function public.pandora_google_workspace_connection_v1(p_organization_id uuid)
returns jsonb language plpgsql stable security definer
set search_path='pg_catalog','public','private','auth','pg_temp' as $$
declare
  v_uid uuid:=auth.uid();
  v_row private.pandora_google_workspace_connections%rowtype;
  v_fresh boolean; v_scopes_exact boolean;
begin
  if v_uid is null or not private.pandora_is_active_org_admin_v1(p_organization_id) then
    raise exception 'pandora_google_connection_owner_required' using errcode='42501';
  end if;
  select * into v_row from private.pandora_google_workspace_connections
  where organization_id=p_organization_id and user_id=v_uid;
  if v_row.organization_id is null then
    return jsonb_build_object(
      'ok',true,'provider','google_workspace','connected',false,
      'state','Needs authorization','canUseNow',false
    );
  end if;
  v_scopes_exact:=cardinality(v_row.scopes)=5 and array_position(v_row.scopes,null) is null
    and private.pandora_google_workspace_required_scopes_v1()<@v_row.scopes
    and v_row.scopes<@private.pandora_google_workspace_required_scopes_v1();
  v_fresh:=v_row.status='connected'
    and v_row.last_verified_at>=clock_timestamp()-interval '15 minutes'
    and v_scopes_exact;
  return jsonb_build_object(
    'ok',true,'provider','google_workspace','connected',v_fresh,
    'state',case when v_fresh then 'Connected' else 'Needs attention' end,
    'canUseNow',v_fresh,
    'account',jsonb_build_object('label',v_row.account_email,'verified',v_fresh),
    'scopes',to_jsonb(v_row.scopes),'scopesVerified',v_scopes_exact,
    'lastVerifiedAt',v_row.last_verified_at,'rawStatus',v_row.status,
    'recovery',case when v_fresh then null else
      jsonb_build_object('action','reconnect','reason','health_or_scopes_stale') end
  );
end; $$;

revoke execute on function public.pandora_google_workspace_oauth_prepare_v1(uuid) from public,anon;
revoke execute on function public.pandora_google_workspace_oauth_material_v1(text) from public,anon,authenticated;
revoke execute on function public.pandora_google_workspace_connection_v1(uuid) from public,anon;

comment on constraint pandora_google_connected_exact_read_scopes_v2
  on private.pandora_connection_accounts_v1 is
  'Google Workspace may project Connected only with the exact approved read-first scope set.';
