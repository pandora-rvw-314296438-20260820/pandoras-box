create or replace function public.pandora_enterprise_direct_github_v1(
  p_organization_id uuid,
  p_method text,
  p_path text,
  p_body jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth
as $$
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
$$;
revoke all on function public.pandora_enterprise_direct_github_v1(uuid,text,text,jsonb) from public, anon;
grant execute on function public.pandora_enterprise_direct_github_v1(uuid,text,text,jsonb) to authenticated;;
