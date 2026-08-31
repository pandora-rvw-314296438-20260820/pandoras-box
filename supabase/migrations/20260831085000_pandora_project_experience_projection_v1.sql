
-- Pandora Project Experience Projection v1
-- Derived customer-facing state. Canonical authority remains ProjectSpec,
-- ProjectVersion, build/deployment/verification/runtime records.
-- Build Theatre is activity-only and may never override canonical LIVE state.

create table if not exists public.pandora_project_experience_projection (
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid primary key references public.projectos_projects(id) on delete cascade,
  experience_state text not null
    check (experience_state in ('START','UNDERSTAND','BUILD','LIVE','REBUILD','REVIEW','PUBLISH')),
  transition_sequence bigint not null default 1
    check (transition_sequence >= 1),
  current_version_id uuid references public.pandora_project_versions(id) on delete set null,
  current_preview_deployment_id uuid references public.pandora_project_deployments(id) on delete set null,
  current_verified boolean not null default false,
  candidate_version_id uuid references public.pandora_project_versions(id) on delete set null,
  candidate_preview_deployment_id uuid references public.pandora_project_deployments(id) on delete set null,
  candidate_verification_state text not null default 'not_started'
    check (candidate_verification_state in ('not_started','checking','passed','failed','blocked')),
  production_version_id uuid references public.pandora_project_versions(id) on delete set null,
  production_deployment_id uuid references public.pandora_project_deployments(id) on delete set null,
  active_build_job_id uuid references public.pandora_build_jobs(id) on delete set null,
  build_phase text
    check (build_phase is null or build_phase in (
      'understanding','building','connecting','checking','previewing',
      'needs_you','publishing','rolling_back'
    )),
  public_message text not null,
  needs_you boolean not null default false,
  retry_available boolean not null default false,
  can_focus boolean not null default false,
  can_change boolean not null default false,
  can_undo boolean not null default false,
  can_publish boolean not null default false,
  can_rollback boolean not null default false,
  verification_summary jsonb not null default '{}'::jsonb
    check (jsonb_typeof(verification_summary) = 'object'),
  change_summary text,
  safe_failure_code text,
  safe_failure_message text,
  last_transition_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint pandora_project_experience_project_org_check
    check (private.pandora_control_plane_project_org_matches(organization_id, project_id)),
  constraint pandora_project_experience_candidate_diff_check
    check (
      candidate_version_id is null
      or current_version_id is null
      or candidate_version_id <> current_version_id
    ),
  constraint pandora_project_experience_publish_guard_check
    check (not can_publish or candidate_verification_state = 'passed' or current_verified)
);

comment on table public.pandora_project_experience_projection is
  'Derived Simple Mode projection. Never authoritative for source/build/deploy/verification truth.';

alter table public.pandora_project_experience_projection enable row level security;

drop policy if exists pandora_project_experience_member_read
  on public.pandora_project_experience_projection;
create policy pandora_project_experience_member_read
  on public.pandora_project_experience_projection
  for select
  to authenticated
  using (private.is_org_member(organization_id));

revoke all on table public.pandora_project_experience_projection from anon;
revoke insert, update, delete on table public.pandora_project_experience_projection from authenticated;
grant select on table public.pandora_project_experience_projection to authenticated;
grant all on table public.pandora_project_experience_projection to service_role;

create index if not exists pandora_project_experience_org_updated_idx
  on public.pandora_project_experience_projection (organization_id, updated_at desc);

create or replace function private.pandora_compute_project_experience_v1(
  p_project_id uuid
)
returns table (
  organization_id uuid,
  project_id uuid,
  experience_state text,
  current_version_id uuid,
  current_preview_deployment_id uuid,
  current_verified boolean,
  candidate_version_id uuid,
  candidate_preview_deployment_id uuid,
  candidate_verification_state text,
  production_version_id uuid,
  production_deployment_id uuid,
  active_build_job_id uuid,
  build_phase text,
  public_message text,
  needs_you boolean,
  retry_available boolean,
  can_focus boolean,
  can_change boolean,
  can_undo boolean,
  can_publish boolean,
  can_rollback boolean,
  verification_summary jsonb,
  change_summary text,
  safe_failure_code text,
  safe_failure_message text
)
language sql
stable
security definer
set search_path = pg_catalog, public, private
as $$
with project_row as (
  select p.id, p.organization_id
  from public.projectos_projects p
  where p.id = p_project_id
),
latest_product_intent as (
  select i.*
  from public.pandora_project_intents i
  where i.project_id = p_project_id
    and i.intent_kind in ('create','build','change')
  order by i.received_at desc, i.id desc
  limit 1
),
latest_spec as (
  select s.*
  from public.pandora_project_specs s
  where s.project_id = p_project_id
  order by s.version desc, s.created_at desc, s.id desc
  limit 1
),
preview_runtime as (
  select r.*
  from public.pandora_runtime_environments r
  where r.project_id = p_project_id
    and r.environment = 'preview'
  limit 1
),
production_runtime as (
  select r.*
  from public.pandora_runtime_environments r
  where r.project_id = p_project_id
    and r.environment = 'production'
  limit 1
),
fallback_current_version as (
  select v.id
  from public.pandora_project_versions v
  where v.project_id = p_project_id
    and v.lifecycle_status in ('live','preview_ready')
  order by
    case v.lifecycle_status when 'live' then 0 else 1 end,
    v.sequence_no desc
  limit 1
),
current_ref as (
  select coalesce(
    (select current_version_id from preview_runtime),
    (select current_version_id from production_runtime),
    (select id from fallback_current_version)
  ) as version_id
),
current_version as (
  select v.*
  from public.pandora_project_versions v
  join current_ref r on r.version_id = v.id
  where v.project_id = p_project_id
  limit 1
),
current_verification as (
  select vr.*
  from public.pandora_verification_runs vr
  join current_version cv on vr.project_version_id = cv.id
  order by
    case when vr.id = cv.verification_run_id then 0 else 1 end,
    vr.created_at desc,
    vr.id desc
  limit 1
),
current_preview_deployment as (
  select d.*
  from public.pandora_project_deployments d
  join current_version cv on d.version_id = cv.id
  left join preview_runtime pr on true
  where d.project_id = p_project_id
    and d.environment = 'preview'
  order by
    case when d.id = pr.current_deployment_id then 0 else 1 end,
    case d.status when 'ready' then 0 when 'ready_for_verification' then 1 else 2 end,
    d.updated_at desc,
    d.id desc
  limit 1
),
production_version as (
  select v.*
  from public.pandora_project_versions v
  join production_runtime r on r.current_version_id = v.id
  where v.project_id = p_project_id
  limit 1
),
production_deployment as (
  select d.*
  from public.pandora_project_deployments d
  join production_version pv on d.version_id = pv.id
  left join production_runtime pr on true
  where d.project_id = p_project_id
    and d.environment = 'production'
  order by
    case when d.id = pr.current_deployment_id then 0 else 1 end,
    case d.status when 'ready' then 0 when 'ready_for_verification' then 1 else 2 end,
    d.updated_at desc,
    d.id desc
  limit 1
),
latest_job as (
  select j.*
  from public.pandora_build_jobs j
  where j.project_id = p_project_id
  order by j.created_at desc, j.id desc
  limit 1
),
active_job as (
  select j.*
  from public.pandora_build_jobs j
  where j.project_id = p_project_id
    and j.status in ('queued','claimed','running','waiting_approval','waiting_verification')
  order by j.created_at desc, j.id desc
  limit 1
),
candidate_version as (
  select v.*
  from public.pandora_project_versions v
  left join current_version cv on true
  left join active_job aj on true
  where v.project_id = p_project_id
    and (cv.id is null or v.id <> cv.id)
    and v.lifecycle_status not in ('live','rolled_back')
    and (
      (aj.target_project_version_id is not null and v.id = aj.target_project_version_id)
      or (
        aj.target_project_version_id is null
        and (cv.sequence_no is null or v.sequence_no > cv.sequence_no)
      )
    )
  order by
    case when aj.target_project_version_id = v.id then 0 else 1 end,
    v.sequence_no desc,
    v.id desc
  limit 1
),
candidate_verification as (
  select vr.*
  from public.pandora_verification_runs vr
  join candidate_version cv on vr.project_version_id = cv.id
  order by
    case when vr.id = cv.verification_run_id then 0 else 1 end,
    vr.created_at desc,
    vr.id desc
  limit 1
),
candidate_preview_deployment as (
  select d.*
  from public.pandora_project_deployments d
  join candidate_version cv on d.version_id = cv.id
  where d.project_id = p_project_id
    and d.environment = 'preview'
  order by
    case d.status when 'ready' then 0 when 'ready_for_verification' then 1 else 2 end,
    d.updated_at desc,
    d.id desc
  limit 1
),
theatre as (
  select t.*
  from public.pandora_build_theatre_projection t
  where t.project_id = p_project_id
  limit 1
),
candidate_checks as (
  select
    count(*)::int as total,
    count(*) filter (where c.status = 'PASS')::int as passed,
    count(*) filter (where c.status = 'FAIL')::int as failed,
    count(*) filter (where c.status = 'BLOCKED')::int as blocked
  from public.pandora_verification_checks c
  join candidate_verification vr on c.verification_run_id = vr.id
),
current_checks as (
  select
    count(*)::int as total,
    count(*) filter (where c.status = 'PASS')::int as passed,
    count(*) filter (where c.status = 'FAIL')::int as failed,
    count(*) filter (where c.status = 'BLOCKED')::int as blocked
  from public.pandora_verification_checks c
  join current_verification vr on c.verification_run_id = vr.id
),
facts as (
  select
    p.organization_id,
    p.id as project_id,
    li.id as latest_intent_id,
    li.intent_kind as latest_intent_kind,
    li.normalized_summary as latest_intent_summary,
    li.intent_text as latest_intent_text,
    li.received_at as latest_intent_received_at,
    ls.id as latest_spec_id,
    ls.source_intent_id as latest_spec_source_intent_id,
    ls.created_at as latest_spec_created_at,
    cv.id as current_version_id,
    cv.sequence_no as current_sequence_no,
    cv.parent_version_id as current_parent_version_id,
    cv.created_at as current_version_created_at,
    cvr.id as current_verification_run_id,
    cvr.status as current_verification_status,
    cpd.id as current_preview_deployment_id,
    cpd.status as current_preview_deployment_status,
    cpd.verification_state as current_preview_verification_state,
    pr.verification_state as preview_runtime_verification_state,
    cand.id as candidate_version_id,
    cand.sequence_no as candidate_sequence_no,
    cand.lifecycle_status as candidate_lifecycle_status,
    cand.created_at as candidate_created_at,
    candvr.id as candidate_verification_run_id,
    candvr.status as candidate_verification_status,
    candpd.id as candidate_preview_deployment_id,
    candpd.status as candidate_preview_deployment_status,
    candpd.verification_state as candidate_preview_verification_state,
    prod.id as production_version_id,
    prod.parent_version_id as production_parent_version_id,
    prod.rollback_eligible as production_rollback_eligible,
    prodd.id as production_deployment_id,
    prodd.promoted_from_id as production_promoted_from_id,
    aj.id as active_build_job_id,
    aj.job_kind as active_job_kind,
    aj.status as active_job_status,
    aj.current_stage as active_job_stage,
    lj.id as latest_job_id,
    lj.status as latest_job_status,
    lj.error_code as latest_job_error_code,
    lj.public_error_summary as latest_job_public_error_summary,
    lj.created_at as latest_job_created_at,
    t.build_job_id as theatre_build_job_id,
    t.needs_you as theatre_needs_you,
    t.retry_available as theatre_retry_available,
    cc.total as candidate_checks_total,
    cc.passed as candidate_checks_passed,
    cc.failed as candidate_checks_failed,
    cc.blocked as candidate_checks_blocked,
    curc.total as current_checks_total,
    curc.passed as current_checks_passed,
    curc.failed as current_checks_failed,
    curc.blocked as current_checks_blocked
  from project_row p
  left join latest_product_intent li on true
  left join latest_spec ls on true
  left join current_version cv on true
  left join current_verification cvr on true
  left join current_preview_deployment cpd on true
  left join preview_runtime pr on true
  left join candidate_version cand on true
  left join candidate_verification candvr on true
  left join candidate_preview_deployment candpd on true
  left join production_version prod on true
  left join production_deployment prodd on true
  left join active_job aj on true
  left join latest_job lj on true
  left join theatre t on true
  left join candidate_checks cc on true
  left join current_checks curc on true
),
normalized as (
  select
    f.*,
    (
      f.latest_intent_id is not null
      and f.latest_spec_source_intent_id is distinct from f.latest_intent_id
    ) as has_uncompiled_intent,
    coalesce(
      f.current_verification_status = 'PASS'
      or f.preview_runtime_verification_state = 'live_verified'
      or f.current_preview_verification_state = 'live_verified',
      false
    ) as is_current_verified,
    case
      when f.candidate_version_id is null then 'not_started'
      when f.candidate_verification_status = 'PASS' then 'passed'
      when f.candidate_verification_status = 'FAIL' then 'failed'
      when f.candidate_verification_status = 'BLOCKED' then 'blocked'
      when f.candidate_lifecycle_status = 'verification_pending'
        or f.active_job_status = 'waiting_verification'
        or f.active_job_stage in ('testing','verifying')
        then 'checking'
      else 'not_started'
    end as normalized_candidate_verification_state,
    case
      when f.active_job_stage = 'publishing' or f.active_job_kind = 'publish' then 'publishing'
      when f.active_job_stage = 'rolling_back' or f.active_job_kind = 'rollback' then 'rolling_back'
      when f.active_job_stage in ('understanding','planning','designing') then 'understanding'
      when f.active_job_stage = 'connecting' then 'connecting'
      when f.active_job_stage in ('testing','verifying') or f.active_job_status = 'waiting_verification' then 'checking'
      when f.active_job_stage in ('previewing','preview_ready') then 'previewing'
      when f.active_job_stage = 'needs_you' or f.active_job_status = 'waiting_approval' then 'needs_you'
      when f.active_build_job_id is not null then 'building'
      else null
    end as normalized_build_phase,
    coalesce(
      f.latest_job_status = 'failed'
      and (
        f.current_version_created_at is null
        or f.latest_job_created_at >= f.current_version_created_at
      ),
      false
    ) as latest_failure_is_relevant,
    (
      f.candidate_preview_deployment_id is not null
      and f.candidate_preview_deployment_status = 'ready'
    ) as candidate_preview_ready
  from facts f
),
stateful as (
  select
    n.*,
    case
      when n.active_build_job_id is not null
        and (n.active_job_stage = 'publishing' or n.active_job_kind = 'publish')
        then 'PUBLISH'
      when n.has_uncompiled_intent
        then 'UNDERSTAND'
      when n.candidate_version_id is not null
        and n.normalized_candidate_verification_state = 'passed'
        and n.candidate_preview_ready
        then 'REVIEW'
      when n.current_version_id is not null
        and (
          n.latest_failure_is_relevant
          or n.normalized_candidate_verification_state in ('failed','blocked')
        )
        then 'LIVE'
      when n.current_version_id is not null
        and (n.active_build_job_id is not null or n.candidate_version_id is not null)
        then 'REBUILD'
      when n.current_version_id is null
        and (
          n.active_build_job_id is not null
          or n.candidate_version_id is not null
          or n.latest_spec_id is not null
        )
        then 'BUILD'
      when n.current_version_id is not null or n.production_version_id is not null
        then 'LIVE'
      when n.latest_intent_id is not null
        then 'UNDERSTAND'
      else 'START'
    end as normalized_experience_state
  from normalized n
)
select
  s.organization_id,
  s.project_id,
  s.normalized_experience_state as experience_state,
  s.current_version_id,
  s.current_preview_deployment_id,
  s.is_current_verified as current_verified,
  s.candidate_version_id,
  s.candidate_preview_deployment_id,
  s.normalized_candidate_verification_state as candidate_verification_state,
  s.production_version_id,
  s.production_deployment_id,
  s.active_build_job_id,
  s.normalized_build_phase as build_phase,
  case
    when s.normalized_experience_state = 'START' then 'What do you want to build?'
    when s.normalized_experience_state = 'UNDERSTAND'
      and s.current_version_id is not null then 'Understanding your change'
    when s.normalized_experience_state = 'UNDERSTAND' then 'Understanding your request'
    when s.normalized_experience_state = 'PUBLISH' then 'Publishing your project'
    when s.normalized_experience_state = 'REVIEW' then 'Change verified'
    when s.normalized_experience_state = 'REBUILD'
      and s.normalized_build_phase = 'checking' then 'Making sure it works'
    when s.normalized_experience_state = 'REBUILD' then 'Updating your project'
    when s.normalized_experience_state = 'BUILD'
      and s.normalized_build_phase = 'checking' then 'Making sure it works'
    when s.normalized_experience_state = 'BUILD' then 'Building the experience'
    when s.normalized_experience_state = 'LIVE'
      and (
        s.latest_failure_is_relevant
        or s.normalized_candidate_verification_state in ('failed','blocked')
      )
      then 'Your current version is still safe'
    else 'Live'
  end as public_message,
  (
    coalesce(s.active_job_stage = 'needs_you', false)
    or coalesce(s.active_job_status = 'waiting_approval', false)
    or (
      s.active_build_job_id is not null
      and s.theatre_build_job_id = s.active_build_job_id
      and coalesce(s.theatre_needs_you, false)
    )
  ) as needs_you,
  (
    coalesce(s.latest_failure_is_relevant, false)
    or s.normalized_candidate_verification_state in ('failed','blocked')
    or (
      s.active_build_job_id is not null
      and s.theatre_build_job_id = s.active_build_job_id
      and coalesce(s.theatre_retry_available, false)
    )
  ) as retry_available,
  (s.current_version_id is not null) as can_focus,
  (
    s.current_version_id is not null
    and s.normalized_experience_state <> 'PUBLISH'
    and coalesce(s.normalized_build_phase, '') <> 'rolling_back'
  ) as can_change,
  (
    s.current_version_id is not null
    and s.current_parent_version_id is not null
    and s.normalized_experience_state <> 'PUBLISH'
    and coalesce(s.normalized_build_phase, '') <> 'rolling_back'
  ) as can_undo,
  (
    (
      s.candidate_version_id is not null
      and s.normalized_candidate_verification_state = 'passed'
      and s.candidate_preview_ready
    )
    or (
      s.current_version_id is not null
      and s.is_current_verified
      and s.current_version_id is distinct from s.production_version_id
    )
  ) as can_publish,
  (
    s.production_version_id is not null
    and (
      coalesce(s.production_rollback_eligible, false)
      or s.production_parent_version_id is not null
      or s.production_promoted_from_id is not null
    )
  ) as can_rollback,
  case
    when s.candidate_verification_run_id is not null then
      jsonb_build_object(
        'runId', s.candidate_verification_run_id,
        'status', s.candidate_verification_status,
        'verified', s.candidate_verification_status = 'PASS',
        'checks', jsonb_build_object(
          'total', coalesce(s.candidate_checks_total,0),
          'passed', coalesce(s.candidate_checks_passed,0),
          'failed', coalesce(s.candidate_checks_failed,0),
          'blocked', coalesce(s.candidate_checks_blocked,0)
        )
      )
    when s.current_verification_run_id is not null then
      jsonb_build_object(
        'runId', s.current_verification_run_id,
        'status', s.current_verification_status,
        'verified', s.current_verification_status = 'PASS',
        'checks', jsonb_build_object(
          'total', coalesce(s.current_checks_total,0),
          'passed', coalesce(s.current_checks_passed,0),
          'failed', coalesce(s.current_checks_failed,0),
          'blocked', coalesce(s.current_checks_blocked,0)
        )
      )
    else jsonb_build_object(
      'runId', null,
      'status', 'NOT_RUN',
      'verified', false,
      'checks', jsonb_build_object('total',0,'passed',0,'failed',0,'blocked',0)
    )
  end as verification_summary,
  case
    when s.latest_intent_id is null then null
    else left(coalesce(nullif(trim(s.latest_intent_summary),''), s.latest_intent_text), 280)
  end as change_summary,
  case
    when s.latest_failure_is_relevant then coalesce(s.latest_job_error_code,'build_failed')
    when s.normalized_candidate_verification_state = 'failed' then 'verification_failed'
    when s.normalized_candidate_verification_state = 'blocked' then 'verification_blocked'
    else null
  end as safe_failure_code,
  case
    when s.latest_failure_is_relevant then
      coalesce(nullif(trim(s.latest_job_public_error_summary),''),
        case when s.current_version_id is not null
          then 'The latest change could not be completed. Your current version is still safe.'
          else 'The build could not be completed. You can retry.'
        end)
    when s.normalized_candidate_verification_state = 'failed' then
      case when s.current_version_id is not null
        then 'The latest change did not pass verification. Your current version is still safe.'
        else 'The build did not pass verification. You can retry.'
      end
    when s.normalized_candidate_verification_state = 'blocked' then
      'Verification needs attention before this version can be accepted.'
    else null
  end as safe_failure_message
from stateful s;
$$;

revoke all on function private.pandora_compute_project_experience_v1(uuid) from public;
grant execute on function private.pandora_compute_project_experience_v1(uuid) to service_role;

create or replace function private.pandora_refresh_project_experience_projection_v1(
  p_project_id uuid
)
returns void
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_next record;
  v_current public.pandora_project_experience_projection%rowtype;
  v_current_payload jsonb;
  v_next_payload jsonb;
begin
  select * into v_next
  from private.pandora_compute_project_experience_v1(p_project_id);

  if not found then
    delete from public.pandora_project_experience_projection
    where project_id = p_project_id;
    return;
  end if;

  select * into v_current
  from public.pandora_project_experience_projection
  where project_id = p_project_id
  for update;

  if not found then
    insert into public.pandora_project_experience_projection (
      organization_id,
      project_id,
      experience_state,
      transition_sequence,
      current_version_id,
      current_preview_deployment_id,
      current_verified,
      candidate_version_id,
      candidate_preview_deployment_id,
      candidate_verification_state,
      production_version_id,
      production_deployment_id,
      active_build_job_id,
      build_phase,
      public_message,
      needs_you,
      retry_available,
      can_focus,
      can_change,
      can_undo,
      can_publish,
      can_rollback,
      verification_summary,
      change_summary,
      safe_failure_code,
      safe_failure_message,
      last_transition_at,
      updated_at
    ) values (
      v_next.organization_id,
      v_next.project_id,
      v_next.experience_state,
      1,
      v_next.current_version_id,
      v_next.current_preview_deployment_id,
      v_next.current_verified,
      v_next.candidate_version_id,
      v_next.candidate_preview_deployment_id,
      v_next.candidate_verification_state,
      v_next.production_version_id,
      v_next.production_deployment_id,
      v_next.active_build_job_id,
      v_next.build_phase,
      v_next.public_message,
      v_next.needs_you,
      v_next.retry_available,
      v_next.can_focus,
      v_next.can_change,
      v_next.can_undo,
      v_next.can_publish,
      v_next.can_rollback,
      v_next.verification_summary,
      v_next.change_summary,
      v_next.safe_failure_code,
      v_next.safe_failure_message,
      now(),
      now()
    );
    return;
  end if;

  v_current_payload := to_jsonb(v_current) - array[
    'transition_sequence','last_transition_at','updated_at'
  ]::text[];
  v_next_payload := to_jsonb(v_next);

  if v_current_payload is not distinct from v_next_payload then
    return;
  end if;

  update public.pandora_project_experience_projection
  set
    organization_id = v_next.organization_id,
    experience_state = v_next.experience_state,
    transition_sequence = transition_sequence + 1,
    current_version_id = v_next.current_version_id,
    current_preview_deployment_id = v_next.current_preview_deployment_id,
    current_verified = v_next.current_verified,
    candidate_version_id = v_next.candidate_version_id,
    candidate_preview_deployment_id = v_next.candidate_preview_deployment_id,
    candidate_verification_state = v_next.candidate_verification_state,
    production_version_id = v_next.production_version_id,
    production_deployment_id = v_next.production_deployment_id,
    active_build_job_id = v_next.active_build_job_id,
    build_phase = v_next.build_phase,
    public_message = v_next.public_message,
    needs_you = v_next.needs_you,
    retry_available = v_next.retry_available,
    can_focus = v_next.can_focus,
    can_change = v_next.can_change,
    can_undo = v_next.can_undo,
    can_publish = v_next.can_publish,
    can_rollback = v_next.can_rollback,
    verification_summary = v_next.verification_summary,
    change_summary = v_next.change_summary,
    safe_failure_code = v_next.safe_failure_code,
    safe_failure_message = v_next.safe_failure_message,
    last_transition_at = now(),
    updated_at = now()
  where project_id = p_project_id;
end;
$$;

revoke all on function private.pandora_refresh_project_experience_projection_v1(uuid) from public;
grant execute on function private.pandora_refresh_project_experience_projection_v1(uuid) to service_role;

create or replace function private.pandora_project_experience_touch_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private
as $$
declare
  v_project_id uuid;
begin
  if tg_table_name = 'projectos_projects' then
    if tg_op = 'DELETE' then
      v_project_id := old.id;
    else
      v_project_id := new.id;
    end if;
  else
    if tg_op = 'DELETE' then
      v_project_id := old.project_id;
    else
      v_project_id := new.project_id;
    end if;
  end if;

  perform private.pandora_refresh_project_experience_projection_v1(v_project_id);

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function private.pandora_project_experience_touch_v1() from public;

drop trigger if exists pandora_project_experience_project_touch on public.projectos_projects;
create trigger pandora_project_experience_project_touch
after insert or update on public.projectos_projects
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_intent_touch on public.pandora_project_intents;
create trigger pandora_project_experience_intent_touch
after insert or update or delete on public.pandora_project_intents
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_spec_touch on public.pandora_project_specs;
create trigger pandora_project_experience_spec_touch
after insert or update or delete on public.pandora_project_specs
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_version_touch on public.pandora_project_versions;
create trigger pandora_project_experience_version_touch
after insert or update or delete on public.pandora_project_versions
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_job_touch on public.pandora_build_jobs;
create trigger pandora_project_experience_job_touch
after insert or update or delete on public.pandora_build_jobs
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_theatre_touch on public.pandora_build_theatre_projection;
create trigger pandora_project_experience_theatre_touch
after insert or update or delete on public.pandora_build_theatre_projection
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_deployment_touch on public.pandora_project_deployments;
create trigger pandora_project_experience_deployment_touch
after insert or update or delete on public.pandora_project_deployments
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_verification_run_touch on public.pandora_verification_runs;
create trigger pandora_project_experience_verification_run_touch
after insert or update or delete on public.pandora_verification_runs
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_verification_check_touch on public.pandora_verification_checks;
create trigger pandora_project_experience_verification_check_touch
after insert or update or delete on public.pandora_verification_checks
for each row execute function private.pandora_project_experience_touch_v1();

drop trigger if exists pandora_project_experience_runtime_touch on public.pandora_runtime_environments;
create trigger pandora_project_experience_runtime_touch
after insert or update or delete on public.pandora_runtime_environments
for each row execute function private.pandora_project_experience_touch_v1();

do $$
declare
  r record;
begin
  for r in
    select p.id
    from public.projectos_projects p
    order by p.created_at, p.id
  loop
    perform private.pandora_refresh_project_experience_projection_v1(r.id);
  end loop;
end;
$$;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'pandora_project_experience_projection'
  ) then
    alter publication supabase_realtime
      add table public.pandora_project_experience_projection;
  end if;
end;
$$;

-- Fail closed on impossible customer-facing states after backfill.
do $$
begin
  if exists (
    select 1
    from public.pandora_project_experience_projection
    where experience_state = 'LIVE'
      and current_version_id is null
      and production_version_id is null
  ) then
    raise exception 'Experience projection invariant failed: LIVE without a current or production version';
  end if;

  if exists (
    select 1
    from public.pandora_project_experience_projection
    where experience_state = 'REVIEW'
      and (
        candidate_version_id is null
        or candidate_verification_state <> 'passed'
      )
  ) then
    raise exception 'Experience projection invariant failed: REVIEW without a verified candidate';
  end if;

  if exists (
    select 1
    from public.pandora_project_experience_projection
    where can_publish
      and not (candidate_verification_state = 'passed' or current_verified)
  ) then
    raise exception 'Experience projection invariant failed: publish enabled without verified exact target';
  end if;

  if exists (
    select 1
    from public.pandora_project_experience_projection
    where candidate_version_id is not null
      and candidate_version_id = current_version_id
  ) then
    raise exception 'Experience projection invariant failed: candidate equals current version';
  end if;
end;
$$;
