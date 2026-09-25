-- Disposable PostgreSQL fixture. Never run against an application database.
\set ON_ERROR_STOP on
CREATE SCHEMA auth;
CREATE SCHEMA private;
CREATE SCHEMA extensions;
CREATE EXTENSION pgcrypto WITH SCHEMA extensions;
CREATE ROLE authenticated;
CREATE ROLE anon;
CREATE ROLE service_role;
CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
 SELECT (nullif(current_setting('request.jwt.claims',true),'')::jsonb->>'sub')::uuid
$$;
CREATE TABLE public.organizations(id uuid PRIMARY KEY,slug text,status text);
CREATE TABLE public.memberships(organization_id uuid,user_id uuid,role text,status text);
CREATE TABLE public.pandora_projects(id uuid,organization_id uuid,project_key text,repository text,status text);
CREATE TABLE public.pandora_runtime_provider_configs(provider text,config_key text,config_value text,active boolean);
CREATE TABLE private.audit_provider_calls(method text,path text);
CREATE FUNCTION private.pandora_integration_github_api_20260825(text,text,jsonb) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO private.audit_provider_calls VALUES($1,$2);
 RETURN jsonb_build_object('status',200,'body',jsonb_build_object('fixture',true));
END; $$;
INSERT INTO public.organizations VALUES
 ('10000000-0000-4000-8000-000000000001','mcpmaster-test','active'),
 ('10000000-0000-4000-8000-000000000002','plp-boracay','active'),
 ('10000000-0000-4000-8000-000000000003','other-tenant-test','active');
INSERT INTO public.pandora_projects VALUES
 ('30000000-0000-4000-8000-000000000001','10000000-0000-4000-8000-000000000001','mcpmaster','pandora-rvw-314296438-20260820/pandoras-box','active');
INSERT INTO public.memberships VALUES
 ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000001','owner','active'),
 ('10000000-0000-4000-8000-000000000002','20000000-0000-4000-8000-000000000002','owner','active'),
 ('10000000-0000-4000-8000-000000000003','20000000-0000-4000-8000-000000000003','owner','active'),
 ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000004','admin','revoked'),
 ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000005','staff','active'),
 ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000006','admin','invited'),
 ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000007','admin','suspended'),
 ('10000000-0000-4000-8000-000000000001','20000000-0000-4000-8000-000000000008','admin','active');
CREATE OR REPLACE FUNCTION public.pandora_enterprise_direct_github_v1(p_organization_id uuid, p_method text, p_path text, p_body jsonb DEFAULT NULL::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public', 'private', 'auth'
AS $function$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_method text := upper(trim(coalesce(p_method,'')));
  v_path text := trim(coalesce(p_path,''));
  v_prefix constant text := '/repos/pandora-rvw-314296438-20260820/plp';
  v_body_text text := coalesce(p_body::text,'');
begin
  if v_uid is null then raise exception 'pandora_direct_github_sign_in_required' using errcode='42501'; end if;
  select role into v_role from public.memberships
   where organization_id=p_organization_id and user_id=v_uid and status='active' limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_direct_github_owner_required' using errcode='42501'; end if;
  if v_method not in ('GET','POST','PATCH') then raise exception 'pandora_direct_github_method_not_allowed' using errcode='22023'; end if;
  if v_path like '%..%' or v_path not like v_prefix || '%' then raise exception 'pandora_direct_github_path_not_allowed' using errcode='22023'; end if;

  if v_method='GET' then
    if not (
      v_path = v_prefix or
      v_path = v_prefix || '/git/ref/heads/main' or
      v_path ~ ('^' || v_prefix || '/git/commits/[0-9a-f]{40}$') or
      v_path ~ ('^' || v_prefix || '/git/trees/[0-9a-f]{40}(\?recursive=1)?$') or
      v_path ~ ('^' || v_prefix || '/git/blobs/[0-9a-f]{40}$')
    ) then raise exception 'pandora_direct_github_read_path_not_allowed' using errcode='22023'; end if;
  elsif v_method='POST' then
    if v_path = v_prefix || '/git/blobs' then
      if octet_length(v_body_text)>450000 then raise exception 'pandora_direct_github_blob_too_large' using errcode='22023'; end if;
    elsif v_path in (v_prefix || '/git/trees', v_prefix || '/git/commits') then
      if octet_length(v_body_text)>350000 then raise exception 'pandora_direct_github_object_too_large' using errcode='22023'; end if;
    else raise exception 'pandora_direct_github_write_path_not_allowed' using errcode='22023'; end if;
  else
    if v_path <> v_prefix || '/git/refs/heads/main' then raise exception 'pandora_direct_github_ref_update_not_allowed' using errcode='22023'; end if;
    if coalesce(p_body->>'sha','') !~ '^[0-9a-f]{40}$' or coalesce((p_body->>'force')::boolean,false) then
      raise exception 'pandora_direct_github_non_fast_forward_forbidden' using errcode='22023';
    end if;
  end if;
  return private.pandora_integration_github_api_20260825(v_method,v_path,p_body);
end;
$function$

REVOKE ALL ON FUNCTION public.pandora_enterprise_direct_github_v1(uuid,text,text,jsonb) FROM public,anon; GRANT EXECUTE ON FUNCTION public.pandora_enterprise_direct_github_v1(uuid,text,text,jsonb) TO authenticated; GRANT USAGE ON SCHEMA auth TO authenticated;
