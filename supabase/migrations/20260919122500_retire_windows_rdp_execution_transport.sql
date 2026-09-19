-- Retire the inaccessible Windows/AWS RDP execution transport.
-- Canonical GitHub + Supabase paths remain authoritative. The historical RPC
-- names are retained only as fail-closed tombstones so stale callers cannot
-- mutate source if an old machine comes back online.

delete from public.pandora_local_ai_workers
where worker_id = 'rdp-ec2amaz-spae2vg';

create or replace function public.pandora_rdp_github_request_v1(
  p_method text,
  p_path text,
  p_body jsonb default null::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  raise exception 'PANDORA_RDP_TRANSPORT_RETIRED'
    using errcode = '55000',
          hint = 'The former Windows/AWS RDP execution node is retired. Use canonical GitHub/Supabase execution paths.';
end;
$$;

create or replace function public.pandora_rdp_memory_github_request_v1(
  p_method text,
  p_path text,
  p_body jsonb default null::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $$
begin
  raise exception 'PANDORA_RDP_TRANSPORT_RETIRED'
    using errcode = '55000',
          hint = 'The former Windows/AWS RDP execution node is retired. Use canonical GitHub/Supabase execution paths.';
end;
$$;

revoke all on function public.pandora_rdp_github_request_v1(text, text, jsonb)
  from public, anon, authenticated;
revoke all on function public.pandora_rdp_memory_github_request_v1(text, text, jsonb)
  from public, anon, authenticated;
