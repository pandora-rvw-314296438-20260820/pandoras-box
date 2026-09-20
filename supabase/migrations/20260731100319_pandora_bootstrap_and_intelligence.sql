-- GOVERNED MIGRATION-HISTORY RECOVERY.
-- This filename preserves a production ledger version for clean replay.
-- Production history is never rewritten; live hashes remain in the recovery manifest.
-- Semantic recovery of the provider-recorded SQL payload; comments and terminal newline may differ.

create or replace function public.projectos_apply_manifest(
  p_organization_id uuid,
  p_manifest jsonb,
  p_created_by uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project_json jsonb;
  v_phase_json jsonb;
  v_task_json jsonb;
  v_resource_json jsonb;
  v_dependency_json jsonb;
  v_project public.projectos_projects%rowtype;
  v_phase_id uuid;
  v_task_id uuid;
  v_dependency_id uuid;
  v_project_count integer := 0;
  v_task_count integer := 0;
  v_resource_count integer := 0;
begin
  perform private.assert_control_service_role();
  if jsonb_typeof(p_manifest) <> 'object'
    or jsonb_typeof(coalesce(p_manifest->'projects','[]'::jsonb)) <> 'array'
  then raise exception 'invalid_projectos_manifest'; end if;

  insert into public.projectos_policies (
    organization_id,mandatory_control_layer,require_project_workspace,
    require_evidence_for_completion,require_exact_sha_review,
    require_independent_vendor_review,require_owner_release_approval,
    allow_untracked_work,learning_enabled,promotion_min_evidence,policy
  ) values (
    p_organization_id,
    coalesce((p_manifest->'policy'->>'mandatoryControlLayer')::boolean,true),
    coalesce((p_manifest->'policy'->>'requireProjectWorkspace')::boolean,true),
    coalesce((p_manifest->'policy'->>'requireEvidenceForCompletion')::boolean,true),
    coalesce((p_manifest->'policy'->>'requireExactShaReview')::boolean,true),
    coalesce((p_manifest->'policy'->>'requireIndependentVendorReview')::boolean,true),
    coalesce((p_manifest->'policy'->>'requireOwnerReleaseApproval')::boolean,true),
    coalesce((p_manifest->'policy'->>'allowUntrackedWork')::boolean,false),
    coalesce((p_manifest->'policy'->>'learningEnabled')::boolean,true),
    coalesce(nullif(p_manifest->'policy'->>'promotionMinEvidence','')::integer,3),
    coalesce(p_manifest->'policy'->'details','{}'::jsonb)
  ) on conflict (organization_id) do update set
    mandatory_control_layer=excluded.mandatory_control_layer,
    require_project_workspace=excluded.require_project_workspace,
    require_evidence_for_completion=excluded.require_evidence_for_completion,
    require_exact_sha_review=excluded.require_exact_sha_review,
    require_independent_vendor_review=excluded.require_independent_vendor_review,
    require_owner_release_approval=excluded.require_owner_release_approval,
    allow_untracked_work=excluded.allow_untracked_work,
    learning_enabled=excluded.learning_enabled,
    promotion_min_evidence=excluded.promotion_min_evidence,
    policy=excluded.policy,
    updated_at=now();

  for v_project_json in select value from jsonb_array_elements(p_manifest->'projects') loop
    perform public.projectos_register_project(
      p_organization_id,
      v_project_json->>'key',
      v_project_json->>'name',
      nullif(v_project_json->>'repository',''),
      coalesce(v_project_json->>'objective',''),
      p_created_by
    );
    select * into strict v_project from public.projectos_projects
      where organization_id=p_organization_id and project_key=v_project_json->>'key';
    v_project_count := v_project_count + 1;

    for v_resource_json in select value from jsonb_array_elements(coalesce(v_project_json->'resources','[]'::jsonb)) loop
      insert into public.projectos_project_resources (
        organization_id,project_id,provider,resource_type,external_id,external_name,
        environment,canonical_url,binding_state,configuration,verified_at
      ) values (
        p_organization_id,v_project.id,v_resource_json->>'provider',v_resource_json->>'resourceType',
        v_resource_json->>'externalId',nullif(v_resource_json->>'externalName',''),
        nullif(v_resource_json->>'environment',''),nullif(v_resource_json->>'canonicalUrl',''),
        coalesce(v_resource_json->>'bindingState','verified'),
        coalesce(v_resource_json->'configuration','{}'::jsonb),
        case when coalesce(v_resource_json->>'bindingState','verified')='verified' then now() else null end
      ) on conflict (project_id,provider,resource_type,external_id) do update set
        external_name=excluded.external_name,environment=excluded.environment,
        canonical_url=excluded.canonical_url,binding_state=excluded.binding_state,
        configuration=excluded.configuration,verified_at=excluded.verified_at;
      v_resource_count := v_resource_count + 1;
    end loop;

    for v_phase_json in select value from jsonb_array_elements(coalesce(v_project_json->'phases','[]'::jsonb)) loop
      insert into public.projectos_phases (
        organization_id,project_id,phase_key,name,sequence,status,exit_criteria
      ) values (
        p_organization_id,v_project.id,v_phase_json->>'key',v_phase_json->>'name',
        coalesce(nullif(v_phase_json->>'sequence','')::integer,0),
        coalesce(v_phase_json->>'status','planned'),
        coalesce(v_phase_json->'exitCriteria','[]'::jsonb)
      ) on conflict (project_id,phase_key) do update set
        name=excluded.name,sequence=excluded.sequence,exit_criteria=excluded.exit_criteria;
    end loop;

    for v_task_json in select value from jsonb_array_elements(coalesce(v_project_json->'tasks','[]'::jsonb)) loop
      select id into v_phase_id from public.projectos_phases
        where project_id=v_project.id and phase_key=v_task_json->>'phaseKey';
      insert into public.projectos_tasks (
        organization_id,project_id,phase_id,task_key,title,description,sequence,
        priority,status,continuation_role,blocks_phase_exit,risk_class,
        builder_agent,builder_vendor,reviewer_agent,reviewer_vendor,
        completion_criteria,current_branch,current_pr_number,current_head_sha,result_summary
      ) values (
        p_organization_id,v_project.id,v_phase_id,v_task_json->>'key',v_task_json->>'title',
        coalesce(v_task_json->>'description',''),coalesce(nullif(v_task_json->>'sequence','')::integer,0),
        coalesce(nullif(v_task_json->>'priority','')::integer,50),coalesce(v_task_json->>'status','not_started'),
        coalesce(v_task_json->>'continuationRole','primary'),
        coalesce((v_task_json->>'blocksPhaseExit')::boolean,true),coalesce(v_task_json->>'riskClass','R1'),
        nullif(v_task_json->>'builderAgent',''),nullif(v_task_json->>'builderVendor',''),
        nullif(v_task_json->>'reviewerAgent',''),nullif(v_task_json->>'reviewerVendor',''),
        coalesce(v_task_json->'completionCriteria','[]'::jsonb),nullif(v_task_json->>'currentBranch',''),
        nullif(v_task_json->>'currentPullRequestNumber','')::integer,
        nullif(v_task_json->>'currentHeadSha',''),coalesce(v_task_json->'resultSummary','{}'::jsonb)
      ) on conflict (project_id,task_key) do update set
        phase_id=excluded.phase_id,title=excluded.title,description=excluded.description,
        sequence=excluded.sequence,priority=excluded.priority,
        continuation_role=excluded.continuation_role,blocks_phase_exit=excluded.blocks_phase_exit,
        risk_class=excluded.risk_class,builder_agent=excluded.builder_agent,
        builder_vendor=excluded.builder_vendor,reviewer_agent=excluded.reviewer_agent,
        reviewer_vendor=excluded.reviewer_vendor,completion_criteria=excluded.completion_criteria,
        current_branch=coalesce(excluded.current_branch,projectos_tasks.current_branch),
        current_pr_number=coalesce(excluded.current_pr_number,projectos_tasks.current_pr_number),
        current_head_sha=coalesce(excluded.current_head_sha,projectos_tasks.current_head_sha),
        result_summary=projectos_tasks.result_summary || excluded.result_summary;
      v_task_count := v_task_count + 1;
    end loop;

    for v_dependency_json in select value from jsonb_array_elements(coalesce(v_project_json->'dependencies','[]'::jsonb)) loop
      select id into v_task_id from public.projectos_tasks
        where project_id=v_project.id and task_key=v_dependency_json->>'taskKey';
      select id into v_dependency_id from public.projectos_tasks
        where project_id=v_project.id and task_key=v_dependency_json->>'dependsOnTaskKey';
      if v_task_id is not null and v_dependency_id is not null then
        insert into public.projectos_task_dependencies (
          organization_id,project_id,task_id,depends_on_task_id,dependency_type
        ) values (
          p_organization_id,v_project.id,v_task_id,v_dependency_id,
          coalesce(v_dependency_json->>'type','hard')
        ) on conflict (task_id,depends_on_task_id) do update set
          dependency_type=excluded.dependency_type;
      end if;
    end loop;
    perform public.projectos_recompute_project(p_organization_id,v_project.project_key);
  end loop;

  return jsonb_build_object('ok',true,'projects',v_project_count,'tasks',v_task_count,'resources',v_resource_count);
end;
$$;

create or replace function public.projectos_plan_intake(
  p_organization_id uuid,
  p_intake_id uuid,
  p_plan jsonb
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_intake public.projectos_intake_requests%rowtype;
  v_project public.projectos_projects%rowtype;
  v_phase_json jsonb;
  v_task_json jsonb;
  v_dependency_json jsonb;
  v_phase_id uuid;
  v_task_id uuid;
  v_dependency_id uuid;
begin
  perform private.assert_control_service_role();
  select * into strict v_intake from public.projectos_intake_requests
    where organization_id=p_organization_id and id=p_intake_id for update;
  select * into strict v_project from public.projectos_projects where id=v_intake.project_id;
  if jsonb_typeof(p_plan) <> 'object' then raise exception 'invalid_projectos_plan'; end if;

  for v_phase_json in select value from jsonb_array_elements(coalesce(p_plan->'phases','[]'::jsonb)) loop
    insert into public.projectos_phases (
      organization_id,project_id,phase_key,name,sequence,status,exit_criteria
    ) values (
      p_organization_id,v_project.id,v_phase_json->>'key',v_phase_json->>'name',
      coalesce(nullif(v_phase_json->>'sequence','')::integer,0),'planned',
      coalesce(v_phase_json->'exitCriteria','[]'::jsonb)
    ) on conflict (project_id,phase_key) do update set
      name=excluded.name,sequence=excluded.sequence,exit_criteria=excluded.exit_criteria;
  end loop;

  for v_task_json in select value from jsonb_array_elements(coalesce(p_plan->'tasks','[]'::jsonb)) loop
    select id into v_phase_id from public.projectos_phases
      where project_id=v_project.id and phase_key=v_task_json->>'phaseKey';
    insert into public.projectos_tasks (
      organization_id,project_id,phase_id,task_key,title,description,sequence,priority,
      status,continuation_role,blocks_phase_exit,risk_class,builder_agent,builder_vendor,
      reviewer_agent,reviewer_vendor,completion_criteria,result_summary
    ) values (
      p_organization_id,v_project.id,v_phase_id,v_task_json->>'key',v_task_json->>'title',
      coalesce(v_task_json->>'description',''),coalesce(nullif(v_task_json->>'sequence','')::integer,0),
      coalesce(nullif(v_task_json->>'priority','')::integer,50),'not_started',
      coalesce(v_task_json->>'continuationRole','primary'),
      coalesce((v_task_json->>'blocksPhaseExit')::boolean,true),coalesce(v_task_json->>'riskClass','R1'),
      nullif(v_task_json->>'builderAgent',''),nullif(v_task_json->>'builderVendor',''),
      nullif(v_task_json->>'reviewerAgent',''),nullif(v_task_json->>'reviewerVendor',''),
      coalesce(v_task_json->'completionCriteria','[]'::jsonb),
      jsonb_build_object('intakeId',v_intake.id,'planSource',coalesce(p_plan->>'source','projectos'))
    ) on conflict (project_id,task_key) do update set
      phase_id=excluded.phase_id,title=excluded.title,description=excluded.description,
      sequence=excluded.sequence,priority=excluded.priority,
      continuation_role=excluded.continuation_role,blocks_phase_exit=excluded.blocks_phase_exit,
      risk_class=excluded.risk_class,builder_agent=excluded.builder_agent,
      builder_vendor=excluded.builder_vendor,reviewer_agent=excluded.reviewer_agent,
      reviewer_vendor=excluded.reviewer_vendor,completion_criteria=excluded.completion_criteria,
      result_summary=projectos_tasks.result_summary || excluded.result_summary;
  end loop;

  for v_dependency_json in select value from jsonb_array_elements(coalesce(p_plan->'dependencies','[]'::jsonb)) loop
    select id into v_task_id from public.projectos_tasks
      where project_id=v_project.id and task_key=v_dependency_json->>'taskKey';
    select id into v_dependency_id from public.projectos_tasks
      where project_id=v_project.id and task_key=v_dependency_json->>'dependsOnTaskKey';
    if v_task_id is not null and v_dependency_id is not null then
      insert into public.projectos_task_dependencies (
        organization_id,project_id,task_id,depends_on_task_id,dependency_type
      ) values (
        p_organization_id,v_project.id,v_task_id,v_dependency_id,
        coalesce(v_dependency_json->>'type','hard')
      ) on conflict (task_id,depends_on_task_id) do update set dependency_type=excluded.dependency_type;
    end if;
  end loop;

  update public.projectos_intake_requests set
    status='planned',analysis=coalesce(p_plan->'analysis','{}'::jsonb),updated_at=now()
  where id=v_intake.id;
  return jsonb_build_object(
    'intakeId',v_intake.id,'projectKey',v_project.project_key,
    'projection',public.projectos_recompute_project(p_organization_id,v_project.project_key)
  );
end;
$$;

create or replace function public.projectos_recommend_agents(
  p_organization_id uuid,
  p_project_key text,
  p_role text default 'builder',
  p_limit integer default 5
) returns jsonb
language sql
security definer
set search_path = public, private, auth, pg_temp
as $$
  with authorized as (
    select 1 as ok where auth.role()='service_role' or private.is_org_member(p_organization_id)
  ), target as (
    select project.id from public.projectos_projects project, authorized
    where project.organization_id=p_organization_id and project.project_key=p_project_key
  ), scored as (
    select
      observation.agent_key,observation.vendor,observation.role,
      count(*) as observations,
      avg(case when observation.success then 1.0 else 0.0 end) as success_rate,
      avg(coalesce(observation.quality_score,case when observation.success then 75 else 25 end)) as quality,
      avg(observation.repair_attempts::numeric) as repairs,
      avg(observation.cost_cents::numeric) as cost,
      sum(case when observation.project_id=(select id from target) then 2 else 1 end) as relevance,
      (
        avg(case when observation.success then 1.0 else 0.0 end)*0.40
        + avg(coalesce(observation.quality_score,case when observation.success then 75 else 25 end))/100*0.40
        + least(1,count(*)::numeric/10)*0.10
        + least(1,sum(case when observation.project_id=(select id from target) then 1 else 0 end)::numeric/5)*0.10
        - least(0.20,avg(observation.repair_attempts::numeric)*0.04)
      ) as score
    from public.projectos_agent_observations observation, authorized
    where observation.organization_id=p_organization_id and observation.role=p_role
    group by observation.agent_key,observation.vendor,observation.role
  ), ranked as (
    select * from scored order by score desc,observations desc,agent_key
    limit greatest(1,least(p_limit,20))
  )
  select coalesce(jsonb_agg(jsonb_build_object(
    'agentKey',agent_key,'vendor',vendor,'role',role,'score',round(score,4),
    'observations',observations,'successRate',round(success_rate,4),
    'averageQuality',round(quality,2),'averageRepairs',round(repairs,2),
    'averageCostCents',round(cost,2),'projectRelevance',relevance
  ) order by score desc,observations desc,agent_key),'[]'::jsonb)
  from ranked;
$$;

create or replace function public.projectos_get_context(
  p_organization_id uuid,
  p_project_key text,
  p_task_key text default null
) returns jsonb
language plpgsql
security definer
set search_path = public, private, auth, pg_temp
as $$
declare
  v_project_id uuid;
  v_task jsonb;
  v_projection jsonb;
begin
  if auth.role()<>'service_role' and not private.is_org_member(p_organization_id) then
    raise exception 'projectos_forbidden';
  end if;
  select id into strict v_project_id from public.projectos_projects
    where organization_id=p_organization_id and project_key=p_project_key;
  v_projection := public.projectos_recompute_project(p_organization_id,p_project_key);
  if p_task_key is not null then
    select to_jsonb(task) into v_task from public.projectos_tasks task
      where task.project_id=v_project_id and task.task_key=p_task_key;
  end if;
  return jsonb_build_object(
    'projection',v_projection,'task',v_task,
    'projectLessons',coalesce((select jsonb_agg(to_jsonb(lesson) order by lesson.confidence desc,lesson.evidence_count desc)
      from public.projectos_lessons lesson where lesson.organization_id=p_organization_id
      and lesson.project_id=v_project_id and lesson.status in ('candidate','promoted')),'[]'::jsonb),
    'portfolioLessons',coalesce((select jsonb_agg(to_jsonb(lesson) order by lesson.confidence desc,lesson.evidence_count desc)
      from public.projectos_lessons lesson where lesson.organization_id=p_organization_id
      and lesson.scope in ('portfolio','operational') and lesson.status='promoted'),'[]'::jsonb),
    'builderRecommendations',public.projectos_recommend_agents(p_organization_id,p_project_key,'builder',5),
    'reviewerRecommendations',public.projectos_recommend_agents(p_organization_id,p_project_key,'reviewer',5)
  );
end;
$$;

grant execute on function public.projectos_apply_manifest(uuid,jsonb,uuid) to service_role;
grant execute on function public.projectos_plan_intake(uuid,uuid,jsonb) to service_role;
grant execute on function public.projectos_recommend_agents(uuid,text,text,integer) to authenticated,service_role;
grant execute on function public.projectos_get_context(uuid,text,text) to authenticated,service_role;
