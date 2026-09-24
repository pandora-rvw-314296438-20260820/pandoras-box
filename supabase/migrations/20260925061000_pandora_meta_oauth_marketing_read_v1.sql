-- Pandora Meta OAuth + Marketing API read foundation v1
-- Owner/admin OAuth uses one-time state. User/Page tokens are stored only in Supabase Vault.

create table if not exists private.pandora_meta_oauth_states (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  state_hash text not null unique check (state_hash ~ '^[0-9a-f]{64}$'),
  redirect_uri text not null,
  required_scopes text[] not null,
  expires_at timestamptz not null,
  claimed_at timestamptz,
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  check (expires_at > created_at)
);
create table if not exists private.pandora_meta_connections (
  organization_id uuid primary key references public.organizations(id) on delete cascade,
  connected_by uuid not null references auth.users(id) on delete restrict,
  provider_user_id text not null,
  display_name text,
  user_token_secret_id uuid not null,
  scopes text[] not null,
  pages jsonb not null default '[]'::jsonb,
  ad_accounts jsonb not null default '[]'::jsonb,
  status text not null default 'connected' check (status in ('connected','problem','revoked')),
  token_expires_at timestamptz,
  last_verified_at timestamptz,
  last_http_status integer,
  last_error text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists private.pandora_meta_page_tokens (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  page_id text not null check (page_id ~ '^[0-9]+$'),
  page_name text,
  token_secret_id uuid not null,
  tasks text[] not null default '{}',
  updated_at timestamptz not null default now(),
  primary key (organization_id,page_id)
);
revoke all on private.pandora_meta_oauth_states from public,anon,authenticated;
revoke all on private.pandora_meta_connections from public,anon,authenticated;
revoke all on private.pandora_meta_page_tokens from public,anon,authenticated;

create or replace function private.pandora_meta_required_scopes_v1()
returns text[] language sql immutable set search_path=pg_catalog as $$
 select array['public_profile','pages_show_list','pages_read_engagement','ads_read','ads_management','business_management']::text[];
$$;
revoke all on function private.pandora_meta_required_scopes_v1() from public,anon,authenticated;
grant execute on function private.pandora_meta_required_scopes_v1() to service_role;

create or replace function public.pandora_meta_oauth_prepare_v1(p_organization_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,auth,extensions,pg_temp as $$
declare
 v_uid uuid:=auth.uid(); v_role text; v_app_id text; v_secret_ok boolean:=false;
 v_state text; v_state_hash text;
 v_redirect text:='https://jcyqixttuebxqqfkjonq.supabase.co/functions/v1/pandora-meta-oauth/callback';
 v_scopes text[]:=private.pandora_meta_required_scopes_v1(); v_expires timestamptz:=now()+interval '10 minutes';
begin
 if v_uid is null then raise exception 'pandora_meta_oauth_sign_in_required' using errcode='42501'; end if;
 select m.role into v_role from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
 if v_role not in ('owner','admin') then raise exception 'pandora_meta_oauth_owner_required' using errcode='42501'; end if;
 select decrypted_secret into v_app_id from vault.decrypted_secrets where name='pandora_meta_oauth_app_id' and nullif(trim(decrypted_secret),'') is not null limit 1;
 select exists(select 1 from vault.decrypted_secrets where name='pandora_meta_oauth_app_secret' and nullif(trim(decrypted_secret),'') is not null) into v_secret_ok;
 if nullif(trim(v_app_id),'') is null or not v_secret_ok then
   return jsonb_build_object('ok',false,'provider','meta','state','needs_authorization_configuration','reason','meta_oauth_not_configured','needsYou',true,'redirectUri',v_redirect);
 end if;
 delete from private.pandora_meta_oauth_states where organization_id=p_organization_id and user_id=v_uid and (expires_at<=now() or consumed_at is not null or claimed_at is not null);
 v_state:=rtrim(translate(encode(extensions.gen_random_bytes(32),'base64'),'+/','-_'),'=');
 v_state_hash:=encode(extensions.digest(convert_to(v_state,'UTF8'),'sha256'),'hex');
 insert into private.pandora_meta_oauth_states(organization_id,user_id,state_hash,redirect_uri,required_scopes,expires_at)
 values(p_organization_id,v_uid,v_state_hash,v_redirect,v_scopes,v_expires);
 return jsonb_build_object('ok',true,'provider','meta','state','authorization_required','redirectUri',v_redirect,'expiresAt',v_expires,'scopes',to_jsonb(v_scopes),
   'authorizationUrl','https://www.facebook.com/v26.0/dialog/oauth?client_id='||extensions.urlencode(v_app_id)||'&redirect_uri='||extensions.urlencode(v_redirect)||'&response_type=code&state='||extensions.urlencode(v_state)||'&scope='||extensions.urlencode(array_to_string(v_scopes,',')));
end; $$;
revoke all on function public.pandora_meta_oauth_prepare_v1(uuid) from public,anon;
grant execute on function public.pandora_meta_oauth_prepare_v1(uuid) to authenticated;

create or replace function public.pandora_meta_oauth_material_v1(p_state text)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,extensions,pg_temp as $$
declare v_hash text; v_row private.pandora_meta_oauth_states%rowtype; v_app_id text; v_app_secret text;
begin
 if current_user not in ('service_role','postgres','supabase_admin') then raise exception 'pandora_meta_oauth_service_role_required' using errcode='42501'; end if;
 if p_state is null or length(p_state)<32 or length(p_state)>256 then raise exception 'pandora_meta_oauth_state_invalid' using errcode='22023'; end if;
 v_hash:=encode(extensions.digest(convert_to(p_state,'UTF8'),'sha256'),'hex');
 update private.pandora_meta_oauth_states set claimed_at=now() where state_hash=v_hash and consumed_at is null and claimed_at is null and expires_at>now() returning * into v_row;
 if v_row.id is null then raise exception 'pandora_meta_oauth_state_invalid_or_replayed' using errcode='42501'; end if;
 select decrypted_secret into v_app_id from vault.decrypted_secrets where name='pandora_meta_oauth_app_id' and nullif(trim(decrypted_secret),'') is not null limit 1;
 select decrypted_secret into v_app_secret from vault.decrypted_secrets where name='pandora_meta_oauth_app_secret' and nullif(trim(decrypted_secret),'') is not null limit 1;
 if nullif(v_app_id,'') is null or nullif(v_app_secret,'') is null then raise exception 'pandora_meta_oauth_client_configuration_missing' using errcode='55000'; end if;
 return jsonb_build_object('organizationId',v_row.organization_id,'userId',v_row.user_id,'appId',v_app_id,'appSecret',v_app_secret,'redirectUri',v_row.redirect_uri,'requiredScopes',to_jsonb(v_row.required_scopes),'expiresAt',v_row.expires_at);
end; $$;
revoke all on function public.pandora_meta_oauth_material_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_meta_oauth_material_v1(text) to service_role;

create or replace function public.pandora_meta_oauth_commit_v1(
 p_state text,p_provider_user_id text,p_display_name text,p_user_token text,p_expires_in integer,
 p_granted_scopes text[],p_pages jsonb,p_ad_accounts jsonb
) returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,extensions,pg_temp as $$
declare
 v_hash text; v_row private.pandora_meta_oauth_states%rowtype; v_existing_user_secret uuid; v_user_secret uuid; v_user_secret_name text;
 v_page jsonb; v_page_id text; v_page_name text; v_page_token text; v_page_tasks text[]; v_page_secret uuid; v_existing_page_secret uuid; v_page_secret_name text;
 v_installation_id uuid; v_public_pages jsonb:='[]'::jsonb; v_required text[]:=private.pandora_meta_required_scopes_v1();
 v_expiry timestamptz; v_page_count integer:=0; v_ad_count integer:=0;
begin
 if current_user not in ('service_role','postgres','supabase_admin') then raise exception 'pandora_meta_oauth_service_role_required' using errcode='42501'; end if;
 if p_state is null or length(trim(coalesce(p_user_token,'')))<16 then raise exception 'pandora_meta_oauth_commit_invalid' using errcode='22023'; end if;
 if p_provider_user_id !~ '^[0-9]+$' then raise exception 'pandora_meta_oauth_provider_identity_invalid' using errcode='22023'; end if;
 if not (v_required <@ coalesce(p_granted_scopes,array[]::text[])) then raise exception 'pandora_meta_oauth_required_scopes_missing' using errcode='42501'; end if;
 if jsonb_typeof(coalesce(p_pages,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_pages,'[]'::jsonb))>100
    or jsonb_typeof(coalesce(p_ad_accounts,'[]'::jsonb))<>'array' or jsonb_array_length(coalesce(p_ad_accounts,'[]'::jsonb))>100 then
   raise exception 'pandora_meta_oauth_assets_invalid' using errcode='22023';
 end if;
 v_hash:=encode(extensions.digest(convert_to(p_state,'UTF8'),'sha256'),'hex');
 select * into v_row from private.pandora_meta_oauth_states where state_hash=v_hash and consumed_at is null and claimed_at is not null and expires_at>now() for update;
 if v_row.id is null then raise exception 'pandora_meta_oauth_state_invalid_or_expired' using errcode='42501'; end if;
 select user_token_secret_id into v_existing_user_secret from private.pandora_meta_connections where organization_id=v_row.organization_id;
 v_user_secret_name:='pandora_meta_user_'||replace(v_row.organization_id::text,'-','');
 if v_existing_user_secret is null then v_user_secret:=vault.create_secret(p_user_token,v_user_secret_name,'Pandora Meta long-lived user access token');
 else perform vault.update_secret(v_existing_user_secret,p_user_token,v_user_secret_name,'Pandora Meta long-lived user access token'); v_user_secret:=v_existing_user_secret; end if;
 if coalesce(p_expires_in,0)>0 then v_expiry:=now()+make_interval(secs=>p_expires_in); end if;

 for v_page in select value from jsonb_array_elements(coalesce(p_pages,'[]'::jsonb)) loop
   v_page_id:=trim(coalesce(v_page->>'id','')); v_page_name:=nullif(trim(coalesce(v_page->>'name','')),''); v_page_token:=trim(coalesce(v_page->>'access_token',''));
   if v_page_id !~ '^[0-9]+$' or length(v_page_token)<16 then raise exception 'pandora_meta_oauth_page_material_invalid' using errcode='22023'; end if;
   select coalesce(array_agg(value),array[]::text[]) into v_page_tasks from jsonb_array_elements_text(coalesce(v_page->'tasks','[]'::jsonb));
   select token_secret_id into v_existing_page_secret from private.pandora_meta_page_tokens where organization_id=v_row.organization_id and page_id=v_page_id;
   v_page_secret_name:='pandora_meta_page_'||replace(v_row.organization_id::text,'-','')||'_'||v_page_id;
   if v_existing_page_secret is null then v_page_secret:=vault.create_secret(v_page_token,v_page_secret_name,'Pandora Meta Page access token');
   else perform vault.update_secret(v_existing_page_secret,v_page_token,v_page_secret_name,'Pandora Meta Page access token'); v_page_secret:=v_existing_page_secret; end if;
   insert into private.pandora_meta_page_tokens(organization_id,page_id,page_name,token_secret_id,tasks,updated_at)
   values(v_row.organization_id,v_page_id,v_page_name,v_page_secret,coalesce(v_page_tasks,array[]::text[]),now())
   on conflict(organization_id,page_id) do update set page_name=excluded.page_name,token_secret_id=excluded.token_secret_id,tasks=excluded.tasks,updated_at=now();

   insert into public.connector_installations(organization_id,provider,external_account_id,display_name,status,scopes,configuration,installed_by,last_health_check_at)
   values(v_row.organization_id,'meta',v_page_id,coalesce(v_page_name,'Meta Page'),'active'::public.connector_status,p_granted_scopes,
     jsonb_build_object('provider_user_id',p_provider_user_id,'page_name',v_page_name,'page_tasks',to_jsonb(coalesce(v_page_tasks,array[]::text[])),'oauth_version','meta-oauth-v1','page_access_verified',true,'provider_network_enabled',true,'marketing_read_enabled',true),
     v_row.user_id,now())
   on conflict(organization_id,provider,external_account_id) do update set display_name=excluded.display_name,status='active'::public.connector_status,scopes=excluded.scopes,configuration=excluded.configuration,installed_by=excluded.installed_by,last_health_check_at=now(),updated_at=now()
   returning id into v_installation_id;

   insert into public.credential_refs(organization_id,installation_id,secret_ref,key_version,expires_at,rotation_state)
   values(v_row.organization_id,v_installation_id,'vault://'||v_page_secret::text,1,v_expiry,'current'::public.rotation_status)
   on conflict(installation_id) do update set secret_ref=excluded.secret_ref,key_version=public.credential_refs.key_version+1,expires_at=excluded.expires_at,rotation_state='current'::public.rotation_status,updated_at=now();
   v_public_pages:=v_public_pages||jsonb_build_array(v_page-'access_token'); v_page_count:=v_page_count+1; v_page_token:=null;
 end loop;

 v_ad_count:=jsonb_array_length(coalesce(p_ad_accounts,'[]'::jsonb));
 insert into private.pandora_meta_connections(organization_id,connected_by,provider_user_id,display_name,user_token_secret_id,scopes,pages,ad_accounts,status,token_expires_at,last_verified_at,last_http_status,last_error,updated_at)
 values(v_row.organization_id,v_row.user_id,p_provider_user_id,nullif(trim(coalesce(p_display_name,'')),''),v_user_secret,p_granted_scopes,v_public_pages,coalesce(p_ad_accounts,'[]'::jsonb),'connected',v_expiry,now(),200,null,now())
 on conflict(organization_id) do update set connected_by=excluded.connected_by,provider_user_id=excluded.provider_user_id,display_name=excluded.display_name,user_token_secret_id=excluded.user_token_secret_id,scopes=excluded.scopes,pages=excluded.pages,ad_accounts=excluded.ad_accounts,status='connected',token_expires_at=excluded.token_expires_at,last_verified_at=now(),last_http_status=200,last_error=null,updated_at=now();
 update private.pandora_meta_oauth_states set consumed_at=now() where id=v_row.id;
 return jsonb_build_object('ok',true,'provider','meta','organizationId',v_row.organization_id,'providerUserId',p_provider_user_id,'pageCount',v_page_count,'adAccountCount',v_ad_count,'scopes',to_jsonb(p_granted_scopes),'verifiedAt',now());
end; $$;
revoke all on function public.pandora_meta_oauth_commit_v1(text,text,text,text,integer,text[],jsonb,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_meta_oauth_commit_v1(text,text,text,text,integer,text[],jsonb,jsonb) to service_role;

create or replace function public.pandora_meta_connection_v1(p_organization_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,auth,pg_temp as $$
declare v_uid uuid:=auth.uid(); v_role text; v_row private.pandora_meta_connections%rowtype; v_installations jsonb:='[]'::jsonb;
begin
 if v_uid is null then raise exception 'pandora_meta_connection_sign_in_required' using errcode='42501'; end if;
 select m.role into v_role from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
 if v_role not in ('owner','admin') then raise exception 'pandora_meta_connection_owner_required' using errcode='42501'; end if;
 select * into v_row from private.pandora_meta_connections where organization_id=p_organization_id;
 if v_row.organization_id is null then return jsonb_build_object('ok',true,'provider','meta','connected',false,'state','Needs authorization','canUseNow',false); end if;
 select coalesce(jsonb_agg(jsonb_build_object('installationId',c.id,'pageId',c.external_account_id,'pageName',c.display_name,'status',c.status,'lastVerifiedAt',c.last_health_check_at) order by c.display_name),'[]'::jsonb)
 into v_installations from public.connector_installations c where c.organization_id=p_organization_id and c.provider='meta';
 return jsonb_build_object('ok',true,'provider','meta','connected',v_row.status='connected','state',case when v_row.status='connected' then 'Connected' else 'Problem' end,'canUseNow',v_row.status='connected',
   'account',jsonb_build_object('id',v_row.provider_user_id,'label',coalesce(v_row.display_name,'Meta account'),'verified',true),
   'scopes',to_jsonb(v_row.scopes),'scopesVerified',private.pandora_meta_required_scopes_v1()<@v_row.scopes,'pages',v_row.pages,'adAccounts',v_row.ad_accounts,'installations',v_installations,'tokenExpiresAt',v_row.token_expires_at,'lastVerifiedAt',v_row.last_verified_at,'rawStatus',v_row.status);
end; $$;
revoke all on function public.pandora_meta_connection_v1(uuid) from public,anon;
grant execute on function public.pandora_meta_connection_v1(uuid) to authenticated;

create or replace function public.pandora_meta_runtime_secret_v1(p_organization_id uuid,p_installation_id uuid,p_purpose text)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,pg_temp as $$
declare v_install public.connector_installations%rowtype; v_secret_id uuid; v_token text; v_purpose text:=lower(trim(coalesce(p_purpose,'')));
begin
 if current_user not in ('service_role','postgres','supabase_admin') then raise exception 'pandora_meta_runtime_service_role_required' using errcode='42501'; end if;
 if v_purpose not in ('page','marketing') then raise exception 'pandora_meta_runtime_purpose_invalid' using errcode='22023'; end if;
 select * into v_install from public.connector_installations where id=p_installation_id and organization_id=p_organization_id and provider='meta' and status='active' limit 1;
 if v_install.id is null then raise exception 'pandora_meta_runtime_installation_unavailable' using errcode='42501'; end if;
 if v_purpose='page' then
   select substring(cr.secret_ref from 9)::uuid into v_secret_id from public.credential_refs cr
   where cr.organization_id=p_organization_id and cr.installation_id=p_installation_id and cr.rotation_state='current'
     and cr.secret_ref ~ '^vault://[0-9a-fA-F-]{36}$' and (cr.expires_at is null or cr.expires_at>now())
   order by cr.key_version desc limit 1;
 else
   select c.user_token_secret_id into v_secret_id from private.pandora_meta_connections c
   where c.organization_id=p_organization_id and c.status='connected' and (c.token_expires_at is null or c.token_expires_at>now()) limit 1;
 end if;
 if v_secret_id is null then raise exception 'pandora_meta_runtime_credential_unavailable' using errcode='55000'; end if;
 select decrypted_secret into v_token from vault.decrypted_secrets where id=v_secret_id limit 1;
 if nullif(trim(coalesce(v_token,'')),'') is null then raise exception 'pandora_meta_runtime_credential_unavailable' using errcode='55000'; end if;
 return jsonb_build_object('token',v_token,'purpose',v_purpose);
end; $$;
revoke all on function public.pandora_meta_runtime_secret_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_meta_runtime_secret_v1(uuid,uuid,text) to service_role;

comment on function public.pandora_meta_oauth_prepare_v1(uuid) is 'Creates one-time owner/admin Meta OAuth state. App credentials remain in Supabase Vault.';
comment on function public.pandora_meta_oauth_commit_v1(text,text,text,text,integer,text[],jsonb,jsonb) is 'Service-role-only Meta OAuth commit. User/Page access tokens are written only to Supabase Vault.';
comment on function public.pandora_meta_runtime_secret_v1(uuid,uuid,text) is 'Trusted runtime-only Meta credential resolver for exact organization/installation and page or marketing purpose.';
