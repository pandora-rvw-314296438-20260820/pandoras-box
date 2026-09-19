-- Pandora Visible Creation — Conversation Evidence Spine
-- Derived customer-safe history projection over canonical lifecycle truth.

begin;

create or replace function public.pandora_get_project_conversation_v1(
  p_project_id uuid,
  p_limit integer default 30,
  p_before_occurred_at timestamptz default null,
  p_before_item_id text default null
)
returns table (
  conversation_item_id text,
  project_id uuid,
  organization_id uuid,
  kind text,
  occurred_at timestamptz,
  actor_type text,
  title text,
  summary text,
  status text,
  source_type text,
  source_id text,
  source_intent_id uuid,
  project_spec_id uuid,
  build_authorization_id uuid,
  build_job_id uuid,
  project_version_id uuid,
  verification_run_id uuid,
  deployment_id uuid,
  expandable boolean,
  evidence_available boolean,
  display_payload jsonb
)
language plpgsql
stable
security definer
set search_path = 'pg_catalog', 'public'
as $fn$
declare
  v_user_id uuid := auth.uid();
  v_organization_id uuid;
  v_limit integer := greatest(1, least(coalesce(p_limit, 30), 100));
begin
  if v_user_id is null then
    raise exception 'SIGN_IN_REQUIRED' using errcode = '42501';
  end if;
  if p_project_id is null then
    raise exception 'PROJECT_REQUIRED' using errcode = '22023';
  end if;
  if (p_before_occurred_at is null) <> (p_before_item_id is null) then
    raise exception 'INVALID_CONVERSATION_CURSOR' using errcode = '22023';
  end if;

  select p.organization_id into v_organization_id
  from public.projectos_projects p
  where p.id = p_project_id;

  if v_organization_id is null then
    raise exception 'PROJECT_NOT_FOUND' using errcode = 'P0002';
  end if;

  if not exists (
    select 1
    from public.memberships m
    where m.organization_id = v_organization_id
      and m.user_id = v_user_id
      and m.status::text = 'active'
  ) then
    raise exception 'ORGANIZATION_ACCESS_REQUIRED' using errcode = '42501';
  end if;

  return query
  with intent_items as (
    select
      'intent:' || i.id::text as conversation_item_id,
      i.project_id,
      i.organization_id,
      case when i.intent_kind = 'change' then 'USER_CHANGE_INTENT' else 'USER_INTENT' end::text as kind,
      i.received_at as occurred_at,
      'user'::text as actor_type,
      case
        when i.intent_kind = 'create' then 'Your request'
        when i.intent_kind = 'change' then 'Change requested'
        when i.intent_kind = 'repair' then 'Repair requested'
        else 'Request'
      end::text as title,
      coalesce(nullif(i.normalized_summary, ''), left(i.intent_text, 240))::text as summary,
      null::text as status,
      'project_intent'::text as source_type,
      i.id::text as source_id,
      i.id as source_intent_id,
      null::uuid as project_spec_id,
      null::uuid as build_authorization_id,
      null::uuid as build_job_id,
      null::uuid as project_version_id,
      null::uuid as verification_run_id,
      null::uuid as deployment_id,
      (length(i.intent_text) > 280)::boolean as expandable,
      true::boolean as evidence_available,
      jsonb_build_object(
        'intentKind', i.intent_kind,
        'intentText', i.intent_text
      ) as display_payload
    from public.pandora_project_intents i
    where i.organization_id = v_organization_id
      and i.project_id = p_project_id
      and i.source = 'customer'
  ),
  proposal_items as (
    select
      'proposal:' || s.id::text,
      s.project_id,
      s.organization_id,
      'PANDORA_PROPOSAL'::text,
      s.created_at,
      'pandora'::text,
      'Project proposal'::text,
      coalesce(nullif(s.business_summary, ''), nullif(i.normalized_summary, ''), 'Proposal ready for review')::text,
      case s.status
        when 'active' then 'Ready'
        when 'superseded' then 'Superseded'
        when 'rejected' then 'Problem'
        else 'Working'
      end::text,
      'project_spec'::text,
      s.id::text,
      s.source_intent_id,
      s.id,
      null::uuid,
      null::uuid,
      null::uuid,
      null::uuid,
      null::uuid,
      true::boolean,
      true::boolean,
      jsonb_strip_nulls(jsonb_build_object(
        'proposalVersion', s.version,
        'businessSummary', s.business_summary,
        'targetUserSummary', s.target_user_summary
      ))
    from public.pandora_project_specs s
    join public.pandora_project_intents i
      on i.id = s.source_intent_id
     and i.organization_id = s.organization_id
     and i.project_id = s.project_id
    where s.organization_id = v_organization_id
      and s.project_id = p_project_id
  ),
  build_authorization_items as (
    select
      'build-authorization:' || r.id::text,
      r.project_id,
      r.organization_id,
      'USER_BUILD_AUTHORIZATION'::text,
      r.authorized_at,
      'user'::text,
      'Build it'::text,
      'Build authorized for the approved proposal.'::text,
      'Ready'::text,
      'build_authorization'::text,
      r.id::text,
      r.source_intent_id,
      r.project_spec_id,
      r.id,
      r.build_job_id,
      null::uuid,
      null::uuid,
      null::uuid,
      false::boolean,
      true::boolean,
      jsonb_build_object(
        'authorizedAt', r.authorized_at,
        'admitted', r.build_job_id is not null,
        'publishAuthorized', false
      )
    from public.pandora_build_authorization_receipts r
    join public.pandora_project_specs s
      on s.id = r.project_spec_id
     and s.organization_id = r.organization_id
     and s.project_id = r.project_id
     and s.source_intent_id = r.source_intent_id
     and s.content_sha256 = r.approved_spec_sha256
    join public.pandora_project_intents i
      on i.id = r.source_intent_id
     and i.organization_id = r.organization_id
     and i.project_id = r.project_id
    where r.organization_id = v_organization_id
      and r.project_id = p_project_id
  ),
  build_items as (
    select
      'build-job:' || j.id::text,
      j.project_id,
      j.organization_id,
      case
        when j.job_kind = 'repair' then 'REPAIR_SUMMARY'
        when j.job_kind = 'build' then 'BUILD_ADMITTED'
        else 'BUILD_ACTIVITY_SUMMARY'
      end::text,
      j.created_at,
      case when j.requested_by is null then 'pandora' else 'user' end::text,
      case
        when j.job_kind = 'repair' then 'Repair'
        when j.job_kind = 'build' then 'Build'
        else initcap(j.job_kind)
      end::text,
      case
        when j.status = 'succeeded' and j.job_kind = 'repair' then 'Repair completed.'
        when j.status = 'succeeded' and j.job_kind = 'build' then 'Build completed.'
        when j.status = 'failed' then coalesce(nullif(j.public_error_summary, ''), 'Build activity stopped with a problem.')
        else coalesce(nullif(j.public_error_summary, ''), initcap(replace(j.current_stage, '_', ' ')))
      end::text,
      case
        when j.status = 'succeeded' then 'Ready'
        when j.status in ('failed','cancelled') then 'Problem'
        when j.status = 'waiting_approval' then 'Needs You'
        else 'Working'
      end::text,
      'build_job'::text,
      j.id::text,
      coalesce(j.source_intent_id, s.source_intent_id),
      j.project_spec_id,
      r.id,
      j.id,
      j.target_project_version_id,
      null::uuid,
      null::uuid,
      true::boolean,
      true::boolean,
      jsonb_strip_nulls(jsonb_build_object(
        'jobKind', j.job_kind,
        'stage', j.current_stage,
        'completedAt', j.completed_at
      ))
    from public.pandora_build_jobs j
    join public.pandora_project_specs s
      on s.id = j.project_spec_id
     and s.organization_id = j.organization_id
     and s.project_id = j.project_id
    left join public.pandora_build_authorization_receipts r
      on r.build_job_id = j.id
     and r.organization_id = j.organization_id
     and r.project_id = j.project_id
     and r.project_spec_id = j.project_spec_id
     and r.source_intent_id = coalesce(j.source_intent_id, s.source_intent_id)
    where j.organization_id = v_organization_id
      and j.project_id = p_project_id
      and j.job_kind in ('build','repair')
      and (j.source_intent_id is null or j.source_intent_id = s.source_intent_id)
  ),
  verification_items as (
    select
      'verification:' || vr.id::text,
      vr.project_id,
      vr.organization_id,
      'VERIFICATION_RECEIPT'::text,
      vr.created_at,
      'pandora'::text,
      case when vr.status = 'PASS' then 'Verification passed' else 'Verification' end::text,
      case
        when vr.status = 'PASS' then
          concat(c.total_count, ' checks · ', c.pass_count, ' passed')
        when vr.status = 'FAIL' then
          concat(c.fail_count, ' checks failed')
        when vr.status = 'BLOCKED' then
          concat(c.blocked_count, ' checks blocked')
        else 'Checks are running'
      end::text,
      case
        when vr.status = 'PASS' then 'Ready'
        when vr.status in ('FAIL','BLOCKED') then 'Problem'
        else 'Working'
      end::text,
      'verification_run'::text,
      vr.id::text,
      s.source_intent_id,
      vr.project_spec_id,
      r.id,
      vr.build_job_id,
      vr.project_version_id,
      vr.id,
      null::uuid,
      true::boolean,
      exists (
        select 1
        from public.pandora_verification_evidence e
        where e.organization_id = vr.organization_id
          and e.project_id = vr.project_id
          and e.verification_run_id = vr.id
      )::boolean,
      jsonb_build_object(
        'checksTotal', c.total_count,
        'checksPassed', c.pass_count,
        'checksFailed', c.fail_count,
        'checksBlocked', c.blocked_count,
        'target', case when vr.target_environment = 'production' then 'Live' else 'Preview' end
      )
    from public.pandora_verification_runs vr
    join public.pandora_project_versions v
      on v.id = vr.project_version_id
     and v.organization_id = vr.organization_id
     and v.project_id = vr.project_id
     and v.project_spec_id = vr.project_spec_id
    join public.pandora_project_specs s
      on s.id = vr.project_spec_id
     and s.organization_id = vr.organization_id
     and s.project_id = vr.project_id
    left join public.pandora_build_authorization_receipts r
      on r.build_job_id = vr.build_job_id
     and r.organization_id = vr.organization_id
     and r.project_id = vr.project_id
     and r.project_spec_id = vr.project_spec_id
    cross join lateral (
      select
        count(*)::int as total_count,
        count(*) filter (where vc.status = 'PASS')::int as pass_count,
        count(*) filter (where vc.status = 'FAIL')::int as fail_count,
        count(*) filter (where vc.status = 'BLOCKED')::int as blocked_count
      from public.pandora_verification_checks vc
      where vc.organization_id = vr.organization_id
        and vc.project_id = vr.project_id
        and vc.verification_run_id = vr.id
    ) c
    where vr.organization_id = v_organization_id
      and vr.project_id = p_project_id
  ),
  preview_items as (
    select
      'preview:' || d.id::text,
      d.project_id,
      d.organization_id,
      'PREVIEW_READY'::text,
      d.created_at,
      'pandora'::text,
      'Preview ready'::text,
      'Working result is ready for review.'::text,
      case
        when d.status = 'ready' then 'Ready'
        when d.status in ('failed','cancelled') then 'Problem'
        else 'Working'
      end::text,
      'project_deployment'::text,
      d.id::text,
      s.source_intent_id,
      v.project_spec_id,
      r.id,
      v.build_job_id,
      v.id,
      v.verification_run_id,
      d.id,
      true::boolean,
      (d.verification_ref is not null or v.verification_run_id is not null)::boolean,
      jsonb_build_object(
        'verificationState', d.verification_state,
        'readyAt', d.ready_at
      )
    from public.pandora_project_deployments d
    join public.pandora_project_versions v
      on v.id = d.version_id
     and v.organization_id = d.organization_id
     and v.project_id = d.project_id
     and v.source_sha256 = d.source_sha256
    join public.pandora_project_specs s
      on s.id = v.project_spec_id
     and s.organization_id = d.organization_id
     and s.project_id = d.project_id
    left join public.pandora_build_authorization_receipts r
      on r.build_job_id = v.build_job_id
     and r.organization_id = d.organization_id
     and r.project_id = d.project_id
     and r.project_spec_id = v.project_spec_id
    where d.organization_id = v_organization_id
      and d.project_id = p_project_id
      and d.environment = 'preview'
      and d.status in ('ready','failed','cancelled')
  ),
  publish_items as (
    select
      'publish:' || pr.id::text,
      pr.project_id,
      pr.organization_id,
      'PUBLISH_RECEIPT'::text,
      pr.created_at,
      'pandora'::text,
      case when pr.status = 'live_verified' then 'Live · Verified' else 'Publish' end::text,
      case
        when pr.status = 'live_verified' then concat('Published version ', v.sequence_no, ' and verified live.')
        when pr.status = 'failed' then 'Publish did not complete.'
        else 'Publishing and checking the live result.'
      end::text,
      case
        when pr.status = 'live_verified' then 'Live'
        when pr.status = 'failed' then 'Problem'
        else 'Working'
      end::text,
      'publish_receipt'::text,
      pr.id::text,
      s.source_intent_id,
      v.project_spec_id,
      r.id,
      v.build_job_id,
      v.id,
      v.verification_run_id,
      pr.production_deployment_id,
      true::boolean,
      true::boolean,
      jsonb_strip_nulls(jsonb_build_object(
        'version', v.sequence_no,
        'publishedAt', pr.published_at,
        'previousVersionId', pr.previous_production_version_id
      ))
    from public.pandora_publish_receipts pr
    join public.pandora_project_versions v
      on v.id = pr.version_id
     and v.organization_id = pr.organization_id
     and v.project_id = pr.project_id
    join public.pandora_project_specs s
      on s.id = v.project_spec_id
     and s.organization_id = pr.organization_id
     and s.project_id = pr.project_id
    join public.pandora_project_deployments d
      on d.id = pr.production_deployment_id
     and d.organization_id = pr.organization_id
     and d.project_id = pr.project_id
     and d.version_id = pr.version_id
     and d.environment = 'production'
    left join public.pandora_build_authorization_receipts r
      on r.build_job_id = v.build_job_id
     and r.organization_id = pr.organization_id
     and r.project_id = pr.project_id
     and r.project_spec_id = v.project_spec_id
    where pr.organization_id = v_organization_id
      and pr.project_id = p_project_id
      and (pr.source_sha256 is null or pr.source_sha256 = v.source_sha256)
      and not exists (
        select 1
        from public.pandora_tool_calls rollback_call
        where rollback_call.organization_id = pr.organization_id
          and rollback_call.project_id = pr.project_id
          and rollback_call.tool_name = 'rollback_project'
          and rollback_call.tool_version = '1'
          and rollback_call.action_hash is not null
          and d.authorization_ref = 'worker-c:' || rollback_call.action_hash
      )
  ),
  undo_items as (
    select
      'undo:' || tc.id::text,
      tc.project_id,
      tc.organization_id,
      'UNDO_RECEIPT'::text,
      pr.created_at,
      'user'::text,
      'Undo completed'::text,
      concat('Restored verified version ', v.sequence_no, '.')::text,
      'Live'::text,
      'publish_receipt'::text,
      pr.id::text,
      s.source_intent_id,
      tc.project_spec_id,
      null::uuid,
      tc.build_job_id,
      tc.project_version_id,
      vr.id,
      d.id,
      true::boolean,
      true::boolean,
      jsonb_build_object(
        'restoredVersion', v.sequence_no,
        'previousVersion', previous_v.sequence_no,
        'verified', true
      )
    from public.pandora_tool_calls tc
    join public.pandora_project_versions v
      on v.id = tc.project_version_id
     and v.organization_id = tc.organization_id
     and v.project_id = tc.project_id
     and v.project_spec_id = tc.project_spec_id
    join public.pandora_project_specs s
      on s.id = tc.project_spec_id
     and s.organization_id = tc.organization_id
     and s.project_id = tc.project_id
    join public.pandora_runtime_environments env
      on env.organization_id = tc.organization_id
     and env.project_id = tc.project_id
     and env.environment = 'production'
     and env.current_version_id = tc.project_version_id
     and env.verification_state = 'live_verified'
    join public.pandora_project_deployments d
      on d.id = env.current_deployment_id
     and d.organization_id = tc.organization_id
     and d.project_id = tc.project_id
     and d.version_id = tc.project_version_id
     and d.environment = 'production'
     and d.authorization_ref = 'worker-c:' || tc.action_hash
    join public.pandora_publish_receipts pr
      on pr.production_deployment_id = d.id
     and pr.organization_id = tc.organization_id
     and pr.project_id = tc.project_id
     and pr.version_id = tc.project_version_id
     and pr.status = 'live_verified'
     and pr.previous_production_version_id is not null
     and pr.previous_production_version_id <> tc.project_version_id
    join public.pandora_project_versions previous_v
      on previous_v.id = pr.previous_production_version_id
     and previous_v.organization_id = tc.organization_id
     and previous_v.project_id = tc.project_id
    join public.pandora_verification_runs vr
      on vr.id = v.verification_run_id
     and vr.organization_id = tc.organization_id
     and vr.project_id = tc.project_id
     and vr.project_version_id = tc.project_version_id
     and vr.project_spec_id = tc.project_spec_id
     and vr.status = 'PASS'
    where tc.organization_id = v_organization_id
      and tc.project_id = p_project_id
      and tc.tool_name = 'rollback_project'
      and tc.tool_version = '1'
      and tc.status = 'succeeded'
      and tc.decision = 'ALLOW'
      and tc.environment = 'production'
  ),
  all_items as (
    select * from intent_items
    union all select * from proposal_items
    union all select * from build_authorization_items
    union all select * from build_items
    union all select * from verification_items
    union all select * from preview_items
    union all select * from publish_items
    union all select * from undo_items
  ),
  selected as (
    select *
    from all_items ai
    where p_before_occurred_at is null
       or (ai.occurred_at, ai.conversation_item_id)
          < (p_before_occurred_at, p_before_item_id)
    order by ai.occurred_at desc, ai.conversation_item_id desc
    limit v_limit
  )
  select
    s.conversation_item_id,
    s.project_id,
    s.organization_id,
    s.kind,
    s.occurred_at,
    s.actor_type,
    s.title,
    s.summary,
    s.status,
    s.source_type,
    s.source_id,
    s.source_intent_id,
    s.project_spec_id,
    s.build_authorization_id,
    s.build_job_id,
    s.project_version_id,
    s.verification_run_id,
    s.deployment_id,
    s.expandable,
    s.evidence_available,
    s.display_payload
  from selected s
  order by s.occurred_at asc, s.conversation_item_id asc;
end;
$fn$;

revoke all on function public.pandora_get_project_conversation_v1(uuid, integer, timestamptz, text)
  from public, anon;
grant execute on function public.pandora_get_project_conversation_v1(uuid, integer, timestamptz, text)
  to authenticated;

comment on function public.pandora_get_project_conversation_v1(uuid, integer, timestamptz, text) is
  'Customer-safe chronological evidence projection. Uses stable keyset pagination and never owns build/version/deployment truth.';

commit;
