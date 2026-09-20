-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create or replace function public.projectos_register_project(
  p_organization_id uuid,
  p_project_key text,
  p_name text,
  p_repository text default null,
  p_objective text default '',
  p_created_by uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project public.projectos_projects%rowtype;
  v_key text := lower(trim(p_project_key));
  v_document_key text;
begin
  if auth.role() <> 'service_role' and not private.has_org_role(p_organization_id, array['owner','admin','operator']::member_role[]) then
    raise exception 'projectos_forbidden';
  end if;
  if v_key !~ '^[a-z0-9][a-z0-9._-]{0,79}$' then raise exception 'invalid_project_key'; end if;

  insert into public.projectos_projects (
    organization_id, project_key, name, repository, workspace_path, objective, created_by
  ) values (
    p_organization_id, v_key, trim(p_name), nullif(trim(p_repository), ''),
    'projectos/projects/' || v_key, coalesce(p_objective, ''), p_created_by
  )
  on conflict (organization_id, project_key) do update set
    name = excluded.name,
    repository = coalesce(excluded.repository, projectos_projects.repository),
    objective = case when excluded.objective <> '' then excluded.objective else projectos_projects.objective end
  returning * into v_project;

  foreach v_document_key in array array[
    'identity','objectives','architecture','roadmap','tasks','decisions','risks','integrations',
    'deployments','analytics','evidence','audit','lessons','current_state','next_action'
  ] loop
    insert into public.projectos_workspace_documents (
      organization_id, project_id, document_key, content
    ) values (
      p_organization_id, v_project.id, v_document_key,
      jsonb_build_object('projectKey', v_project.project_key, 'status', 'initialized')
    ) on conflict (project_id, document_key) do nothing;
  end loop;

  return to_jsonb(v_project);
end;
$$;

create or replace function public.projectos_accept_intake(
  p_organization_id uuid,
  p_requester_id uuid,
  p_request_text text,
  p_project_key text default null,
  p_project_name text default null,
  p_repository text default null,
  p_request_type text default 'work',
  p_source text default 'operator',
  p_idempotency_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project public.projectos_projects%rowtype;
  v_intake public.projectos_intake_requests%rowtype;
  v_key text;
  v_policy public.projectos_policies%rowtype;
begin
  if auth.role() <> 'service_role' and not private.is_org_member(p_organization_id) then
    raise exception 'projectos_forbidden';
  end if;
  if p_requester_id is not null and auth.role() <> 'service_role' and p_requester_id <> auth.uid() then
    raise exception 'projectos_requester_mismatch';
  end if;

  select * into v_policy from public.projectos_policies where organization_id = p_organization_id;
  if found and v_policy.allow_untracked_work then raise exception 'invalid_projectos_policy'; end if;

  if p_project_key is not null and trim(p_project_key) <> '' then
    v_key := lower(trim(p_project_key));
  elsif p_repository is not null and trim(p_repository) <> '' then
    v_key := lower(regexp_replace(split_part(p_repository, '/', 2), '[^a-zA-Z0-9._-]+', '-', 'g'));
  elsif p_project_name is not null and trim(p_project_name) <> '' then
    v_key := lower(regexp_replace(trim(p_project_name), '[^a-zA-Z0-9._-]+', '-', 'g'));
  else
    v_key := 'projectos-inbox';
  end if;

  select * into v_project
  from public.projectos_projects
  where organization_id = p_organization_id
    and (project_key = v_key or (p_repository is not null and repository = p_repository))
  order by case when project_key = v_key then 0 else 1 end
  limit 1;

  if not found then
    perform public.projectos_register_project(
      p_organization_id,
      v_key,
      coalesce(nullif(trim(p_project_name), ''), initcap(replace(v_key, '-', ' '))),
      p_repository,
      'Automatically created by mandatory ProjectOS intake.',
      p_requester_id
    );
    select * into v_project from public.projectos_projects
      where organization_id = p_organization_id and project_key = v_key;
  end if;

  insert into public.projectos_intake_requests (
    organization_id, project_id, requester_id, source, request_type, request_text,
    project_hint, repository_hint, idempotency_key, status,
    analysis
  ) values (
    p_organization_id, v_project.id, p_requester_id, p_source, p_request_type,
    p_request_text, v_key, p_repository,
    coalesce(nullif(p_idempotency_key, ''), encode(digest(p_organization_id::text || ':' || p_request_text, 'sha256'), 'hex')),
    'accepted',
    jsonb_build_object(
      'workspacePath', v_project.workspace_path,
      'mandatoryControlLayer', true,
      'nextAction', 'analyze_current_state'
    )
  )
  on conflict (organization_id, idempotency_key) do update set
    project_id = excluded.project_id
  returning * into v_intake;

  return jsonb_build_object('intake', to_jsonb(v_intake), 'project', to_jsonb(v_project));
end;
$$;

create or replace function public.projectos_record_external_event(
  p_organization_id uuid,
  p_provider text,
  p_delivery_id text,
  p_event_type text,
  p_payload_hash text,
  p_payload_redacted jsonb default '{}'::jsonb,
  p_project_key text default null,
  p_repository text default null,
  p_external_created_at timestamptz default null
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project_id uuid;
  v_event public.projectos_external_events%rowtype;
begin
  perform private.assert_control_service_role();
  select id into v_project_id from public.projectos_projects
   where organization_id = p_organization_id
     and ((p_project_key is not null and project_key = p_project_key)
       or (p_repository is not null and repository = p_repository))
   order by case when p_project_key is not null and project_key = p_project_key then 0 else 1 end
   limit 1;

  insert into public.projectos_external_events (
    organization_id, project_id, provider, delivery_id, event_type, repository,
    external_created_at, payload_hash, payload_redacted, process_status, processed_at
  ) values (
    p_organization_id, v_project_id, p_provider, p_delivery_id, p_event_type, p_repository,
    p_external_created_at, p_payload_hash, coalesce(p_payload_redacted, '{}'::jsonb), 'processed', now()
  )
  on conflict (organization_id, provider, delivery_id) do update set
    project_id = coalesce(projectos_external_events.project_id, excluded.project_id),
    process_status = 'processed', processed_at = now()
  returning * into v_event;

  if v_project_id is not null then
    insert into public.projectos_integration_health (
      organization_id, project_id, provider, status, last_event_at, last_success_at, stale_after, details
    ) values (
      p_organization_id, v_project_id, p_provider, 'healthy', now(), now(), now() + interval '24 hours',
      jsonb_build_object('lastEventType', p_event_type, 'deliveryId', p_delivery_id)
    ) on conflict (project_id, provider) do update set
      status = 'healthy', last_event_at = excluded.last_event_at,
      last_success_at = excluded.last_success_at, stale_after = excluded.stale_after,
      details = excluded.details, updated_at = now();
  end if;

  return to_jsonb(v_event);
end;
$$;

create or replace function public.projectos_recompute_project(
  p_organization_id uuid,
  p_project_key text
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project public.projectos_projects%rowtype;
  v_task public.projectos_tasks%rowtype;
  v_missing integer;
  v_criteria integer;
  v_satisfied integer;
  v_has_blocker boolean;
  v_has_activity boolean;
  v_completed integer;
  v_total integer;
  v_required_total integer;
  v_required_completed integer;
  v_next_task public.projectos_tasks%rowtype;
  v_current_phase public.projectos_phases%rowtype;
  v_projection jsonb;
  v_version bigint;
begin
  if auth.role() <> 'service_role' and not private.is_org_member(p_organization_id) then
    raise exception 'projectos_forbidden';
  end if;

  select * into strict v_project from public.projectos_projects
   where organization_id = p_organization_id and project_key = p_project_key;

  for v_task in select * from public.projectos_tasks where project_id = v_project.id order by sequence loop
    select count(*) into v_missing
      from public.projectos_task_dependencies d
      join public.projectos_tasks required_task on required_task.id = d.depends_on_task_id
      where d.task_id = v_task.id and d.dependency_type = 'hard'
        and required_task.status <> 'complete';

    v_criteria := jsonb_array_length(v_task.completion_criteria);
    if v_criteria > 0 then
      select count(*) into v_satisfied
      from jsonb_array_elements(v_task.completion_criteria) criterion
      where exists (
        select 1 from public.projectos_evidence e
        where e.task_id = v_task.id
          and e.invalidated_at is null
          and e.status in ('passing','complete')
          and e.evidence_type = case
            when jsonb_typeof(criterion) = 'string' then trim(both '"' from criterion::text)
            else criterion->>'type'
          end
          and (
            coalesce(case when jsonb_typeof(criterion) = 'object' then (criterion->>'exact_head')::boolean else false end, false) = false
            or (v_task.current_head_sha is not null and e.head_sha = v_task.current_head_sha)
          )
      );
    else
      select count(*) into v_satisfied from public.projectos_evidence e
       where e.task_id = v_task.id and e.invalidated_at is null
         and e.evidence_type = 'task_completion' and e.status in ('passing','complete');
      v_criteria := 1;
    end if;

    select exists(
      select 1 from public.projectos_evidence e
       where e.task_id = v_task.id and e.invalidated_at is null
         and (e.evidence_type = 'blocker' or e.status in ('failing','blocked'))
    ) into v_has_blocker;

    select exists(
      select 1 from public.projectos_evidence e
       where e.task_id = v_task.id and e.invalidated_at is null
         and e.evidence_type in ('github_pr_open','branch_created','implementation_started','preview_deployment')
         and e.status in ('observed','passing','complete')
    ) into v_has_activity;

    update public.projectos_tasks set
      status = case
        when status = 'cancelled' then 'cancelled'
        when v_satisfied >= v_criteria then 'complete'
        when v_has_blocker then 'blocked'
        when v_missing > 0 then 'not_started'
        when status in ('waiting_review','waiting_approval') then status
        when v_has_activity or started_at is not null then 'in_progress'
        else 'ready'
      end,
      completed_at = case when v_satisfied >= v_criteria then coalesce(completed_at, now()) else null end,
      started_at = case when v_has_activity then coalesce(started_at, now()) else started_at end
    where id = v_task.id;
  end loop;

  update public.projectos_phases phase set
    status = case
      when not exists (select 1 from public.projectos_tasks t where t.phase_id = phase.id and t.blocks_phase_exit and t.status <> 'complete') then 'complete'
      when exists (select 1 from public.projectos_tasks t where t.phase_id = phase.id and t.status = 'blocked') then 'blocked'
      when exists (select 1 from public.projectos_tasks t where t.phase_id = phase.id and t.status in ('ready','in_progress','waiting_review','waiting_approval')) then 'active'
      else 'planned'
    end,
    started_at = case when exists (select 1 from public.projectos_tasks t where t.phase_id = phase.id and t.status in ('ready','in_progress','waiting_review','waiting_approval','complete')) then coalesce(phase.started_at, now()) else phase.started_at end,
    completed_at = case when not exists (select 1 from public.projectos_tasks t where t.phase_id = phase.id and t.blocks_phase_exit and t.status <> 'complete') then coalesce(phase.completed_at, now()) else null end
  where phase.project_id = v_project.id;

  select * into v_next_task from public.projectos_tasks t
   where t.project_id = v_project.id and t.status in ('ready','in_progress','waiting_review','waiting_approval')
   order by case t.continuation_role when 'primary' then 0 when 'parallel' then 1 else 2 end,
            t.priority desc, t.sequence asc limit 1;

  if v_next_task.phase_id is not null then select * into v_current_phase from public.projectos_phases where id = v_next_task.phase_id; end if;

  select count(*), count(*) filter (where status = 'complete'),
         count(*) filter (where blocks_phase_exit),
         count(*) filter (where blocks_phase_exit and status = 'complete')
    into v_total, v_completed, v_required_total, v_required_completed
  from public.projectos_tasks where project_id = v_project.id and status <> 'cancelled';

  update public.projectos_projects set
    current_phase_key = v_current_phase.phase_key,
    current_task_key = v_next_task.task_key,
    progress_percent = case when v_total = 0 then 0 else round((v_completed::numeric / v_total::numeric) * 100, 2) end,
    status = case
      when v_required_total > 0 and v_required_completed = v_required_total then 'complete'
      when exists (select 1 from public.projectos_tasks where project_id = v_project.id and status = 'blocked') and v_next_task.id is null then 'blocked'
      else 'active'
    end,
    last_reconciled_at = now()
  where id = v_project.id returning * into v_project;

  select jsonb_build_object(
    'schemaVersion', '2.0.0',
    'observedThrough', now(),
    'project', jsonb_build_object(
      'id', v_project.id, 'key', v_project.project_key, 'name', v_project.name,
      'repository', v_project.repository, 'workspacePath', v_project.workspace_path,
      'status', v_project.status, 'objective', v_project.objective,
      'roadmapVersion', v_project.roadmap_version
    ),
    'progress', jsonb_build_object('completed', v_completed, 'total', v_total, 'percent', v_project.progress_percent),
    'currentPhase', case when v_current_phase.id is null then null else jsonb_build_object(
      'id', v_current_phase.id, 'key', v_current_phase.phase_key, 'name', v_current_phase.name,
      'status', v_current_phase.status, 'sequence', v_current_phase.sequence
    ) end,
    'nextTask', case when v_next_task.id is null then null else jsonb_build_object(
      'id', v_next_task.id, 'key', v_next_task.task_key, 'title', v_next_task.title,
      'status', v_next_task.status, 'repository', v_project.repository,
      'builderAgent', v_next_task.builder_agent, 'builderVendor', v_next_task.builder_vendor,
      'reviewerAgent', v_next_task.reviewer_agent, 'reviewerVendor', v_next_task.reviewer_vendor,
      'riskClass', v_next_task.risk_class, 'headSha', v_next_task.current_head_sha,
      'pullRequestNumber', v_next_task.current_pr_number
    ) end,
    'phases', coalesce((select jsonb_agg(jsonb_build_object(
      'id', p.id, 'key', p.phase_key, 'name', p.name, 'sequence', p.sequence, 'status', p.status,
      'completedTasks', (select count(*) from public.projectos_tasks t where t.phase_id = p.id and t.status = 'complete'),
      'gatingTasks', (select count(*) from public.projectos_tasks t where t.phase_id = p.id and t.blocks_phase_exit)
    ) order by p.sequence) from public.projectos_phases p where p.project_id = v_project.id), '[]'::jsonb),
    'tasks', coalesce((select jsonb_agg(jsonb_build_object(
      'id', t.id, 'key', t.task_key, 'title', t.title, 'status', t.status,
      'priority', t.priority, 'role', t.continuation_role, 'blocksPhaseExit', t.blocks_phase_exit,
      'headSha', t.current_head_sha, 'pullRequestNumber', t.current_pr_number,
      'missingDependencies', coalesce((select jsonb_agg(dep.task_key) from public.projectos_task_dependencies d join public.projectos_tasks dep on dep.id=d.depends_on_task_id where d.task_id=t.id and dep.status <> 'complete'), '[]'::jsonb),
      'evidence', coalesce((select jsonb_agg(jsonb_build_object('type',e.evidence_type,'provider',e.provider,'status',e.status,'headSha',e.head_sha,'url',e.source_url,'observedAt',e.observed_at) order by e.observed_at desc) from public.projectos_evidence e where e.task_id=t.id and e.invalidated_at is null), '[]'::jsonb)
    ) order by t.sequence) from public.projectos_tasks t where t.project_id = v_project.id), '[]'::jsonb),
    'integrations', coalesce((select jsonb_agg(jsonb_build_object('provider',h.provider,'status',h.status,'lastEventAt',h.last_event_at,'lastSuccessAt',h.last_success_at,'staleAfter',h.stale_after,'details',h.details)) from public.projectos_integration_health h where h.project_id=v_project.id), '[]'::jsonb),
    'lessons', coalesce((select jsonb_agg(jsonb_build_object('scope',l.scope,'category',l.category,'lesson',l.lesson,'confidence',l.confidence,'evidenceCount',l.evidence_count,'status',l.status) order by l.confidence desc,l.evidence_count desc) from public.projectos_lessons l where l.organization_id=p_organization_id and (l.project_id=v_project.id or l.scope in ('portfolio','operational')) and l.status in ('candidate','promoted')), '[]'::jsonb),
    'liveSync', jsonb_build_object('mode','durable','healthy',true,'lastReconciledAt',v_project.last_reconciled_at,'stale',false)
  ) into v_projection;

  insert into public.projectos_projections (organization_id, project_id, version, projection, computed_at, stale_after)
  values (p_organization_id, v_project.id, 1, v_projection, now(), now() + interval '15 minutes')
  on conflict (project_id) do update set
    version = projectos_projections.version + 1,
    projection = excluded.projection, computed_at = excluded.computed_at, stale_after = excluded.stale_after
  returning version into v_version;

  v_projection := jsonb_set(v_projection, '{projectionVersion}', to_jsonb(v_version), true);
  update public.projectos_projections set projection = v_projection where project_id = v_project.id;

  insert into public.projectos_workspace_documents (organization_id, project_id, document_key, content)
  values
    (p_organization_id, v_project.id, 'current_state', v_projection),
    (p_organization_id, v_project.id, 'next_action', coalesce(v_projection->'nextTask', 'null'::jsonb)),
    (p_organization_id, v_project.id, 'tasks', v_projection->'tasks'),
    (p_organization_id, v_project.id, 'integrations', v_projection->'integrations'),
    (p_organization_id, v_project.id, 'lessons', v_projection->'lessons')
  on conflict (project_id, document_key) do update set
    version = projectos_workspace_documents.version + 1,
    content = excluded.content, generated_at = now();

  return v_projection;
end;
$$;

create or replace function public.projectos_record_evidence(
  p_organization_id uuid,
  p_project_key text,
  p_task_key text,
  p_evidence_type text,
  p_provider text,
  p_external_id text,
  p_status text,
  p_source_url text default null,
  p_repository text default null,
  p_head_sha text default null,
  p_verdict text default null,
  p_payload_redacted jsonb default '{}'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project public.projectos_projects%rowtype;
  v_task public.projectos_tasks%rowtype;
  v_evidence public.projectos_evidence%rowtype;
  v_projection jsonb;
begin
  perform private.assert_control_service_role();
  select * into strict v_project from public.projectos_projects where organization_id=p_organization_id and project_key=p_project_key;
  select * into strict v_task from public.projectos_tasks where project_id=v_project.id and task_key=p_task_key;

  if p_head_sha is not null then
    update public.projectos_evidence set
      status='invalidated', invalidated_at=now(), invalidation_reason='superseded_by_new_head'
    where task_id=v_task.id and evidence_type=p_evidence_type and invalidated_at is null
      and head_sha is not null and head_sha <> p_head_sha;
    update public.projectos_tasks set current_head_sha=p_head_sha where id=v_task.id;
  end if;

  insert into public.projectos_evidence (
    organization_id, project_id, task_id, evidence_type, provider, external_id,
    source_url, repository, head_sha, status, verdict, payload_redacted
  ) values (
    p_organization_id, v_project.id, v_task.id, p_evidence_type, p_provider, p_external_id,
    p_source_url, p_repository, p_head_sha, p_status, p_verdict, coalesce(p_payload_redacted,'{}'::jsonb)
  )
  on conflict (organization_id, provider, evidence_type, external_id) where external_id is not null
  do update set
    task_id=excluded.task_id, source_url=excluded.source_url, repository=excluded.repository,
    head_sha=excluded.head_sha, status=excluded.status, verdict=excluded.verdict,
    payload_redacted=excluded.payload_redacted, observed_at=now(), invalidated_at=null, invalidation_reason=null
  returning * into v_evidence;

  v_projection := public.projectos_recompute_project(p_organization_id, p_project_key);
  return jsonb_build_object('evidence',to_jsonb(v_evidence),'projection',v_projection);
end;
$$;

create or replace function public.projectos_record_outcome(
  p_organization_id uuid,
  p_project_key text,
  p_task_key text,
  p_success boolean,
  p_planned jsonb default '{}'::jsonb,
  p_actual jsonb default '{}'::jsonb,
  p_quality_score numeric default null,
  p_duration_seconds integer default null,
  p_repair_attempts integer default 0,
  p_deployment_result text default null,
  p_impact_metrics jsonb default '{}'::jsonb,
  p_agent_observations jsonb default '[]'::jsonb,
  p_lessons jsonb default '[]'::jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project public.projectos_projects%rowtype;
  v_task public.projectos_tasks%rowtype;
  v_item jsonb;
  v_existing public.projectos_lessons%rowtype;
  v_threshold integer := 3;
  v_scope text;
  v_category text;
  v_fingerprint text;
  v_lesson text;
  v_project_for_lesson uuid;
begin
  perform private.assert_control_service_role();
  select * into strict v_project from public.projectos_projects where organization_id=p_organization_id and project_key=p_project_key;
  select * into strict v_task from public.projectos_tasks where project_id=v_project.id and task_key=p_task_key;
  select promotion_min_evidence into v_threshold from public.projectos_policies where organization_id=p_organization_id;
  v_threshold := coalesce(v_threshold,3);

  insert into public.projectos_task_outcomes (
    organization_id,project_id,task_id,planned,actual,success,quality_score,duration_seconds,
    repair_attempts,deployment_result,impact_metrics
  ) values (
    p_organization_id,v_project.id,v_task.id,coalesce(p_planned,'{}'::jsonb),coalesce(p_actual,'{}'::jsonb),p_success,
    p_quality_score,p_duration_seconds,greatest(coalesce(p_repair_attempts,0),0),p_deployment_result,coalesce(p_impact_metrics,'{}'::jsonb)
  ) on conflict (task_id) do update set
    planned=excluded.planned, actual=excluded.actual, success=excluded.success,
    quality_score=excluded.quality_score, duration_seconds=excluded.duration_seconds,
    repair_attempts=excluded.repair_attempts, deployment_result=excluded.deployment_result,
    impact_metrics=excluded.impact_metrics, recorded_at=now();

  for v_item in select value from jsonb_array_elements(coalesce(p_agent_observations,'[]'::jsonb)) loop
    insert into public.projectos_agent_observations (
      organization_id,project_id,task_id,agent_key,vendor,role,success,duration_seconds,
      repair_attempts,quality_score,cost_cents,capabilities,notes
    ) values (
      p_organization_id,v_project.id,v_task.id,v_item->>'agentKey',v_item->>'vendor',coalesce(v_item->>'role','builder'),
      coalesce((v_item->>'success')::boolean,p_success),nullif(v_item->>'durationSeconds','')::integer,
      coalesce(nullif(v_item->>'repairAttempts','')::integer,0),nullif(v_item->>'qualityScore','')::numeric,
      coalesce(nullif(v_item->>'costCents','')::integer,0),coalesce(v_item->'capabilities','[]'::jsonb),coalesce(v_item->'notes','{}'::jsonb)
    );
  end loop;

  for v_item in select value from jsonb_array_elements(coalesce(p_lessons,'[]'::jsonb)) loop
    v_scope := coalesce(v_item->>'scope','project');
    v_category := coalesce(v_item->>'category','general');
    v_lesson := v_item->>'lesson';
    v_fingerprint := coalesce(v_item->>'fingerprint', encode(digest(v_category || ':' || coalesce(v_lesson,''),'sha256'),'hex'));
    v_project_for_lesson := case when v_scope='project' then v_project.id else null end;
    if v_lesson is null or trim(v_lesson)='' then continue; end if;

    select * into v_existing from public.projectos_lessons
     where organization_id=p_organization_id and scope=v_scope and category=v_category
       and project_id is not distinct from v_project_for_lesson
       and pattern->>'fingerprint'=v_fingerprint
     limit 1;

    if found then
      update public.projectos_lessons set
        evidence_count=evidence_count+1,
        confidence=least(1, confidence + 0.1),
        lesson=v_lesson,
        pattern=coalesce(v_item->'pattern','{}'::jsonb) || jsonb_build_object('fingerprint',v_fingerprint),
        status=case when evidence_count+1 >= v_threshold then 'promoted' else status end,
        promoted_at=case when evidence_count+1 >= v_threshold then coalesce(promoted_at,now()) else promoted_at end
      where id=v_existing.id;
    else
      insert into public.projectos_lessons (
        organization_id,scope,project_id,source_task_id,category,lesson,pattern,evidence_count,confidence,status,applies_to,promoted_at
      ) values (
        p_organization_id,v_scope,v_project_for_lesson,v_task.id,v_category,v_lesson,
        coalesce(v_item->'pattern','{}'::jsonb) || jsonb_build_object('fingerprint',v_fingerprint),
        1,coalesce(nullif(v_item->>'confidence','')::numeric,0.5),
        case when v_threshold <= 1 then 'promoted' else 'candidate' end,
        coalesce(v_item->'appliesTo','{}'::jsonb),case when v_threshold <= 1 then now() else null end
      );
    end if;
  end loop;

  insert into public.projectos_learning_runs (organization_id,project_id,status,inputs,outputs,completed_at)
  values (p_organization_id,v_project.id,'succeeded',jsonb_build_object('taskKey',p_task_key,'success',p_success),
    jsonb_build_object('agentObservations',jsonb_array_length(coalesce(p_agent_observations,'[]'::jsonb)),'lessons',jsonb_array_length(coalesce(p_lessons,'[]'::jsonb))),now());

  return jsonb_build_object('ok',true,'projection',public.projectos_recompute_project(p_organization_id,p_project_key));
end;
$$;

create or replace function public.projectos_get_dashboard(
  p_organization_id uuid,
  p_project_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_result jsonb;
  v_project record;
begin
  if auth.role() <> 'service_role' and not private.is_org_member(p_organization_id) then raise exception 'projectos_forbidden'; end if;
  if p_project_key is not null then
    select projection into v_result from public.projectos_projections pr
      join public.projectos_projects p on p.id=pr.project_id
      where p.organization_id=p_organization_id and p.project_key=p_project_key;
    if v_result is null then v_result := public.projectos_recompute_project(p_organization_id,p_project_key); end if;
    return v_result;
  end if;

  for v_project in select project_key from public.projectos_projects where organization_id=p_organization_id and status <> 'archived' loop
    perform public.projectos_recompute_project(p_organization_id,v_project.project_key);
  end loop;

  select jsonb_build_object(
    'schemaVersion','2.0.0','observedThrough',now(),
    'policy',(select to_jsonb(p) from public.projectos_policies p where p.organization_id=p_organization_id),
    'portfolio',jsonb_build_object(
      'projects',count(*),
      'active',count(*) filter (where p.status='active'),
      'blocked',count(*) filter (where p.status='blocked'),
      'complete',count(*) filter (where p.status='complete'),
      'averageProgress',coalesce(round(avg(p.progress_percent),2),0)
    ),
    'projects',coalesce(jsonb_agg(jsonb_build_object(
      'key',p.project_key,'name',p.name,'repository',p.repository,'workspacePath',p.workspace_path,
      'status',p.status,'progressPercent',p.progress_percent,'currentPhaseKey',p.current_phase_key,
      'currentTaskKey',p.current_task_key,'lastReconciledAt',p.last_reconciled_at,
      'projection',pr.projection
    ) order by case p.status when 'blocked' then 0 when 'active' then 1 else 2 end,p.updated_at desc),'[]'::jsonb)
  ) into v_result
  from public.projectos_projects p left join public.projectos_projections pr on pr.project_id=p.id
  where p.organization_id=p_organization_id and p.status <> 'archived';
  return v_result;
end;
$$;

grant execute on function public.projectos_register_project(uuid,text,text,text,text,uuid) to authenticated, service_role;
grant execute on function public.projectos_accept_intake(uuid,uuid,text,text,text,text,text,text,text) to authenticated, service_role;
grant execute on function public.projectos_record_external_event(uuid,text,text,text,text,jsonb,text,text,timestamptz) to service_role;
grant execute on function public.projectos_record_evidence(uuid,text,text,text,text,text,text,text,text,text,text,jsonb) to service_role;
grant execute on function public.projectos_recompute_project(uuid,text) to authenticated, service_role;
grant execute on function public.projectos_record_outcome(uuid,text,text,boolean,jsonb,jsonb,numeric,integer,integer,text,jsonb,jsonb,jsonb) to service_role;
grant execute on function public.projectos_get_dashboard(uuid,text) to authenticated, service_role;

insert into public.projectos_policies (organization_id, policy)
values ('2270b266-59da-4c39-bfd9-9f8d08352af0', jsonb_build_object(
  'workflow','owner_request -> projectos_intake -> workspace -> plan -> execution -> independent_review -> evidence -> merge_deploy -> outcome -> learning',
  'phoneOnly',true,
  'generatedSnapshotsAreAuthority',false
)) on conflict (organization_id) do update set policy=excluded.policy, mandatory_control_layer=true,
  require_project_workspace=true, require_evidence_for_completion=true,
  require_exact_sha_review=true, require_independent_vendor_review=true,
  allow_untracked_work=false, learning_enabled=true;

select public.projectos_register_project('2270b266-59da-4c39-bfd9-9f8d08352af0','mcpmaster','MCPMaster / ProjectOS','mbanatao/mcpmaster','Mandatory Banatao Systems control layer for all project work.','76a3bf0a-5bfa-4ce2-b92a-3646824e5754');
select public.projectos_register_project('2270b266-59da-4c39-bfd9-9f8d08352af0','callgate','CallGate','mbanatao/callgate-platform','Production-grade branded calling platform and proving project for ProjectOS.','76a3bf0a-5bfa-4ce2-b92a-3646824e5754');
select public.projectos_register_project('2270b266-59da-4c39-bfd9-9f8d08352af0','battle','Battle','mbanatao/Battle','Legal operations and client-engagement system.','76a3bf0a-5bfa-4ce2-b92a-3646824e5754');
select public.projectos_register_project('2270b266-59da-4c39-bfd9-9f8d08352af0','realmatch','RealMatch','mbanatao/realmatch','Matching, qualification, trust, and conversion infrastructure.','76a3bf0a-5bfa-4ce2-b92a-3646824e5754');
select public.projectos_register_project('2270b266-59da-4c39-bfd9-9f8d08352af0','memory','Memory','mbanatao/Memory','AI memory and intelligence infrastructure.','76a3bf0a-5bfa-4ce2-b92a-3646824e5754');

insert into public.projectos_phases (organization_id,project_id,phase_key,name,sequence)
select p.organization_id,p.id,'kernel','Mandatory operating kernel',0 from public.projectos_projects p where p.project_key='mcpmaster'
on conflict (project_id,phase_key) do nothing;
insert into public.projectos_phases (organization_id,project_id,phase_key,name,sequence)
select p.organization_id,p.id,'production-proof','CallGate production proof',0 from public.projectos_projects p where p.project_key='callgate'
on conflict (project_id,phase_key) do nothing;

insert into public.projectos_tasks (organization_id,project_id,phase_id,task_key,title,description,sequence,priority,status,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,completion_criteria,current_head_sha,current_pr_number)
select p.organization_id,p.id,ph.id,'POS-KERNEL-001','Implement durable ProjectOS operating kernel','Durable workspaces, mandatory intake, events, evidence, projections, outcomes, lessons, and learning.',0,100,'in_progress','primary',true,'R2','A-CHATGPT','OpenAI','Vercel Agent','Vercel',
  '[{"type":"github_ci_success","exact_head":true},{"type":"independent_review_pass","exact_head":true},{"type":"github_pr_merged","exact_head":true},{"type":"vercel_production_ready","exact_head":true}]'::jsonb,
  '388282dd3013ee4a7bbd57efe986c0deb1b4af40',55
from public.projectos_projects p join public.projectos_phases ph on ph.project_id=p.id and ph.phase_key='kernel' where p.project_key='mcpmaster'
on conflict (project_id,task_key) do update set completion_criteria=excluded.completion_criteria,current_head_sha=excluded.current_head_sha,current_pr_number=excluded.current_pr_number;

insert into public.projectos_tasks (organization_id,project_id,phase_id,task_key,title,description,sequence,priority,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,completion_criteria)
select p.organization_id,p.id,ph.id,'POS-KERNEL-002','Enforce mandatory ProjectOS intake','Every request resolves to or creates a durable project workspace before execution.',1,95,'primary',true,'R2','A-CHATGPT','OpenAI','A-COPILOT','GitHub','["database_migration_applied","intake_api_verified"]'::jsonb
from public.projectos_projects p join public.projectos_phases ph on ph.project_id=p.id and ph.phase_key='kernel' where p.project_key='mcpmaster'
on conflict (project_id,task_key) do nothing;
insert into public.projectos_tasks (organization_id,project_id,phase_id,task_key,title,description,sequence,priority,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,completion_criteria)
select p.organization_id,p.id,ph.id,'POS-KERNEL-003','Implement generic connector reconciliation','Ingest GitHub, Vercel, Supabase, and PostHog state with idempotency and stale-data repair.',2,90,'primary',true,'R2','A-CHATGPT','OpenAI','Vercel Agent','Vercel','["github_reconciliation_verified","vercel_reconciliation_verified","supabase_health_verified","posthog_health_verified"]'::jsonb
from public.projectos_projects p join public.projectos_phases ph on ph.project_id=p.id and ph.phase_key='kernel' where p.project_key='mcpmaster'
on conflict (project_id,task_key) do nothing;
insert into public.projectos_tasks (organization_id,project_id,phase_id,task_key,title,description,sequence,priority,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,completion_criteria)
select p.organization_id,p.id,ph.id,'POS-KERNEL-004','Activate outcome learning and lesson promotion','Compare plan versus outcome, score agents, record failure modes, and promote repeated evidence-backed lessons.',3,85,'primary',true,'R1','A-CHATGPT','OpenAI','A-COPILOT','GitHub','["learning_engine_verified","lesson_promotion_verified"]'::jsonb
from public.projectos_projects p join public.projectos_phases ph on ph.project_id=p.id and ph.phase_key='kernel' where p.project_key='mcpmaster'
on conflict (project_id,task_key) do nothing;
insert into public.projectos_tasks (organization_id,project_id,phase_id,task_key,title,description,sequence,priority,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,completion_criteria)
select p.organization_id,p.id,ph.id,'POS-KERNEL-005','Publish live portfolio and project workspaces','Dashboard reads durable projections and exposes project identity, roadmap, tasks, evidence, integrations, decisions, and lessons.',4,80,'primary',true,'R1','A-CHATGPT','OpenAI','Vercel Agent','Vercel','["dashboard_live_verified","workspace_projection_verified"]'::jsonb
from public.projectos_projects p join public.projectos_phases ph on ph.project_id=p.id and ph.phase_key='kernel' where p.project_key='mcpmaster'
on conflict (project_id,task_key) do nothing;

insert into public.projectos_task_dependencies (organization_id,project_id,task_id,depends_on_task_id)
select t.organization_id,t.project_id,t.id,d.id from public.projectos_tasks t join public.projectos_tasks d on d.project_id=t.project_id
where t.task_key='POS-KERNEL-002' and d.task_key='POS-KERNEL-001' on conflict do nothing;
insert into public.projectos_task_dependencies (organization_id,project_id,task_id,depends_on_task_id)
select t.organization_id,t.project_id,t.id,d.id from public.projectos_tasks t join public.projectos_tasks d on d.project_id=t.project_id
where t.task_key='POS-KERNEL-003' and d.task_key='POS-KERNEL-002' on conflict do nothing;
insert into public.projectos_task_dependencies (organization_id,project_id,task_id,depends_on_task_id)
select t.organization_id,t.project_id,t.id,d.id from public.projectos_tasks t join public.projectos_tasks d on d.project_id=t.project_id
where t.task_key='POS-KERNEL-004' and d.task_key='POS-KERNEL-003' on conflict do nothing;
insert into public.projectos_task_dependencies (organization_id,project_id,task_id,depends_on_task_id)
select t.organization_id,t.project_id,t.id,d.id from public.projectos_tasks t join public.projectos_tasks d on d.project_id=t.project_id
where t.task_key='POS-KERNEL-005' and d.task_key='POS-KERNEL-004' on conflict do nothing;

insert into public.projectos_tasks (organization_id,project_id,phase_id,task_key,title,description,sequence,priority,status,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,completion_criteria,current_head_sha,current_pr_number)
select p.organization_id,p.id,ph.id,'PO-015','Prove CallGate fallback and repair','Verify fallback and repair with exact issue, PR, review, CI, and merge evidence.',0,100,'in_progress','primary',true,'R2','A-JULES','Google','A-CHATGPT','OpenAI',
  '[{"type":"github_issue_closed"},{"type":"github_pr_merged","exact_head":true},{"type":"github_ci_success","exact_head":true},{"type":"independent_review_pass","exact_head":true}]'::jsonb,
  '699542f18ccf08ce299c7a70225728507959c96e',114
from public.projectos_projects p join public.projectos_phases ph on ph.project_id=p.id and ph.phase_key='production-proof' where p.project_key='callgate'
on conflict (project_id,task_key) do update set completion_criteria=excluded.completion_criteria,current_head_sha=excluded.current_head_sha,current_pr_number=excluded.current_pr_number;
insert into public.projectos_tasks (organization_id,project_id,phase_id,task_key,title,description,sequence,priority,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,completion_criteria)
select p.organization_id,p.id,ph.id,'PO-016','Prove CallGate release observation and rollback','Observe production release and prove rollback recovery.',1,90,'primary',true,'R3','A-CHATGPT','OpenAI','A-COPILOT','GitHub','["vercel_production_ready","rollback_proven"]'::jsonb
from public.projectos_projects p join public.projectos_phases ph on ph.project_id=p.id and ph.phase_key='production-proof' where p.project_key='callgate'
on conflict (project_id,task_key) do nothing;
insert into public.projectos_task_dependencies (organization_id,project_id,task_id,depends_on_task_id)
select t.organization_id,t.project_id,t.id,d.id from public.projectos_tasks t join public.projectos_tasks d on d.project_id=t.project_id
where t.task_key='PO-016' and d.task_key='PO-015' on conflict do nothing;

with projects as (
  select * from public.projectos_projects where project_key in ('battle','realmatch','memory')
), phases as (
  insert into public.projectos_phases (organization_id,project_id,phase_key,name,sequence)
  select organization_id,id,'discovery','Current-state discovery and roadmap reconciliation',0 from projects
  on conflict (project_id,phase_key) do update set name=excluded.name returning *
)
insert into public.projectos_tasks (organization_id,project_id,phase_id,task_key,title,description,sequence,priority,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,completion_criteria)
select p.organization_id,p.id,ph.id,'DISCOVERY-001','Reconcile complete project state','Analyze repository, roadmap, deployment, database, analytics, risks, and the correct next task.',0,100,'primary',true,'R1','A-CHATGPT','OpenAI','A-COPILOT','GitHub','["project_reconciled"]'::jsonb
from projects p join phases ph on ph.project_id=p.id
on conflict (project_id,task_key) do nothing;

select public.projectos_record_evidence('2270b266-59da-4c39-bfd9-9f8d08352af0','callgate','PO-015','github_issue_closed','github','callgate-issue-112','complete','https://github.com/mbanatao/callgate-platform/issues/112','mbanatao/callgate-platform',null,'pass',jsonb_build_object('issue',112));
select public.projectos_record_evidence('2270b266-59da-4c39-bfd9-9f8d08352af0','callgate','PO-015','github_pr_merged','github','callgate-pr-114-merge','complete','https://github.com/mbanatao/callgate-platform/pull/114','mbanatao/callgate-platform','699542f18ccf08ce299c7a70225728507959c96e','pass',jsonb_build_object('mergeCommit','febbf1f1743ed8a25b194005df8fe7bc5de68dc7'));
select public.projectos_record_evidence('2270b266-59da-4c39-bfd9-9f8d08352af0','callgate','PO-015','github_ci_success','github','callgate-run-30615099412','passing','https://github.com/mbanatao/callgate-platform/actions/runs/30615099412','mbanatao/callgate-platform','699542f18ccf08ce299c7a70225728507959c96e','pass',jsonb_build_object('runId',30615099412));
select public.projectos_record_evidence('2270b266-59da-4c39-bfd9-9f8d08352af0','callgate','PO-015','independent_review_pass','github','callgate-pr-114-review','passing','https://github.com/mbanatao/callgate-platform/pull/114','mbanatao/callgate-platform','699542f18ccf08ce299c7a70225728507959c96e','pass','{}'::jsonb);

select public.projectos_recompute_project('2270b266-59da-4c39-bfd9-9f8d08352af0','mcpmaster');
select public.projectos_recompute_project('2270b266-59da-4c39-bfd9-9f8d08352af0','callgate');
select public.projectos_recompute_project('2270b266-59da-4c39-bfd9-9f8d08352af0','battle');
select public.projectos_recompute_project('2270b266-59da-4c39-bfd9-9f8d08352af0','realmatch');
select public.projectos_recompute_project('2270b266-59da-4c39-bfd9-9f8d08352af0','memory');
