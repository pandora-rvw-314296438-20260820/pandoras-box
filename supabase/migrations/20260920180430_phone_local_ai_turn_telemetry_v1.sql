create table if not exists public.pandora_phone_local_ai_turns (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  phase text not null check (phase in ('route','warm','self_test','generation','fallback','success')),
  outcome text not null check (outcome in ('started','bypassed','failed','cloud','success')),
  reason text,
  model_name text,
  model_sha256 text,
  created_at timestamptz not null default now()
);

create index if not exists pandora_phone_local_ai_turns_org_created_idx
  on public.pandora_phone_local_ai_turns (organization_id, created_at desc);

alter table public.pandora_phone_local_ai_turns enable row level security;

drop policy if exists pandora_phone_local_ai_turns_owner_read
  on public.pandora_phone_local_ai_turns;
create policy pandora_phone_local_ai_turns_owner_read
  on public.pandora_phone_local_ai_turns
  for select
  to authenticated
  using (
    user_id = auth.uid()
    and exists (
      select 1
      from public.memberships m
      where m.organization_id = pandora_phone_local_ai_turns.organization_id
        and m.user_id = auth.uid()
        and m.status::text = 'active'
    )
  );

revoke all on public.pandora_phone_local_ai_turns from anon, authenticated;
grant select on public.pandora_phone_local_ai_turns to authenticated;

create or replace function public.record_phone_local_ai_turn_v1(
  p_organization_id uuid,
  p_phase text,
  p_outcome text,
  p_reason text default null,
  p_model_name text default null,
  p_model_sha256 text default null
)
returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_id uuid;
  v_reason text := nullif(trim(coalesce(p_reason,'')),'');
  v_model_name text := nullif(trim(coalesce(p_model_name,'')),'');
  v_sha text := lower(nullif(trim(coalesce(p_model_sha256,'')),''));
begin
  if v_uid is null then
    raise exception 'sign in required' using errcode='42501';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = v_uid
      and m.status::text = 'active'
  ) then
    raise exception 'organization membership required' using errcode='42501';
  end if;

  if p_phase not in ('route','warm','self_test','generation','fallback','success')
     or p_outcome not in ('started','bypassed','failed','cloud','success') then
    raise exception 'invalid local ai telemetry state' using errcode='22023';
  end if;

  if v_reason is not null and length(v_reason) > 160 then
    raise exception 'local ai reason too long' using errcode='22023';
  end if;
  if v_model_name is not null and length(v_model_name) > 160 then
    raise exception 'local ai model name too long' using errcode='22023';
  end if;
  if v_sha is not null and v_sha !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid local ai model sha' using errcode='22023';
  end if;

  insert into public.pandora_phone_local_ai_turns(
    organization_id,user_id,phase,outcome,reason,model_name,model_sha256
  )
  values (
    p_organization_id,v_uid,p_phase,p_outcome,v_reason,v_model_name,v_sha
  )
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function public.record_phone_local_ai_turn_v1(
  uuid,text,text,text,text,text
) from public, anon;
grant execute on function public.record_phone_local_ai_turn_v1(
  uuid,text,text,text,text,text
) to authenticated;
