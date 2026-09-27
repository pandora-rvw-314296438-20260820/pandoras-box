
create or replace function private.enqueue_execution_learning()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_context private.execution_plan_contexts%rowtype;
  v_project_id uuid;
  v_project_key text;
  v_completed_at text;
  v_result_fingerprint text;
  v_error_fingerprint text;
  v_payload jsonb;
  v_outbox_id uuid;
  v_product_key text;
begin
  if new.status not in ('completed','failed')
     or old.status is not distinct from new.status then
    return new;
  end if;

  select * into v_context
  from private.execution_plan_contexts
  where plan_id=new.id
    and organization_id=new.organization_id
    and request_id=new.request_id;

  if v_context.plan_id is null then
    raise exception 'pandora_memory_context_missing_at_completion'
      using errcode='55000';
  end if;

  if new.intake_id is not null then
    select intake.project_id,project.project_key
      into v_project_id,v_project_key
    from public.projectos_intake_requests intake
    join public.projectos_projects project
      on project.id=intake.project_id
     and project.organization_id=intake.organization_id
    where intake.id=new.intake_id
      and intake.organization_id=new.organization_id;
    v_product_key:='projectos';
  else
    v_project_id:=null;
    v_project_key:=coalesce(
      nullif(v_context.context_envelope#>>'{queryBasis,identifiers,projectKey}',''),
      nullif(v_context.context_envelope#>>'{queryBasis,identifiers,project_key}','')
    );
    v_product_key:='pandora';
  end if;

  if coalesce(v_project_key,'')='' then
    raise exception 'pandora_project_context_missing_at_completion'
      using errcode='55000';
  end if;

  v_completed_at:=to_char(
    coalesce(new.completed_at,clock_timestamp()) at time zone 'UTC',
    'YYYY-MM-DD"T"HH24:MI:SS.MS"Z"'
  );

  v_result_fingerprint:=case when new.result_summary is null then null
    else encode(extensions.digest(new.result_summary::text,'sha256'),'hex') end;
  v_error_fingerprint:=case when new.error is null then null
    else encode(extensions.digest(new.error,'sha256'),'hex') end;

  v_payload:=jsonb_strip_nulls(jsonb_build_object(
    'schema_version',1,
    'product_key',v_product_key,
    'source_event_id',new.id,
    'source_request_id',new.request_id,
    'organization_id',new.organization_id,
    'intake_id',new.intake_id,
    'project_id',v_project_id,
    'project_key',v_project_key,
    'tool',new.tool,
    'risk',new.risk,
    'outcome_status',new.status,
    'duration_ms',greatest(coalesce(new.duration_ms,0),0),
    'completed_at',v_completed_at,
    'context_status',v_context.context_status,
    'context_hash',v_context.context_hash,
    'result_fingerprint',v_result_fingerprint,
    'error_fingerprint',v_error_fingerprint,
    'privacy_policy','metadata_only_v1'
  ));

  insert into private.execution_learning_outbox(
    plan_id,organization_id,request_id,intake_id,project_id,project_key,payload,
    delivery_status,next_attempt_at,created_at,updated_at
  ) values(
    new.id,new.organization_id,new.request_id,new.intake_id,v_project_id,v_project_key,
    v_payload,'pending',now(),now(),now()
  )
  on conflict(plan_id) do update
    set payload=excluded.payload,
        project_id=excluded.project_id,
        project_key=excluded.project_key,
        updated_at=now()
  returning id into v_outbox_id;

  begin
    perform private.dispatch_execution_learning(v_outbox_id);
  exception when others then
    update private.execution_learning_outbox
      set delivery_status='pending',
          last_error=left(sqlerrm,1000),
          next_attempt_at=now(),
          updated_at=now()
      where id=v_outbox_id;
  end;

  return new;
end;
$fn$;
