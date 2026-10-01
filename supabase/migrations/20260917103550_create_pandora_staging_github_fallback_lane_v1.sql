create or replace function public.pandora_staging_github_fallback_request_v1(
  p_method text,
  p_path text,
  p_body jsonb default null
) returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,private
as $$
declare
  v_method text:=upper(trim(coalesce(p_method,'')));
  v_path text:=trim(coalesce(p_path,''));
  v_prefix constant text:='/repos/pandora-rvw-314296438-20260820/pandoras-box';
  v_body_text text:=coalesce(p_body::text,'');
begin
  if v_method not in ('GET','POST') or v_path like '%..%' or length(v_path)>1600 then
    raise exception 'pandora_staging_github_fallback_request_invalid' using errcode='22023';
  end if;
  if v_method='GET' then
    if not (
      v_path = v_prefix
      or v_path = v_prefix || '/git/ref/heads/main'
      or v_path ~ ('^' || v_prefix || '/git/ref/heads/pandora/staging-[a-z0-9-]{8,64}$')
      or v_path ~ ('^' || v_prefix || '/git/commits/[0-9a-f]{40}$')
      or v_path ~ ('^' || v_prefix || '/pulls/[1-9][0-9]*$')
      or v_path ~ ('^' || v_prefix || '/pulls\?state=open&head=[A-Za-z0-9_.-]+:pandora%2Fstaging-[a-z0-9-]{8,64}&base=main&per_page=10$')
    ) then raise exception 'pandora_staging_github_fallback_read_not_allowed' using errcode='22023'; end if;
  else
    if v_path not in (v_prefix||'/git/blobs',v_prefix||'/git/trees',v_prefix||'/git/commits',v_prefix||'/git/refs',v_prefix||'/pulls') then
      raise exception 'pandora_staging_github_fallback_write_not_allowed' using errcode='22023';
    end if;
    if octet_length(v_body_text)>14000000 then raise exception 'pandora_staging_github_fallback_body_too_large' using errcode='22023'; end if;
  end if;
  return private.pandora_integration_github_api_20260825(v_method,v_path,p_body);
end; $$;

revoke all on function public.pandora_staging_github_fallback_request_v1(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_staging_github_fallback_request_v1(text,text,jsonb) to service_role;
