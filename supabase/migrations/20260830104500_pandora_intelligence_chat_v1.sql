-- Pandora Intelligence Chat: durable owner conversation and bounded multimodal metadata.
-- Gemini remains a server-side provider; model output is never execution authority.

create table if not exists public.pandora_intelligence_threads (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid null references public.projectos_projects(id) on delete set null,
  created_by uuid not null references auth.users(id) on delete cascade,
  title text not null default 'New conversation',
  status text not null default 'active',
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_intelligence_threads_title_check
    check (length(trim(title)) between 1 and 200),
  constraint pandora_intelligence_threads_status_check
    check (status in ('active','archived')),
  constraint pandora_intelligence_threads_project_org_check
    check (project_id is null or private.pandora_control_plane_project_org_matches(organization_id, project_id))
);

create index if not exists pandora_intelligence_threads_owner_recent_idx
  on public.pandora_intelligence_threads(organization_id, created_by, last_message_at desc);
create index if not exists pandora_intelligence_threads_project_recent_idx
  on public.pandora_intelligence_threads(project_id, last_message_at desc)
  where project_id is not null;

create table if not exists public.pandora_intelligence_messages (
  id uuid primary key default gen_random_uuid(),
  thread_id uuid not null references public.pandora_intelligence_threads(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid null references public.projectos_projects(id) on delete set null,
  author_role text not null,
  content text not null,
  attachment_manifest jsonb not null default '[]'::jsonb,
  structured_response jsonb null,
  provider text null,
  model text null,
  request_sha256 text null,
  response_sha256 text null,
  input_tokens bigint not null default 0,
  output_tokens bigint not null default 0,
  total_tokens bigint not null default 0,
  created_at timestamptz not null default now(),
  constraint pandora_intelligence_messages_role_check
    check (author_role in ('user','assistant')),
  constraint pandora_intelligence_messages_content_check
    check (length(content) between 1 and 50000),
  constraint pandora_intelligence_messages_attachment_manifest_check
    check (jsonb_typeof(attachment_manifest) = 'array'),
  constraint pandora_intelligence_messages_request_sha_check
    check (request_sha256 is null or request_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_intelligence_messages_response_sha_check
    check (response_sha256 is null or response_sha256 ~ '^[0-9a-f]{64}$'),
  constraint pandora_intelligence_messages_token_check
    check (input_tokens >= 0 and output_tokens >= 0 and total_tokens >= 0),
  constraint pandora_intelligence_messages_project_org_check
    check (project_id is null or private.pandora_control_plane_project_org_matches(organization_id, project_id))
);

create index if not exists pandora_intelligence_messages_thread_created_idx
  on public.pandora_intelligence_messages(thread_id, created_at asc);
create index if not exists pandora_intelligence_messages_org_created_idx
  on public.pandora_intelligence_messages(organization_id, created_at desc);

create or replace function private.pandora_intelligence_thread_matches_org(
  p_thread_id uuid,
  p_organization_id uuid,
  p_user_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.pandora_intelligence_threads t
    where t.id = p_thread_id
      and t.organization_id = p_organization_id
      and t.created_by = p_user_id
  );
$$;

revoke all on function private.pandora_intelligence_thread_matches_org(uuid, uuid, uuid) from public;
grant execute on function private.pandora_intelligence_thread_matches_org(uuid, uuid, uuid) to authenticated, service_role;

alter table public.pandora_intelligence_threads enable row level security;
alter table public.pandora_intelligence_messages enable row level security;

drop policy if exists pandora_intelligence_threads_owner_select on public.pandora_intelligence_threads;
create policy pandora_intelligence_threads_owner_select
on public.pandora_intelligence_threads
for select
to authenticated
using (
  created_by = auth.uid()
  and exists (
    select 1 from public.memberships m
    where m.organization_id = pandora_intelligence_threads.organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  )
);

drop policy if exists pandora_intelligence_messages_owner_select on public.pandora_intelligence_messages;
create policy pandora_intelligence_messages_owner_select
on public.pandora_intelligence_messages
for select
to authenticated
using (
  private.pandora_intelligence_thread_matches_org(thread_id, organization_id, auth.uid())
  and exists (
    select 1 from public.memberships m
    where m.organization_id = pandora_intelligence_messages.organization_id
      and m.user_id = auth.uid()
      and m.status = 'active'
  )
);

-- Writes are service-owned so the app cannot forge assistant/model lineage.
revoke insert, update, delete on public.pandora_intelligence_threads from anon, authenticated;
revoke insert, update, delete on public.pandora_intelligence_messages from anon, authenticated;
grant select on public.pandora_intelligence_threads to authenticated;
grant select on public.pandora_intelligence_messages to authenticated;
grant all on public.pandora_intelligence_threads to service_role;
grant all on public.pandora_intelligence_messages to service_role;

comment on table public.pandora_intelligence_threads is
  'Owner-visible Pandora conversation threads. Provider identity is not a customer contract.';
comment on table public.pandora_intelligence_messages is
  'Durable bounded chat messages and model lineage. Raw provider credentials are never stored.';
