-- Fail closed when the Meta marketing user-token expiry is unknown.
-- Page-token credentials keep the existing nullable-expiry semantics.

create or replace function public.pandora_meta_runtime_secret_v1(p_organization_id uuid,p_installation_id uuid,p_purpose text)
returns jsonb language plpgsql security definer
set search_path=pg_catalog,public,private,vault,pg_temp as $$
declare v_install public.connector_installations%rowtype; v_secret_id uuid; v_token text; v_purpose text:=lower(trim(coalesce(p_purpose,'')));
begin
 if session_user not in ('postgres','service_role','supabase_admin')
   and coalesce(nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'role','') <> 'service_role' then
   raise exception 'pandora_meta_runtime_service_role_required' using errcode='42501';
 end if;
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
   where c.organization_id=p_organization_id and c.status='connected'
     and c.token_expires_at is not null and c.token_expires_at>now() limit 1;
 end if;
 if v_secret_id is null then raise exception 'pandora_meta_runtime_credential_unavailable' using errcode='55000'; end if;
 select decrypted_secret into v_token from vault.decrypted_secrets where id=v_secret_id limit 1;
 if nullif(trim(coalesce(v_token,'')),'') is null then raise exception 'pandora_meta_runtime_credential_unavailable' using errcode='55000'; end if;
 return jsonb_build_object('token',v_token,'purpose',v_purpose);
end; $$;
revoke all on function public.pandora_meta_runtime_secret_v1(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.pandora_meta_runtime_secret_v1(uuid,uuid,text) to service_role;
comment on function public.pandora_meta_runtime_secret_v1(uuid,uuid,text) is 'Trusted runtime-only Meta credential resolver for exact organization/installation and page or marketing purpose. Marketing credentials require a known future expiry.';
