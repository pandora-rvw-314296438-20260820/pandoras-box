-- Pandora Meta OAuth Vercel callback v1
-- Supabase project is at its Edge Function count limit, so the public OAuth
-- callback is hosted by the existing mcpmaster Vercel runtime. App/user/Page
-- secrets remain server-side and all provider tokens are committed into Vault.

create or replace function public.pandora_meta_oauth_prepare_v1(p_organization_id uuid)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,auth,extensions,pg_temp as $$
declare
 v_uid uuid:=auth.uid(); v_role text; v_app_id text; v_secret_ok boolean:=false;
 v_state text; v_state_hash text;
 v_redirect text:='https://mcpmaster.vercel.app/oauth/meta/callback';
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
comment on function public.pandora_meta_oauth_prepare_v1(uuid) is
  'Creates one-time owner/admin Meta OAuth state using the mcpmaster Vercel callback. App credentials remain in Supabase Vault.';
