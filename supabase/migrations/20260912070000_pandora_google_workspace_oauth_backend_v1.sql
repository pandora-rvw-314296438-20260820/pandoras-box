-- Pandora Google Workspace OAuth backend v1
-- Owner/admin authorization is PKCE + one-time state. Refresh tokens live only in Supabase Vault.

create table if not exists private.pandora_google_workspace_oauth_states (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  state_hash text not null unique check (state_hash ~ '^[0-9a-f]{64}$'),
  code_verifier text not null check (length(code_verifier) between 43 and 128),
  redirect_uri text not null,
  required_scopes text[] not null,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create table if not exists private.pandora_google_workspace_connections (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  refresh_token_secret_id uuid not null,
  provider_subject text not null,
  account_email text not null,
  display_name text,
  scopes text[] not null,
  status text not null default 'connected' check (status in ('connected','problem','revoked')),
  last_verified_at timestamptz,
  last_http_status integer,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (organization_id,user_id)
);

revoke all on private.pandora_google_workspace_oauth_states from public,anon,authenticated;
revoke all on private.pandora_google_workspace_connections from public,anon,authenticated;

create or replace function private.pandora_google_workspace_required_scopes_v1()
returns text[] language sql immutable set search_path=pg_catalog as $$
  select array['openid','email','profile','https://www.googleapis.com/auth/drive','https://www.googleapis.com/auth/spreadsheets']::text[];
$$;
revoke all on function private.pandora_google_workspace_required_scopes_v1() from public,anon,authenticated;
grant execute on function private.pandora_google_workspace_required_scopes_v1() to service_role;

create or replace function public.pandora_google_workspace_oauth_prepare_v1(p_organization_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,auth,extensions,pg_temp as $$
declare
  v_uid uuid:=auth.uid(); v_role text; v_client_id text; v_secret_ok boolean;
  v_state text; v_verifier text; v_challenge text; v_state_hash text;
  v_redirect text:='https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-google-workspace-oauth/callback';
  v_scopes text[]:=private.pandora_google_workspace_required_scopes_v1();
  v_expires timestamptz:=now()+interval '10 minutes';
begin
  if v_uid is null then raise exception 'pandora_google_oauth_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_google_oauth_owner_required' using errcode='42501'; end if;
  select decrypted_secret into v_client_id from vault.decrypted_secrets where name='pandora_google_workspace_oauth_client_id' and nullif(trim(decrypted_secret),'') is not null limit 1;
  select exists(select 1 from vault.decrypted_secrets where name='pandora_google_workspace_oauth_client_secret' and nullif(trim(decrypted_secret),'') is not null) into v_secret_ok;
  if nullif(trim(v_client_id),'') is null or not v_secret_ok then
    return jsonb_build_object('ok',false,'provider','google_workspace','state','needs_authorization_configuration','reason','google_workspace_oauth_not_configured','needsYou',true,'redirectUri',v_redirect);
  end if;
  delete from private.pandora_google_workspace_oauth_states where organization_id=p_organization_id and user_id=v_uid and (expires_at<=now() or consumed_at is not null);
  v_state:=rtrim(translate(encode(extensions.gen_random_bytes(32),'base64'),'+/','-_'),'=');
  v_verifier:=rtrim(translate(encode(extensions.gen_random_bytes(64),'base64'),'+/','-_'),'=');
  v_state_hash:=encode(extensions.digest(convert_to(v_state,'UTF8'),'sha256'),'hex');
  v_challenge:=rtrim(translate(encode(extensions.digest(convert_to(v_verifier,'UTF8'),'sha256'),'base64'),'+/','-_'),'=');
  insert into private.pandora_google_workspace_oauth_states(organization_id,user_id,state_hash,code_verifier,redirect_uri,required_scopes,expires_at)
  values(p_organization_id,v_uid,v_state_hash,v_verifier,v_redirect,v_scopes,v_expires);
  return jsonb_build_object(
    'ok',true,'provider','google_workspace','state','authorization_required','redirectUri',v_redirect,'expiresAt',v_expires,'scopes',to_jsonb(v_scopes),
    'authorizationUrl','https://accounts.google.com/o/oauth2/v2/auth?'||extensions.urlencode(jsonb_build_object(
      'client_id',v_client_id,'redirect_uri',v_redirect,'response_type','code','scope',array_to_string(v_scopes,' '),'access_type','offline','prompt','consent',
      'include_granted_scopes','true','state',v_state,'code_challenge',v_challenge,'code_challenge_method','S256'))
  );
end; $$;
revoke all on function public.pandora_google_workspace_oauth_prepare_v1(uuid) from public,anon;
grant execute on function public.pandora_google_workspace_oauth_prepare_v1(uuid) to authenticated;

create or replace function public.pandora_google_workspace_oauth_material_v1(p_state text)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,extensions,pg_temp as $$
declare
  v_hash text; v_row private.pandora_google_workspace_oauth_states%rowtype; v_client_id text; v_client_secret text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then raise exception 'pandora_google_oauth_service_role_required' using errcode='42501'; end if;
  if p_state is null or length(p_state)<32 or length(p_state)>256 then raise exception 'pandora_google_oauth_state_invalid' using errcode='22023'; end if;
  v_hash:=encode(extensions.digest(convert_to(p_state,'UTF8'),'sha256'),'hex');
  update private.pandora_google_workspace_oauth_states set claimed_at=now()
  where state_hash=v_hash and consumed_at is null and claimed_at is null and expires_at>now() returning * into v_row;
  if v_row.id is null then raise exception 'pandora_google_oauth_state_invalid_or_replayed' using errcode='42501'; end if;
  select decrypted_secret into v_client_id from vault.decrypted_secrets where name='pandora_google_workspace_oauth_client_id' and nullif(trim(decrypted_secret),'') is not null limit 1;
  select decrypted_secret into v_client_secret from vault.decrypted_secrets where name='pandora_google_workspace_oauth_client_secret' and nullif(trim(decrypted_secret),'') is not null limit 1;
  if nullif(v_client_id,'') is null or nullif(v_client_secret,'') is null then raise exception 'pandora_google_oauth_client_configuration_missing' using errcode='55000'; end if;
  return jsonb_build_object('organizationId',v_row.organization_id,'userId',v_row.user_id,'clientId',v_client_id,'clientSecret',v_client_secret,'codeVerifier',v_row.code_verifier,'redirectUri',v_row.redirect_uri,'requiredScopes',to_jsonb(v_row.required_scopes),'expiresAt',v_row.expires_at);
end; $$;
revoke all on function public.pandora_google_workspace_oauth_material_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_google_workspace_oauth_material_v1(text) to service_role;

create or replace function public.pandora_google_workspace_oauth_commit_v1(
  p_state text,p_provider_subject text,p_account_email text,p_display_name text,p_refresh_token text,p_granted_scopes text[])
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,extensions,pg_temp as $$
declare
  v_hash text; v_row private.pandora_google_workspace_oauth_states%rowtype; v_existing uuid; v_secret_id uuid; v_name text;
begin
  if current_user not in ('service_role','postgres','supabase_admin') then raise exception 'pandora_google_oauth_service_role_required' using errcode='42501'; end if;
  if p_state is null or length(trim(coalesce(p_refresh_token,'')))<16 then raise exception 'pandora_google_oauth_commit_invalid' using errcode='22023'; end if;
  v_hash:=encode(extensions.digest(convert_to(p_state,'UTF8'),'sha256'),'hex');
  select * into v_row from private.pandora_google_workspace_oauth_states where state_hash=v_hash and consumed_at is null and claimed_at is not null and expires_at>now() for update;
  if v_row.id is null then raise exception 'pandora_google_oauth_state_invalid_or_expired' using errcode='42501'; end if;
  if not (v_row.required_scopes <@ coalesce(p_granted_scopes,array[]::text[])) then raise exception 'pandora_google_oauth_required_scopes_missing' using errcode='42501'; end if;
  select refresh_token_secret_id into v_existing from private.pandora_google_workspace_connections where organization_id=v_row.organization_id and user_id=v_row.user_id;
  v_name:='pandora_google_workspace_refresh_'||replace(v_row.organization_id::text,'-','')||'_'||replace(v_row.user_id::text,'-','');
  if v_existing is null then v_secret_id:=vault.create_secret(p_refresh_token,v_name,'Pandora Google Workspace owner refresh token');
  else perform vault.update_secret(v_existing,p_refresh_token,v_name,'Pandora Google Workspace owner refresh token'); v_secret_id:=v_existing; end if;
  insert into private.pandora_google_workspace_connections(organization_id,user_id,refresh_token_secret_id,provider_subject,account_email,display_name,scopes,status,last_verified_at,last_http_status,last_error,updated_at)
  values(v_row.organization_id,v_row.user_id,v_secret_id,trim(p_provider_subject),lower(trim(p_account_email)),nullif(trim(p_display_name),''),p_granted_scopes,'connected',now(),200,null,now())
  on conflict(organization_id,user_id) do update set refresh_token_secret_id=excluded.refresh_token_secret_id,provider_subject=excluded.provider_subject,account_email=excluded.account_email,display_name=excluded.display_name,scopes=excluded.scopes,status='connected',last_verified_at=now(),last_http_status=200,last_error=null,updated_at=now();
  update private.pandora_google_workspace_oauth_states set consumed_at=now() where id=v_row.id;
  return jsonb_build_object('ok',true,'provider','google_workspace','organizationId',v_row.organization_id,'userId',v_row.user_id,'accountEmail',lower(trim(p_account_email)),'scopes',to_jsonb(p_granted_scopes),'verifiedAt',now());
end; $$;
revoke all on function public.pandora_google_workspace_oauth_commit_v1(text,text,text,text,text,text[]) from public,anon,authenticated;
grant execute on function public.pandora_google_workspace_oauth_commit_v1(text,text,text,text,text,text[]) to service_role;

create or replace function public.pandora_google_workspace_connection_v1(p_organization_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,auth,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_role text; v_row private.pandora_google_workspace_connections%rowtype;
begin
  if v_uid is null then raise exception 'pandora_google_connection_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_google_connection_owner_required' using errcode='42501'; end if;
  select * into v_row from private.pandora_google_workspace_connections where organization_id=p_organization_id and user_id=v_uid;
  if v_row.organization_id is null then return jsonb_build_object('ok',true,'provider','google_workspace','connected',false,'state','Needs authorization','canUseNow',false); end if;
  return jsonb_build_object('ok',true,'provider','google_workspace','connected',v_row.status='connected','state',case when v_row.status='connected' then 'Connected' else 'Problem' end,'canUseNow',v_row.status='connected','account',jsonb_build_object('label',v_row.account_email,'verified',true),'scopes',to_jsonb(v_row.scopes),'scopesVerified',private.pandora_google_workspace_required_scopes_v1()<@v_row.scopes,'lastVerifiedAt',v_row.last_verified_at,'rawStatus',v_row.status);
end; $$;
revoke all on function public.pandora_google_workspace_connection_v1(uuid) from public,anon;
grant execute on function public.pandora_google_workspace_connection_v1(uuid) to authenticated;

comment on function public.pandora_google_workspace_oauth_prepare_v1(uuid) is 'Creates one-time PKCE state for owner-scoped Google Workspace OAuth without exposing token material.';
comment on function public.pandora_google_workspace_oauth_material_v1(text) is 'Service-role-only callback material for the one-time Google OAuth exchange.';
comment on function public.pandora_google_workspace_oauth_commit_v1(text,text,text,text,text,text[]) is 'Stores Google Workspace refresh token only in Supabase Vault after identity/scope verification.';
comment on function public.pandora_google_workspace_connection_v1(uuid) is 'Authenticated owner/admin projection of Google Workspace authorization state without token material.';