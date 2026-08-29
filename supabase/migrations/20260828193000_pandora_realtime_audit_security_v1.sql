
-- Pandora Worker A A16-A19: safe Build Theatre Realtime, project-scoped immutable audit,
-- final RLS/service-boundary hardening, and query-driven indexes.
-- This migration persists customer-safe control-plane truth only. It does not execute providers.

create table if not exists public.pandora_build_theatre_projection (
  project_id uuid primary key references public.projectos_projects(id) on delete cascade,
  organization_id uuid not null references public.organizations(id) on delete cascade,
  build_job_id uuid null references public.pandora_build_jobs(id) on delete set null,
  project_spec_id uuid null references public.pandora_project_specs(id) on delete set null,
  project_version_id uuid null references public.pandora_project_versions(id) on delete set null,
  owner_state text not null default 'draft',
  owner_stage text not null default 'understanding',
  progress_percent smallint null,
  public_message text not null default 'Pandora is preparing your project.',
  preview_url text null,
  live_url text null,
  needs_you boolean not null default false,
  retry_available boolean not null default false,
  last_event_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_build_theatre_projection_state_check check (
    owner_state in ('draft','building','checking','needs_you','blocked','preview_ready','publishing','live','complete')
  ),
  constraint pandora_build_theatre_projection_stage_check check (
    owner_stage in ('understanding','designing','building','connecting','checking','fixing','preparing_preview','preview_ready','needs_you','publishing','live')
  ),
  constraint pandora_build_theatre_projection_progress_check check (
    progress_percent is null or progress_percent between 0 and 100
  ),
  constraint pandora_build_theatre_projection_message_check check (
    length(trim(public_message)) between 1 and 280
  ),
  constraint pandora_build_theatre_projection_preview_url_check check (
    preview_url is null or (length(preview_url) <= 2048 and preview_url ~ '^https://')
  ),
  constraint pandora_build_theatre_projection_live_url_check check (
    live_url is null or (length(live_url) <= 2048 and live_url ~ '^https://')
  ),
  constraint pandora_build_theatre_projection_project_org_check check (
    private.pandora_control_plane_project_org_matches(organization_id, project_id)
  )
);

create index if not exists pandora_build_theatre_projection_org_state_idx
  on public.pandora_build_theatre_projection(organization_id, owner_state, updated_at desc);
create index if not exists pandora_build_theatre_projection_job_idx
  on public.pandora_build_theatre_projection(build_job_id)
  where build_job_id is not null;
create index if not exists pandora_build_theatre_projection_version_idx
  on public.pandora_build_theatre_projection(project_version_id)
  where project_version_id is not null;

create or replace function private.pandora_build_theatre_owner_stage(p_stage text, p_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(coalesce(p_status,'')) in ('failed','cancelled') then 'fixing'
    when lower(coalesce(p_status,'')) = 'waiting_approval' then 'needs_you'
    when lower(coalesce(p_status,'')) = 'waiting_verification' then 'checking'
    when lower(coalesce(p_stage,'')) in ('received','understanding') then 'understanding'
    when lower(coalesce(p_stage,'')) in ('planning','designing') then 'designing'
    when lower(coalesce(p_stage,'')) = 'building' then 'building'
    when lower(coalesce(p_stage,'')) = 'connecting' then 'connecting'
    when lower(coalesce(p_stage,'')) in ('testing','verifying') then 'checking'
    when lower(coalesce(p_stage,'')) in ('repairing','failed','rolling_back') then 'fixing'
    when lower(coalesce(p_stage,'')) = 'previewing' then 'preparing_preview'
    when lower(coalesce(p_stage,'')) = 'preview_ready' then 'preview_ready'
    when lower(coalesce(p_stage,'')) in ('awaiting_approval','needs_you') then 'needs_you'
    when lower(coalesce(p_stage,'')) = 'publishing' then 'publishing'
    when lower(coalesce(p_stage,'')) = 'live' then 'live'
    else 'understanding'
  end
$$;

create or replace function private.pandora_build_theatre_owner_state(p_stage text, p_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when lower(coalesce(p_status,'')) = 'failed' then 'blocked'
    when lower(coalesce(p_status,'')) = 'waiting_approval'
      or lower(coalesce(p_stage,'')) in ('awaiting_approval','needs_you') then 'needs_you'
    when lower(coalesce(p_stage,'')) = 'live' then 'live'
    when lower(coalesce(p_stage,'')) = 'publishing' then 'publishing'
    when lower(coalesce(p_stage,'')) = 'preview_ready' then 'preview_ready'
    when lower(coalesce(p_stage,'')) in ('testing','verifying') or lower(coalesce(p_status,'')) = 'waiting_verification' then 'checking'
    when lower(coalesce(p_status,'')) = 'succeeded' then 'complete'
    when lower(coalesce(p_status,'')) = 'cancelled' then 'blocked'
    when lower(coalesce(p_status,'')) in ('queued','claimed','running') then 'building'
    else 'draft'
  end
$$;

create or replace function private.pandora_build_theatre_progress(p_stage text, p_status text)
returns smallint
language sql
immutable
set search_path = ''
as $$
  select (
    case private.pandora_build_theatre_owner_stage(p_stage,p_status)
      when 'understanding' then 10
      when 'designing' then 20
      when 'building' then 45
      when 'connecting' then 60
      when 'checking' then 75
      when 'fixing' then 65
      when 'preparing_preview' then 85
      when 'needs_you' then 85
      when 'publishing' then 95
      when 'preview_ready' then 100
      when 'live' then 100
      else 0
    end
  )::smallint
$$;

create or replace function private.pandora_build_theatre_message(p_stage text, p_status text)
returns text
language sql
immutable
set search_path = ''
as $$
  select case private.pandora_build_theatre_owner_stage(p_stage,p_status)
    when 'understanding' then 'Pandora is confirming the result you asked for.'
    when 'designing' then 'Pandora is shaping the experience around your goal.'
    when 'building' then 'Pandora is creating the working version.'
    when 'connecting' then 'Pandora is joining the parts your project needs.'
    when 'checking' then 'Pandora is checking this version before the next step.'
    when 'fixing' then 'Pandora found something to fix and is working on it.'
    when 'preparing_preview' then 'Pandora is making this version available for you to inspect.'
    when 'preview_ready' then 'Your latest live preview is ready to open.'
    when 'needs_you' then 'Pandora needs your input before it can continue.'
    when 'publishing' then 'Pandora is making this verified version live.'
    when 'live' then 'Your verified project is live.'
    else 'Pandora is preparing your project.'
  end
$$;

create or replace function private.pandora_sync_build_theatre_from_job()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.pandora_build_theatre_projection(
    project_id,organization_id,build_job_id,project_spec_id,project_version_id,
    owner_state,owner_stage,progress_percent,public_message,needs_you,retry_available,
    last_event_at,updated_at
  )
  values (
    new.project_id,new.organization_id,new.id,new.project_spec_id,new.target_project_version_id,
    private.pandora_build_theatre_owner_state(new.current_stage,new.status),
    private.pandora_build_theatre_owner_stage(new.current_stage,new.status),
    private.pandora_build_theatre_progress(new.current_stage,new.status),
    private.pandora_build_theatre_message(new.current_stage,new.status),
    new.status = 'waiting_approval' or new.current_stage in ('awaiting_approval','needs_you'),
    new.status in ('failed','cancelled'),
    now(),now()
  )
  on conflict (project_id) do update
    set organization_id = excluded.organization_id,
        build_job_id = excluded.build_job_id,
        project_spec_id = excluded.project_spec_id,
        project_version_id = coalesce(excluded.project_version_id, pandora_build_theatre_projection.project_version_id),
        owner_state = excluded.owner_state,
        owner_stage = excluded.owner_stage,
        progress_percent = excluded.progress_percent,
        public_message = excluded.public_message,
        needs_you = excluded.needs_you,
        retry_available = excluded.retry_available,
        last_event_at = excluded.last_event_at,
        updated_at = excluded.updated_at;
  return new;
end
$$;

drop trigger if exists pandora_build_jobs_build_theatre_projection on public.pandora_build_jobs;
create trigger pandora_build_jobs_build_theatre_projection
after insert or update of status,current_stage,target_project_version_id
on public.pandora_build_jobs
for each row execute function private.pandora_sync_build_theatre_from_job();

create or replace function private.pandora_sync_build_theatre_from_deployment()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_spec uuid;
  v_job uuid;
begin
  if new.url is null or lower(new.status) not in ('ready','live','success','succeeded','completed') then
    return new;
  end if;

  select v.project_spec_id,v.build_job_id
    into v_spec,v_job
  from public.pandora_project_versions v
  where v.id = new.version_id;

  insert into public.pandora_build_theatre_projection(
    project_id,organization_id,build_job_id,project_spec_id,project_version_id,
    owner_state,owner_stage,progress_percent,public_message,preview_url,live_url,
    needs_you,retry_available,last_event_at,updated_at
  )
  values (
    new.project_id,new.organization_id,v_job,v_spec,new.version_id,
    case when new.environment='production' then 'live' else 'preview_ready' end,
    case when new.environment='production' then 'live' else 'preview_ready' end,
    100,
    case when new.environment='production' then 'Your verified project is live.' else 'Your latest live preview is ready to open.' end,
    case when new.environment='preview' then new.url else null end,
    case when new.environment='production' then new.url else null end,
    false,false,now(),now()
  )
  on conflict(project_id) do update
    set project_version_id = excluded.project_version_id,
        project_spec_id = coalesce(excluded.project_spec_id,pandora_build_theatre_projection.project_spec_id),
        build_job_id = coalesce(excluded.build_job_id,pandora_build_theatre_projection.build_job_id),
        owner_state = excluded.owner_state,
        owner_stage = excluded.owner_stage,
        progress_percent = excluded.progress_percent,
        public_message = excluded.public_message,
        preview_url = coalesce(excluded.preview_url,pandora_build_theatre_projection.preview_url),
        live_url = coalesce(excluded.live_url,pandora_build_theatre_projection.live_url),
        needs_you = false,
        retry_available = false,
        last_event_at = now(),
        updated_at = now();
  return new;
end
$$;

create or replace function private.pandora_sync_build_theatre_from_version()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_state text;
  v_stage text;
  v_message text;
begin
  if new.lifecycle_status not in ('verification_pending','verified','preview_ready','production_candidate','live','rejected','rolled_back') then
    return new;
  end if;

  v_state := case
    when new.lifecycle_status='live' then 'live'
    when new.lifecycle_status='preview_ready' then 'preview_ready'
    when new.lifecycle_status in ('verification_pending','verified','production_candidate') then 'checking'
    when new.lifecycle_status in ('rejected','rolled_back') then 'blocked'
    else 'building'
  end;
  v_stage := case
    when new.lifecycle_status='live' then 'live'
    when new.lifecycle_status='preview_ready' then 'preview_ready'
    when new.lifecycle_status in ('verification_pending','verified','production_candidate') then 'checking'
    else 'fixing'
  end;
  v_message := case
    when new.lifecycle_status='live' then 'Your verified project is live.'
    when new.lifecycle_status='preview_ready' then 'Your latest live preview is ready to open.'
    when new.lifecycle_status in ('verification_pending','verified','production_candidate') then 'Pandora is checking this version before the next step.'
    else 'Pandora found something to fix and is working on it.'
  end;

  insert into public.pandora_build_theatre_projection(
    project_id,organization_id,build_job_id,project_spec_id,project_version_id,
    owner_state,owner_stage,progress_percent,public_message,needs_you,retry_available,
    last_event_at,updated_at
  )
  values(
    new.project_id,new.organization_id,new.build_job_id,new.project_spec_id,new.id,
    v_state,v_stage,
    case when v_state in ('live','preview_ready') then 100 when v_state='checking' then 75 else 65 end,
    v_message,false,v_state='blocked',now(),now()
  )
  on conflict(project_id) do update
    set project_version_id=excluded.project_version_id,
        build_job_id=coalesce(excluded.build_job_id,pandora_build_theatre_projection.build_job_id),
        project_spec_id=coalesce(excluded.project_spec_id,pandora_build_theatre_projection.project_spec_id),
        owner_state=excluded.owner_state,
        owner_stage=excluded.owner_stage,
        progress_percent=excluded.progress_percent,
        public_message=excluded.public_message,
        needs_you=false,
        retry_available=excluded.retry_available,
        last_event_at=now(),
        updated_at=now();
  return new;
end
$$;

drop trigger if exists pandora_project_versions_build_theatre_projection on public.pandora_project_versions;
create trigger pandora_project_versions_build_theatre_projection
after insert or update of lifecycle_status,verification_run_id
on public.pandora_project_versions
for each row execute function private.pandora_sync_build_theatre_from_version();

drop trigger if exists pandora_project_deployments_build_theatre_projection on public.pandora_project_deployments;
create trigger pandora_project_deployments_build_theatre_projection
after insert or update of status,url
on public.pandora_project_deployments
for each row execute function private.pandora_sync_build_theatre_from_deployment();

create or replace function private.pandora_sync_build_theatre_from_domain()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.verified and new.primary_domain then
    insert into public.pandora_build_theatre_projection(
      project_id,organization_id,owner_state,owner_stage,progress_percent,public_message,
      live_url,needs_you,retry_available,last_event_at,updated_at
    )
    values(
      new.project_id,new.organization_id,'live','live',100,'Your verified project is live.',
      'https://' || new.domain,false,false,now(),now()
    )
    on conflict(project_id) do update
      set live_url=excluded.live_url,
          owner_state=case when pandora_build_theatre_projection.owner_state='publishing' then 'live' else pandora_build_theatre_projection.owner_state end,
          owner_stage=case when pandora_build_theatre_projection.owner_stage='publishing' then 'live' else pandora_build_theatre_projection.owner_stage end,
          public_message=case when pandora_build_theatre_projection.owner_state='publishing' then 'Your verified project is live.' else pandora_build_theatre_projection.public_message end,
          progress_percent=case when pandora_build_theatre_projection.owner_state='publishing' then 100 else pandora_build_theatre_projection.progress_percent end,
          last_event_at=now(),
          updated_at=now();
  end if;
  return new;
end
$$;

drop trigger if exists pandora_project_domains_build_theatre_projection on public.pandora_project_domains;
create trigger pandora_project_domains_build_theatre_projection
after insert or update of verified,primary_domain,domain
on public.pandora_project_domains
for each row execute function private.pandora_sync_build_theatre_from_domain();

alter table public.pandora_build_theatre_projection enable row level security;
drop policy if exists pandora_build_theatre_projection_member_read on public.pandora_build_theatre_projection;
create policy pandora_build_theatre_projection_member_read
on public.pandora_build_theatre_projection
for select to authenticated
using (private.is_org_member(organization_id));

revoke all on table public.pandora_build_theatre_projection from public,anon,authenticated;
grant select on table public.pandora_build_theatre_projection to authenticated;
grant select,insert,update,delete on table public.pandora_build_theatre_projection to service_role;

do $realtime$
begin
  if exists (select 1 from pg_publication where pubname='supabase_realtime')
     and not exists (
       select 1 from pg_publication_tables
       where pubname='supabase_realtime'
         and schemaname='public'
         and tablename='pandora_build_theatre_projection'
     ) then
    execute 'alter publication supabase_realtime add table public.pandora_build_theatre_projection';
  end if;
end
$realtime$;

comment on table public.pandora_build_theatre_projection is
  'Customer-safe Worker A Realtime projection. Never contains model prompts, tool arguments, worker leases, raw errors, or secrets.';

alter table public.audit_events
  add column if not exists project_id uuid null,
  add column if not exists request_id text null,
  add column if not exists idempotency_key text null,
  add column if not exists resource_type text null,
  add column if not exists resource_id uuid null,
  add column if not exists action_hash text null,
  add column if not exists provenance_redacted jsonb not null default '{}'::jsonb;

alter table public.audit_events drop constraint if exists audit_events_worker_a_action_hash_check;
alter table public.audit_events
  add constraint audit_events_worker_a_action_hash_check
  check (action_hash is null or action_hash ~ '^[0-9a-f]{64}$');

create index if not exists audit_events_project_id_desc_idx
  on public.audit_events(project_id,id desc)
  where project_id is not null;
create index if not exists audit_events_resource_desc_idx
  on public.audit_events(resource_type,resource_id,id desc)
  where resource_type is not null and resource_id is not null;
create index if not exists audit_events_org_idempotency_idx
  on public.audit_events(organization_id,idempotency_key,id desc)
  where idempotency_key is not null;
create index if not exists audit_events_project_event_type_idx
  on public.audit_events(project_id,event_type,id desc)
  where project_id is not null;

create or replace function private.append_project_audit_event(
  target_organization_id uuid,
  target_project_id uuid,
  target_actor_type public.audit_actor_type,
  target_actor_user_id uuid,
  target_event_type text,
  target_resource_type text,
  target_resource_id uuid,
  target_request_id text,
  target_idempotency_key text,
  target_action_hash text,
  target_provenance jsonb,
  target_payload jsonb
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  prior_hash text;
  created_timestamp timestamptz := clock_timestamp();
  calculated_hash text;
  inserted_id bigint;
  safe_payload jsonb;
begin
  safe_payload := jsonb_strip_nulls(jsonb_build_object(
    'project_id',target_project_id,
    'resource_type',target_resource_type,
    'resource_id',target_resource_id,
    'request_id',target_request_id,
    'idempotency_key',target_idempotency_key,
    'action_hash',target_action_hash,
    'provenance',coalesce(target_provenance,'{}'::jsonb),
    'event',coalesce(target_payload,'{}'::jsonb)
  ));

  if private.pandora_control_plane_json_has_secret_keys(safe_payload) then
    raise exception 'audit payload contains secret-like keys' using errcode='23514';
  end if;
  if target_action_hash is not null and target_action_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'audit action hash invalid' using errcode='23514';
  end if;

  perform pg_advisory_xact_lock(hashtextextended(target_organization_id::text,0));

  select event_hash into prior_hash
  from public.audit_events
  where organization_id=target_organization_id
  order by id desc
  limit 1;

  calculated_hash := encode(
    extensions.digest(
      concat_ws(
        '|',
        target_organization_id::text,
        '',
        '',
        target_actor_type::text,
        coalesce(target_actor_user_id::text,''),
        target_event_type,
        safe_payload::text,
        coalesce(prior_hash,''),
        created_timestamp::text
      ),
      'sha256'
    ),
    'hex'
  );

  insert into public.audit_events(
    organization_id,run_id,step_id,actor_type,actor_user_id,event_type,
    payload_redacted,previous_hash,event_hash,created_at,
    project_id,request_id,idempotency_key,resource_type,resource_id,action_hash,provenance_redacted
  )
  values(
    target_organization_id,null,null,target_actor_type,target_actor_user_id,target_event_type,
    safe_payload,prior_hash,calculated_hash,created_timestamp,
    target_project_id,target_request_id,target_idempotency_key,target_resource_type,target_resource_id,target_action_hash,
    coalesce(target_provenance,'{}'::jsonb)
  )
  returning id into inserted_id;

  return inserted_id;
end
$$;

revoke all on function private.append_project_audit_event(uuid,uuid,public.audit_actor_type,uuid,text,text,uuid,text,text,text,jsonb,jsonb)
  from public,anon,authenticated;
grant execute on function private.append_project_audit_event(uuid,uuid,public.audit_actor_type,uuid,text,text,uuid,text,text,text,jsonb,jsonb)
  to service_role;

create or replace function private.pandora_control_plane_audit_trigger()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_row jsonb;
  v_old jsonb := '{}'::jsonb;
  v_org uuid;
  v_project uuid;
  v_resource uuid;
  v_actor uuid;
  v_actor_type public.audit_actor_type;
  v_request_id text;
  v_idempotency text;
  v_action_hash text;
  v_headers jsonb;
  v_payload jsonb;
begin
  if tg_op='DELETE' then
    v_row := to_jsonb(old);
    v_old := to_jsonb(old);
  elsif tg_op='UPDATE' then
    v_row := to_jsonb(new);
    v_old := to_jsonb(old);
  else
    v_row := to_jsonb(new);
  end if;

  v_org := nullif(v_row->>'organization_id','')::uuid;
  v_project := nullif(v_row->>'project_id','')::uuid;
  v_resource := nullif(v_row->>'id','')::uuid;
  v_idempotency := nullif(v_row->>'idempotency_key','');
  v_action_hash := nullif(v_row->>'action_hash','');

  if v_project is null and v_action_hash is not null then
    select p.project_id into v_project
    from public.pandora_policy_actions p
    where p.organization_id=v_org and p.action_hash=v_action_hash
    limit 1;
    if v_project is null and to_regclass('public.pandora_database_change_plans') is not null then
      select d.project_id into v_project
      from public.pandora_database_change_plans d
      where d.organization_id=v_org and d.action_hash=v_action_hash
      limit 1;
    end if;
  end if;

  begin
    v_headers := nullif(current_setting('request.headers',true),'')::jsonb;
    v_request_id := coalesce(v_headers->>'x-request-id',v_headers->>'x-correlation-id');
  exception when others then
    v_request_id := null;
  end;

  v_actor := auth.uid();
  v_actor_type := case when v_actor is null then 'system'::public.audit_actor_type else 'human'::public.audit_actor_type end;

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'operation',lower(tg_op),
    'status',coalesce(v_row->>'status',v_row->>'lifecycle_status',v_row->>'rotation_status'),
    'previous_status',coalesce(v_old->>'status',v_old->>'lifecycle_status',v_old->>'rotation_status'),
    'stage',v_row->>'current_stage',
    'previous_stage',v_old->>'current_stage',
    'decision',v_row->>'decision',
    'previous_decision',v_old->>'decision',
    'project_spec_id',v_row->>'project_spec_id',
    'project_version_id',coalesce(v_row->>'project_version_id',v_row->>'version_id'),
    'build_job_id',v_row->>'build_job_id',
    'sequence_no',v_row->>'sequence_no'
  ));

  perform private.append_project_audit_event(
    v_org,v_project,v_actor_type,v_actor,
    'pandora_control_plane.'||tg_table_name||'.'||lower(tg_op),
    tg_table_name,v_resource,v_request_id,v_idempotency,v_action_hash,
    jsonb_build_object('source','database_trigger','schema',tg_table_schema),
    v_payload
  );

  if tg_op='DELETE' then return old; else return new; end if;
end
$$;

revoke all on function private.pandora_control_plane_audit_trigger() from public,anon,authenticated;
grant execute on function private.pandora_control_plane_audit_trigger() to service_role;

do $audit_triggers$
declare
  v_table text;
begin
  foreach v_table in array array[
    'pandora_project_intents',
    'pandora_project_specs',
    'pandora_build_jobs',
    'pandora_verification_runs',
    'pandora_policy_actions',
    'approvals',
    'pandora_project_versions',
    'pandora_project_deployments',
    'pandora_project_domains',
    'pandora_budget_limits',
    'pandora_runtime_resources',
    'pandora_secret_references',
    'pandora_database_change_plans'
  ]
  loop
    execute format('drop trigger if exists %I on public.%I',v_table||'_control_plane_audit',v_table);
    execute format(
      'create trigger %I after insert or update or delete on public.%I for each row execute function private.pandora_control_plane_audit_trigger()',
      v_table||'_control_plane_audit',v_table
    );
  end loop;
end
$audit_triggers$;

comment on column public.audit_events.project_id is
  'Historical project identity for project-scoped control-plane events; intentionally no FK so audit history survives project deletion.';
comment on column public.audit_events.provenance_redacted is
  'Redacted provenance metadata duplicated into the hashed payload for tamper-evident project audit history.';

revoke insert,update,delete on table public.audit_events from public,anon,authenticated,service_role;

drop policy if exists pandora_project_versions_operator_write on public.pandora_project_versions;
drop policy if exists pandora_project_deployments_operator_write on public.pandora_project_deployments;
drop policy if exists pandora_project_domains_operator_write on public.pandora_project_domains;

revoke insert,update,delete on table public.pandora_project_versions from authenticated;
revoke insert,update,delete on table public.pandora_project_deployments from authenticated;
revoke insert,update,delete on table public.pandora_project_domains from authenticated;
grant select on table public.pandora_project_versions to authenticated;
grant select on table public.pandora_project_deployments to authenticated;
grant select on table public.pandora_project_domains to authenticated;
grant select,insert,update,delete on table public.pandora_project_versions to service_role;
grant select,insert,update,delete on table public.pandora_project_deployments to service_role;
grant select,insert,update,delete on table public.pandora_project_domains to service_role;

revoke execute on function private.pandora_record_build_job_state_event() from public,anon,authenticated;
revoke execute on function private.pandora_validate_artifact_version_lineage() from public,anon,authenticated;
revoke execute on function private.pandora_validate_build_job_child() from public,anon,authenticated;
revoke execute on function private.pandora_validate_build_job_lineage() from public,anon,authenticated;
revoke execute on function private.pandora_validate_control_plane_scope() from public,anon,authenticated;
revoke execute on function private.pandora_validate_policy_action() from public,anon,authenticated;
revoke execute on function private.pandora_validate_project_version_control_plane() from public,anon,authenticated;
revoke execute on function private.pandora_validate_verification_identity() from public,anon,authenticated;
revoke execute on function private.pandora_validate_budget_limit_scope() from public,anon,authenticated;
revoke execute on function private.pandora_validate_cost_entry_scope() from public,anon,authenticated;
revoke execute on function private.pandora_validate_project_node_scope() from public,anon,authenticated;
revoke execute on function private.pandora_validate_project_relationship_scope() from public,anon,authenticated;
revoke execute on function private.pandora_validate_runtime_resource_scope() from public,anon,authenticated;
revoke execute on function private.pandora_validate_secret_reference_scope() from public,anon,authenticated;
revoke execute on function private.pandora_validate_database_change_plan() from public,anon,authenticated;
revoke execute on function private.pandora_validate_database_change_item_scope() from public,anon,authenticated;
revoke execute on function private.pandora_control_plane_prevent_history_mutation() from public,anon,authenticated;
revoke execute on function private.pandora_sync_build_theatre_from_job() from public,anon,authenticated;
revoke execute on function private.pandora_sync_build_theatre_from_deployment() from public,anon,authenticated;
revoke execute on function private.pandora_sync_build_theatre_from_version() from public,anon,authenticated;
revoke execute on function private.pandora_sync_build_theatre_from_domain() from public,anon,authenticated;
revoke execute on function private.pandora_build_theatre_owner_stage(text,text) from public,anon,authenticated;
revoke execute on function private.pandora_build_theatre_owner_state(text,text) from public,anon,authenticated;
revoke execute on function private.pandora_build_theatre_progress(text,text) from public,anon,authenticated;
revoke execute on function private.pandora_build_theatre_message(text,text) from public,anon,authenticated;

grant execute on function private.pandora_record_build_job_state_event() to service_role;
grant execute on function private.pandora_validate_artifact_version_lineage() to service_role;
grant execute on function private.pandora_validate_build_job_child() to service_role;
grant execute on function private.pandora_validate_build_job_lineage() to service_role;
grant execute on function private.pandora_validate_control_plane_scope() to service_role;
grant execute on function private.pandora_validate_policy_action() to service_role;
grant execute on function private.pandora_validate_project_version_control_plane() to service_role;
grant execute on function private.pandora_validate_verification_identity() to service_role;
grant execute on function private.pandora_validate_budget_limit_scope() to service_role;
grant execute on function private.pandora_validate_cost_entry_scope() to service_role;
grant execute on function private.pandora_validate_project_node_scope() to service_role;
grant execute on function private.pandora_validate_project_relationship_scope() to service_role;
grant execute on function private.pandora_validate_runtime_resource_scope() to service_role;
grant execute on function private.pandora_validate_secret_reference_scope() to service_role;
grant execute on function private.pandora_validate_database_change_plan() to service_role;
grant execute on function private.pandora_validate_database_change_item_scope() to service_role;
grant execute on function private.pandora_control_plane_prevent_history_mutation() to service_role;
grant execute on function private.pandora_sync_build_theatre_from_job() to service_role;
grant execute on function private.pandora_sync_build_theatre_from_deployment() to service_role;
grant execute on function private.pandora_sync_build_theatre_from_version() to service_role;
grant execute on function private.pandora_sync_build_theatre_from_domain() to service_role;
grant execute on function private.pandora_build_theatre_owner_stage(text,text) to service_role;
grant execute on function private.pandora_build_theatre_owner_state(text,text) to service_role;
grant execute on function private.pandora_build_theatre_progress(text,text) to service_role;
grant execute on function private.pandora_build_theatre_message(text,text) to service_role;

create index if not exists pandora_build_jobs_project_active_stage_idx
  on public.pandora_build_jobs(project_id,status,current_stage,updated_at desc)
  where status in ('queued','claimed','running','waiting_approval','waiting_verification');
create index if not exists pandora_project_versions_live_idx
  on public.pandora_project_versions(project_id,created_at desc)
  where lifecycle_status='live';
create index if not exists pandora_project_versions_verification_idx
  on public.pandora_project_versions(verification_run_id)
  where verification_run_id is not null;
create index if not exists pandora_verification_runs_project_status_idx
  on public.pandora_verification_runs(project_id,status,created_at desc);
create index if not exists pandora_policy_actions_project_pending_idx
  on public.pandora_policy_actions(project_id,status,created_at)
  where status in ('proposed','authorized');

comment on function private.pandora_control_plane_audit_trigger() is
  'Appends redacted project-scoped lifecycle metadata to the existing organization hash chain. Never copies full control-plane rows.';
