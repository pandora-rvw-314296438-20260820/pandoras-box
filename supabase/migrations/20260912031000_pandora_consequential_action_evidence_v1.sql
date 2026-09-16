-- Pandora consequential action evidence v1
-- Promote terminal ProjectOS execution truth into the existing public evidence and hash-chained activity models.
-- Raw provider payloads remain outside these owner-facing records; only bounded identifiers, outcomes and hashes are promoted.

create or replace function private.pandora_record_execution_plan_evidence_v1(
  p_plan_id uuid
) returns uuid
language plpgsql
security definer
set search_path = pg_catalog, public, private, extensions, pg_temp
as $$
declare
  v_plan private.execution_plans%rowtype;
  v_intake public.projectos_intake_requests%rowtype;
  v_project public.projectos_projects%rowtype;
  v_provider text;
  v_summary jsonb;
  v_source_sha text;
  v_source_version text;
  v_source_url text;
  v_external_provider_id text;
  v_readback_status text;
  v_readback_verified boolean;
  v_result_hash text;
  v_evidence_id uuid;
  v_payload jsonb;
begin
  select * into v_plan from private.execution_plans where id=p_plan_id;
  if v_plan.id is null or v_plan.status not in ('completed','failed') then return null; end if;

  select * into v_intake from public.projectos_intake_requests
  where id=v_plan.intake_id and organization_id=v_plan.organization_id;
  if v_intake.id is null then return null; end if;
  select * into v_project from public.projectos_projects
  where id=v_intake.project_id and organization_id=v_plan.organization_id;
  if v_project.id is null then return null; end if;

  v_summary := coalesce(v_plan.result_summary,'{}'::jsonb);
  v_provider := case
    when lower(v_plan.tool) like '%github%' then 'github'
    when lower(v_plan.tool) like '%supabase%' then 'supabase'
    when lower(v_plan.tool) like '%vercel%' then 'vercel'
    when lower(v_plan.tool) like '%posthog%' then 'posthog'
    when lower(v_plan.tool) like '%google%drive%' then 'google_drive'
    when lower(v_plan.tool) like '%google%sheet%' then 'google_sheets'
    else 'projectos' end;

  v_source_sha := lower(trim(coalesce(
    v_summary->>'headSha',v_summary->>'head_sha',v_summary->>'sourceSha',v_summary->>'source_sha',v_summary#>>'{providerReadback,headSha}',v_summary#>>'{providerReadback,sourceSha}','')));
  if v_source_sha !~ '^[0-9a-f]{40}$' then v_source_sha := null; end if;

  v_source_version := left(trim(coalesce(
    v_summary->>'sourceVersion',v_summary->>'source_version',v_summary->>'version',v_summary#>>'{providerReadback,version}','')),160);
  if v_source_version='' then v_source_version := null; end if;

  v_source_url := trim(coalesce(v_summary->>'sourceUrl',v_summary->>'source_url',v_summary#>>'{providerReadback,sourceUrl}',''));
  if v_source_url !~ '^https://[^[:space:]]+$' then v_source_url := null; end if;

  v_external_provider_id := left(trim(coalesce(
    v_summary->>'deploymentId',v_summary->>'externalId',v_summary->>'providerId',v_summary#>>'{providerReadback,deploymentId}',v_summary#>>'{providerReadback,externalId}','')),200);
  if v_external_provider_id='' then v_external_provider_id := null; end if;

  v_readback_status := left(trim(coalesce(
    v_summary->>'providerStatus',v_summary#>>'{providerReadback,status}',v_summary->>'status','')),120);
  if v_readback_status='' then v_readback_status := null; end if;
  v_readback_verified := coalesce(
    case when jsonb_typeof(v_summary->'verified')='boolean' then (v_summary->>'verified')::boolean end,
    case when jsonb_typeof(v_summary#>'{providerReadback,verified}')='boolean' then (v_summary#>>'{providerReadback,verified}')::boolean end,
    v_plan.status='completed'
  );
  v_result_hash := encode(extensions.digest(convert_to(v_summary::text,'UTF8'),'sha256'),'hex');

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'summary','Pandora '||case when v_plan.status='completed' then 'verified completion of ' else 'recorded failure of ' end||replace(v_plan.tool,'.',' '),
    'planId',v_plan.id,'requestId',v_plan.request_id,'intakeId',v_plan.intake_id,
    'tool',v_plan.tool,'risk',v_plan.risk,'outcome',v_plan.status,
    'durationMs',v_plan.duration_ms,'payloadHash',v_plan.payload_hash,
    'resultSummarySha256',v_result_hash,'sourceVersion',v_source_version,
    'providerReadback',jsonb_strip_nulls(jsonb_build_object(
      'provider',v_provider,'externalId',v_external_provider_id,'status',v_readback_status,
      'verified',v_readback_verified,'observedAt',coalesce(v_plan.completed_at,v_plan.updated_at)
    ))
  ));

  insert into public.projectos_evidence(
    organization_id,project_id,evidence_type,provider,external_id,source_url,repository,head_sha,status,verdict,payload_redacted,observed_at
  ) values (
    v_plan.organization_id,v_project.id,'projectos_execution_outcome',v_provider,v_plan.id::text,v_source_url,
    v_project.repository,v_source_sha,
    case when v_plan.status='completed' then 'passing' else 'failing' end,
    case when v_plan.status='completed' then 'pass' else 'fail' end,
    v_payload,coalesce(v_plan.completed_at,v_plan.updated_at,now())
  )
  on conflict (organization_id,provider,evidence_type,external_id) where external_id is not null do nothing
  returning id into v_evidence_id;

  if v_evidence_id is null then
    select id into v_evidence_id from public.projectos_evidence
    where organization_id=v_plan.organization_id and provider=v_provider
      and evidence_type='projectos_execution_outcome' and external_id=v_plan.id::text limit 1;
    return v_evidence_id;
  end if;

  perform private.append_audit_event(
    v_plan.organization_id,null,null,'system'::public.audit_actor_type,null,
    'projectos_execution_evidence_recorded',
    jsonb_build_object(
      'summary',v_payload->>'summary','evidenceId',v_evidence_id,'planId',v_plan.id,
      'projectId',v_project.id,'provider',v_provider,'outcome',v_plan.status,
      'headSha',v_source_sha,'sourceVersion',v_source_version,'resultSummarySha256',v_result_hash
    )
  );
  return v_evidence_id;
end;
$$;

revoke all on function private.pandora_record_execution_plan_evidence_v1(uuid) from public,anon,authenticated;
grant execute on function private.pandora_record_execution_plan_evidence_v1(uuid) to service_role;

create or replace function private.pandora_execution_plan_evidence_trigger_v1()
returns trigger
language plpgsql
security definer
set search_path = pg_catalog, public, private, pg_temp
as $$
begin
  if new.status in ('completed','failed') and (tg_op='INSERT' or old.status is distinct from new.status) then
    perform private.pandora_record_execution_plan_evidence_v1(new.id);
  end if;
  return new;
end;
$$;
revoke all on function private.pandora_execution_plan_evidence_trigger_v1() from public,anon,authenticated;

drop trigger if exists execution_plan_evidence_v1 on private.execution_plans;
create trigger execution_plan_evidence_v1
after insert or update of status on private.execution_plans
for each row execute function private.pandora_execution_plan_evidence_trigger_v1();

-- Backfill only missing terminal-plan evidence. The recorder is idempotent by the existing evidence unique key.
do $$
declare v_id uuid;
begin
  for v_id in
    select p.id from private.execution_plans p
    where p.status in ('completed','failed')
      and not exists (
        select 1 from public.projectos_evidence e
        where e.organization_id=p.organization_id and e.evidence_type='projectos_execution_outcome' and e.external_id=p.id::text
      )
    order by p.completed_at nulls last,p.created_at
  loop
    perform private.pandora_record_execution_plan_evidence_v1(v_id);
  end loop;
end $$;

create or replace function public.pandora_action_evidence_v1(
  p_organization_id uuid,
  p_limit integer default 100
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, auth, pg_temp
as $$
declare v_uid uuid := auth.uid(); v_role text;
begin
  if v_uid is null then raise exception 'pandora_evidence_sign_in_required' using errcode='42501'; end if;
  select m.role into v_role from public.memberships m
  where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active' limit 1;
  if v_role not in ('owner','admin') then raise exception 'pandora_evidence_owner_required' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',e.id,'projectId',e.project_id,'projectName',p.name,'projectKey',p.project_key,
      'evidenceType',e.evidence_type,'provider',e.provider,'externalId',e.external_id,
      'repository',e.repository,'headSha',e.head_sha,'status',e.status,'verdict',e.verdict,
      'details',e.payload_redacted,'observedAt',e.observed_at
    ) order by e.observed_at desc)
    from (
      select * from public.projectos_evidence
      where organization_id=p_organization_id and evidence_type='projectos_execution_outcome' and invalidated_at is null
      order by observed_at desc limit least(greatest(coalesce(p_limit,100),1),500)
    ) e join public.projectos_projects p on p.id=e.project_id and p.organization_id=e.organization_id
  ),'[]'::jsonb);
end;
$$;
revoke all on function public.pandora_action_evidence_v1(uuid,integer) from public,anon;
grant execute on function public.pandora_action_evidence_v1(uuid,integer) to authenticated;
