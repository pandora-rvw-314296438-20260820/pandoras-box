
begin;

create table if not exists public.pandora_build_stream_sessions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  requested_by uuid not null references auth.users(id) on delete cascade,
  idempotency_key text not null,
  status text not null default 'queued' check (status in ('queued','streaming','assembling','building','completed','failed','cancelled')),
  build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,
  project_version_id uuid null references public.pandora_project_versions(id) on delete set null,
  public_error_code text null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (organization_id, project_id, idempotency_key)
);

create table if not exists public.pandora_build_stream_events (
  id bigint generated always as identity primary key,
  stream_id uuid not null references public.pandora_build_stream_sessions(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,
  event_type text not null check (event_type in (
    'stream_started','file_started','code_chunk','file_completed','generation_completed',
    'build_job_created','job_state','build_step','verification','preview_ready','stream_error'
  )),
  file_path text null,
  content_chunk text null,
  safe_payload jsonb not null default '{}'::jsonb,
  expires_at timestamptz not null default (now() + interval '20 minutes'),
  created_at timestamptz not null default now(),
  check (content_chunk is null or octet_length(content_chunk) <= 16384),
  check (file_path is null or length(file_path) <= 512)
);

create index if not exists pandora_build_stream_events_stream_id_id_idx
  on public.pandora_build_stream_events(stream_id, id);
create index if not exists pandora_build_stream_sessions_project_created_idx
  on public.pandora_build_stream_sessions(organization_id, project_id, created_at desc);

alter table public.pandora_build_stream_sessions enable row level security;
alter table public.pandora_build_stream_events enable row level security;

revoke all on public.pandora_build_stream_sessions from anon, authenticated;
revoke all on public.pandora_build_stream_events from anon, authenticated;
grant select on public.pandora_build_stream_sessions to authenticated;
grant select on public.pandora_build_stream_events to authenticated;

drop policy if exists pandora_build_stream_sessions_member_read on public.pandora_build_stream_sessions;
create policy pandora_build_stream_sessions_member_read
on public.pandora_build_stream_sessions
for select to authenticated
using (
  exists (
    select 1 from public.memberships m
    where m.organization_id = pandora_build_stream_sessions.organization_id
      and m.user_id = auth.uid()
      and m.status::text = 'active'
  )
);

drop policy if exists pandora_build_stream_events_member_live_read on public.pandora_build_stream_events;
create policy pandora_build_stream_events_member_live_read
on public.pandora_build_stream_events
for select to authenticated
using (
  expires_at > now()
  and exists (
    select 1 from public.memberships m
    where m.organization_id = pandora_build_stream_events.organization_id
      and m.user_id = auth.uid()
      and m.status::text = 'active'
  )
);

create or replace function public.pandora_gemini_stream_credential_service_20260901()
returns text
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_secret text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'SERVICE_ROLE_REQUIRED';
  end if;
  select decrypted_secret into v_secret
  from vault.decrypted_secrets
  where name = 'gemini_api_key'
  order by created_at desc
  limit 1;
  if nullif(btrim(v_secret), '') is null then
    raise exception 'GEMINI_STREAM_CREDENTIAL_UNAVAILABLE';
  end if;
  return v_secret;
end;
$fn$;
revoke all on function public.pandora_gemini_stream_credential_service_20260901() from public, anon, authenticated;
grant execute on function public.pandora_gemini_stream_credential_service_20260901() to service_role;

create or replace function private.pandora_mirror_build_job_to_stream_20260901()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_stream_id uuid;
  v_event_type text := 'job_state';
begin
  select s.id into v_stream_id
  from public.pandora_build_stream_sessions s
  where s.build_job_id = new.id
  order by s.created_at desc
  limit 1;
  if v_stream_id is null then return new; end if;
  if new.current_stage = 'preview_ready' and new.status = 'succeeded' then
    v_event_type := 'preview_ready';
  elsif new.current_stage = 'verifying' or new.status = 'waiting_verification' then
    v_event_type := 'verification';
  end if;
  if tg_op = 'INSERT'
     or new.status is distinct from old.status
     or new.current_stage is distinct from old.current_stage then
    insert into public.pandora_build_stream_events(
      stream_id, organization_id, project_id, build_job_id, event_type, safe_payload
    ) values (
      v_stream_id, new.organization_id, new.project_id, new.id, v_event_type,
      jsonb_build_object('status', new.status, 'stage', new.current_stage)
    );
    update public.pandora_build_stream_sessions
      set status = case
        when new.status = 'failed' then 'failed'
        when new.status = 'cancelled' then 'cancelled'
        when new.status = 'succeeded' and new.current_stage = 'preview_ready' then 'completed'
        else 'building'
      end,
      updated_at = now()
    where id = v_stream_id;
  end if;
  return new;
end;
$fn$;

create or replace function private.pandora_mirror_build_step_to_stream_20260901()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
declare
  v_stream public.pandora_build_stream_sessions%rowtype;
begin
  select s.* into v_stream
  from public.pandora_build_stream_sessions s
  where s.build_job_id = new.build_job_id
  order by s.created_at desc
  limit 1;
  if v_stream.id is null then return new; end if;
  if tg_op = 'INSERT'
     or new.status is distinct from old.status
     or new.started_at is distinct from old.started_at
     or new.completed_at is distinct from old.completed_at then
    insert into public.pandora_build_stream_events(
      stream_id, organization_id, project_id, build_job_id, event_type, safe_payload
    ) values (
      v_stream.id, new.organization_id, new.project_id, new.build_job_id, 'build_step',
      jsonb_strip_nulls(jsonb_build_object(
        'stepKey', new.step_key,
        'stepKind', new.step_kind,
        'status', new.status,
        'error', new.public_error_summary
      ))
    );
  end if;
  return new;
end;
$fn$;

drop trigger if exists pandora_mirror_build_job_to_stream_20260901 on public.pandora_build_jobs;
create trigger pandora_mirror_build_job_to_stream_20260901
after insert or update of status, current_stage on public.pandora_build_jobs
for each row execute function private.pandora_mirror_build_job_to_stream_20260901();

drop trigger if exists pandora_mirror_build_step_to_stream_20260901 on public.pandora_build_job_steps;
create trigger pandora_mirror_build_step_to_stream_20260901
after insert or update of status, started_at, completed_at on public.pandora_build_job_steps
for each row execute function private.pandora_mirror_build_step_to_stream_20260901();

do $do$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pandora_build_stream_events'
  ) then
    alter publication supabase_realtime add table public.pandora_build_stream_events;
  end if;
end;
$do$;

commit;
