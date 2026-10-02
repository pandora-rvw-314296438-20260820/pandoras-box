do $$
begin
  if to_regprocedure('public.pandora_activity_admit_event_v1_legacy_20260917(uuid,jsonb)') is null then
    alter function public.pandora_activity_admit_event_v1(uuid,jsonb)
      rename to pandora_activity_admit_event_v1_legacy_20260917;
  end if;
end $$;

create or replace function public.pandora_activity_admit_event_v1(p_job_id uuid,p_event jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'pg_catalog','public','auth','pg_temp'
as $$
declare
  v_event jsonb := p_event;
  v_result jsonb;
  v_message text := coalesce(p_event->>'message','');
begin
  if coalesce(auth.role(),'') <> 'service_role' then
    raise exception 'pandora_activity_service_role_required' using errcode='42501';
  end if;

  if v_message='Execution handoff persisted; downstream action is not complete.'
     and coalesce(p_event->'provenance'->>'sourceId','')='pandora-capability-router' then
    select execution_result into v_result
    from public.pandora_activity_jobs
    where id=p_job_id;

    if coalesce(v_result->>'intent','')='direct_github_code_change'
       and coalesce((v_result->'providerReadback'->>'verified')::boolean,false)=true then
      v_event := jsonb_set(v_event,'{message}',to_jsonb('PLP code change committed directly to GitHub and verified.'::text),false);
      if jsonb_typeof(v_event->'outcome')='object' then
        v_event := jsonb_set(v_event,'{outcome,summary}',to_jsonb('PLP code change committed directly to GitHub and verified.'::text),false);
      end if;
    end if;
  end if;

  return public.pandora_activity_admit_event_v1_legacy_20260917(p_job_id,v_event);
end;
$$;

revoke all on function public.pandora_activity_admit_event_v1(uuid,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_activity_admit_event_v1(uuid,jsonb) to service_role;
revoke all on function public.pandora_activity_admit_event_v1_legacy_20260917(uuid,jsonb) from public,anon,authenticated;
;
