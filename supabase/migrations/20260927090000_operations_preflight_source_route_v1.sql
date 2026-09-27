-- Operations Room preflight persistence and external-source routing v1.
-- Source-tracks the live preflight behavior and prevents native source execution
-- from reclaiming tasks explicitly routed to an external ChatGPT worker.

CREATE OR REPLACE FUNCTION public.pandora_ops_preflight_next_v1(p_organization_id uuid, p_project_id uuid, p_worker_key text, p_principal_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w private.pandora_ops_workspaces%rowtype;
  k private.pandora_ops_workers%rowtype;
  t private.pandora_ops_tasks%rowtype;
  deps jsonb;
  gate jsonb;
  auth_caps jsonb;
  incomplete_count integer;
  execution_class text;
  safe_work jsonb;
  receipt jsonb;
  event_key text;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_PREFLIGHT_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;

  perform 1 from private.pandora_ops_project_bindings
   where organization_id=p_organization_id and project_id=p_project_id and state='active'
   for share;
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  select * into w from private.pandora_ops_workspaces
   where organization_id=p_organization_id and project_id=p_project_id;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;
  if w.paused then return jsonb_build_object('state','paused'); end if;

  select * into k from private.pandora_ops_workers
   where organization_id=p_organization_id and project_id=p_project_id
     and worker_key=p_worker_key and principal_key=p_principal_key;
  if not found or not k.acknowledged or not k.connected or k.health<>'ready'
     or k.heartbeat_at is null or k.heartbeat_at<clock_timestamp()-interval '60 seconds' then
    raise exception 'OPS_PREFLIGHT_WORKER_UNAVAILABLE' using errcode='42501';
  end if;

  select q.* into t
  from private.pandora_ops_tasks q
  where q.organization_id=p_organization_id and q.project_id=p_project_id
    and q.status='queued'
    and q.task_key !~ '^OPS-(RDP-(AUTO|DIRECT)|CHATGPT-DIRECT)-'
    and not exists (
      select 1 from private.pandora_ops_events e
      where e.organization_id=q.organization_id and e.project_id=q.project_id
        and e.event_key='preflight:'||q.task_key||':'||q.spec_digest
        and e.event_type='task_preflight_completed'
    )
  order by (q.spec->>'priority')::integer,q.queued_at,q.task_key
  for update skip locked
  limit 1;

  if not found then
    return jsonb_build_object(
      'state','idle',
      'preflighted',(
        select count(*) from private.pandora_ops_events e
        where e.organization_id=p_organization_id and e.project_id=p_project_id
          and e.event_type='task_preflight_completed'
      )
    );
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object('taskId',d.dependency_key,'status',dep.status)
    order by d.dependency_key
  ),'[]'::jsonb),
  count(*) filter(where dep.status<>'complete')
  into deps,incomplete_count
  from private.pandora_ops_dependencies d
  join private.pandora_ops_tasks dep
    on dep.organization_id=d.organization_id
   and dep.project_id=d.project_id
   and dep.task_key=d.dependency_key
  where d.organization_id=p_organization_id and d.project_id=p_project_id
    and d.task_key=t.task_key;

  select coalesce(
    (select jsonb_build_object(
      'kind',g.gate_kind,'state',g.state,'evidenceRef',g.evidence_ref,'decidedAt',g.decided_at
    )
    from private.pandora_ops_human_gates g
    where g.organization_id=p_organization_id and g.project_id=p_project_id
      and g.task_key=t.task_key and g.state<>'approved'
    order by g.updated_at desc limit 1),
    'null'::jsonb
  ) into gate;

  select coalesce(jsonb_agg(value order by value),'[]'::jsonb)
  into auth_caps
  from jsonb_array_elements_text(t.spec->'requiredCapabilities') value
  where value in ('privacy.approve','owner.meta_oauth','spend.authorized');

  if gate <> 'null'::jsonb or jsonb_array_length(auth_caps)>0 then
    execution_class:='authority_wait';
    safe_work:=jsonb_build_array(
      'prepare_evidence_packet',
      'review_exact_source_and_tests',
      'do_not_infer_or_satisfy_human_authority'
    );
  elsif incomplete_count>0 then
    execution_class:='dependency_wait';
    safe_work:=jsonb_build_array(
      'prepare_implementation_and_verification_plan',
      'inspect_existing_source_and_provider_evidence',
      'do_not_mutate_external_provider_before_dependencies_complete'
    );
  elsif t.spec->>'risk'='read'
    and t.spec->>'verificationProfile'='automation'
    and (t.spec->'requiredCapabilities') ? 'rdp.execute' then
    execution_class:='reasoning_rdp_ready';
    safe_work:=jsonb_build_array(
      'route_reasoning_through_governed_inference_policy',
      'materialize_only_a_bounded_rdp_execution_profile',
      'require_independent_rdp_release_verification_and_verified_memory_outcome'
    );
  elsif t.spec->>'risk'='source'
    and t.spec->>'lane'=any(k.lanes)
    and array(select jsonb_array_elements_text(t.spec->'requiredCapabilities')) <@ k.capabilities then
    execution_class:='source_ready';
    safe_work:=jsonb_build_array(
      'eligible_for_generic_source_execution',
      'create_exact_source_branch_and_pr',
      'require_ci_and_independent_release_verification'
    );
  elsif t.spec->>'risk' in ('production','destructive') then
    execution_class:='provider_gate';
    safe_work:=jsonb_build_array(
      'perform_read_only_provider_precheck',
      'prepare_mutation_request_and_receipt_contract',
      'do_not_execute_production_mutation_without_specific_authority'
    );
  else
    execution_class:='read_ready';
    safe_work:=jsonb_build_array(
      'perform_read_only_analysis',
      'capture_provider_readback',
      'attach_verification_evidence'
    );
  end if;

  receipt:=jsonb_build_object(
    'taskId',t.task_key,
    'title',t.spec->>'title',
    'specDigest',t.spec_digest,
    'taskStatus',t.status,
    'risk',t.spec->>'risk',
    'lane',t.spec->>'lane',
    'executionClass',execution_class,
    'dependencies',deps,
    'incompleteDependencyCount',incomplete_count,
    'humanGate',gate,
    'authorityCapabilities',auth_caps,
    'requiredCapabilities',t.spec->'requiredCapabilities',
    'acceptance',t.spec->'acceptance',
    'safeWork',safe_work,
    'preflightWorker',p_worker_key,
    'preflightedAt',clock_timestamp()
  );

  event_key:='preflight:'||t.task_key||':'||t.spec_digest;
  perform private.pandora_ops_event_v1(
    p_organization_id,p_project_id,event_key,t.task_key,'task_preflight_completed',receipt::text
  );

  return receipt||jsonb_build_object('state','preflighted');
end;
$function$;

revoke all on function public.pandora_ops_preflight_next_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_preflight_next_v1(uuid,uuid,text,text) to service_role;

CREATE OR REPLACE FUNCTION public.pandora_ops_generic_source_candidate_v1(p_organization_id uuid, p_project_id uuid, p_worker_key text, p_principal_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  w private.pandora_ops_workspaces%rowtype;
  k private.pandora_ops_workers%rowtype;
  t private.pandora_ops_tasks%rowtype;
begin
  if session_user not in ('postgres','service_role')
     and coalesce(auth.jwt()->>'role','') <> 'service_role' then
    raise exception 'OPS_GENERIC_SOURCE_SERVICE_ROLE_REQUIRED' using errcode='42501';
  end if;
  perform 1 from private.pandora_ops_project_bindings
    where organization_id=p_organization_id and project_id=p_project_id and state='active' for share;
  if not found then raise exception 'OPS_PROJECT_SCOPE_DENIED' using errcode='42501'; end if;

  select * into w from private.pandora_ops_workspaces
    where organization_id=p_organization_id and project_id=p_project_id;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;
  if w.paused then return jsonb_build_object('state','paused'); end if;

  select * into k from private.pandora_ops_workers
    where organization_id=p_organization_id and project_id=p_project_id
      and worker_key=p_worker_key and principal_key=p_principal_key;
  if not found or not k.acknowledged or not k.connected or k.health<>'ready'
     or k.heartbeat_at is null or k.heartbeat_at<clock_timestamp()-interval '60 seconds' then
    raise exception 'OPS_GENERIC_SOURCE_WORKER_UNAVAILABLE' using errcode='42501';
  end if;

  select q.* into t
  from private.pandora_ops_tasks q
  where q.organization_id=p_organization_id and q.project_id=p_project_id
    and q.status='queued' and not q.cancel_requested
    and q.spec->>'risk'='source'
    and q.spec#>>'{source,repository}'='pandora-rvw-314296438-20260820/pandoras-box'
    and q.spec->>'lane'=any(k.lanes)
    and array(select jsonb_array_elements_text(q.spec->'requiredCapabilities')) <@ k.capabilities
    and q.attempts < (q.spec->>'maxAttempts')::integer
    and coalesce(q.verification->>'executionRoute','') <> 'external_worker_required'
    and not exists (
      select 1 from private.pandora_ops_dependencies d
      join private.pandora_ops_tasks dep
        on dep.organization_id=d.organization_id and dep.project_id=d.project_id and dep.task_key=d.dependency_key
      where d.organization_id=q.organization_id and d.project_id=q.project_id
        and d.task_key=q.task_key and dep.status<>'complete'
    )
    and not exists (
      select 1 from private.pandora_ops_human_gates g
      where g.organization_id=q.organization_id and g.project_id=q.project_id
        and g.task_key=q.task_key and g.state<>'approved'
    )
  order by (q.spec->>'priority')::integer, q.queued_at, q.task_key
  limit 1;

  if not found then
    return jsonb_build_object(
      'state','idle',
      'reason','no_dependency_ready_authorized_source_task',
      'humanBlocked',(
        select count(*) from private.pandora_ops_tasks q
        join private.pandora_ops_human_gates g
          on g.organization_id=q.organization_id and g.project_id=q.project_id and g.task_key=q.task_key
        where q.organization_id=p_organization_id and q.project_id=p_project_id
          and q.status='queued' and g.state<>'approved'
      )
    );
  end if;

  return jsonb_build_object(
    'state','ready',
    'taskId',t.task_key,
    'taskRevision',t.revision,
    'controlRevision',w.revision,
    'spec',t.spec
  );
end;
$function$;

revoke all on function public.pandora_ops_generic_source_candidate_v1(uuid,uuid,text,text) from public,anon,authenticated;
grant execute on function public.pandora_ops_generic_source_candidate_v1(uuid,uuid,text,text) to service_role;
