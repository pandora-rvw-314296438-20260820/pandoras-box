-- Pandora consequential action evidence v2 (additive correction of deployed v1)
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
  v_failure jsonb;
  v_reconciliation_required boolean;
  v_result_hash text;
  v_evidence_id uuid;
  v_payload jsonb;
begin
  select * into v_plan from private.execution_plans where id=p_plan_id;
  if v_plan.id is null or v_plan.status not in ('completed','failed')
    or v_plan.risk is null or v_plan.risk not in ('write','destructive') then return null; end if;

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

  v_source_version := trim(coalesce(
    v_summary->>'sourceVersion',v_summary->>'source_version',v_summary->>'version',v_summary#>>'{providerReadback,version}',''));
  if length(v_source_version)>64 or v_source_version !~ '^[vV]?[0-9]+([.][0-9]+){0,3}(-(alpha|beta|rc|preview)([.][0-9]+)?)?([+][0-9]+)?$'
    then v_source_version := null; end if;

  -- Never copy provider URLs: they can contain userinfo, signed queries or private paths.
  -- Construct a source permalink only from the existing repository binding and exact SHA.
  v_source_url := case when v_provider='github' and v_source_sha is not null
    and v_project.repository ~ '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'
    then 'https://github.com/'||v_project.repository||'/commit/'||v_source_sha else null end;

  v_external_provider_id := trim(coalesce(
    v_summary->>'deploymentId',v_summary->>'externalId',v_summary->>'providerId',v_summary#>>'{providerReadback,deploymentId}',v_summary#>>'{providerReadback,externalId}',''));
  if not ((v_provider='vercel' and v_external_provider_id ~ '^dpl_[A-Za-z0-9]{8,80}$')
    or (v_provider='github' and v_external_provider_id ~ '^[0-9]{1,20}$'))
    then v_external_provider_id := null; end if;

  v_readback_status := lower(trim(coalesce(
    v_summary#>>'{providerReadback,status}',v_summary->>'providerStatus','')));
  if v_readback_status not in ('ready','active','active_healthy','completed','succeeded','success','failed','error','canceled','cancelled','queued','building','pending','open','closed','merged','verified')
    then v_readback_status := null; end if;
  -- Plan completion and a generic verified flag do not prove a provider readback.
  v_readback_verified := coalesce(v_summary#>'{providerReadback,verified}'='true'::jsonb,false);
  begin
    v_failure := coalesce(v_plan.error::jsonb,'{}'::jsonb);
  exception when invalid_text_representation then
    v_failure := '{}'::jsonb;
  end;
  -- A failed dispatch can already have changed the provider. Preserve that uncertainty.
  v_reconciliation_required := v_plan.status='failed' and not coalesce(
    v_failure->>'terminalClassification'='failed_without_side_effect'
    and v_failure->>'providerOutcome'='failed_before_side_effects'
    and v_failure->'reconciliationRequired'='false'::jsonb,false);
  v_result_hash := encode(extensions.digest(convert_to(v_summary::text,'UTF8'),'sha256'),'hex');

  v_payload := jsonb_strip_nulls(jsonb_build_object(
    'summary','Pandora '||case
      when v_reconciliation_required then 'requires provider reconciliation for '
      when v_plan.status='failed' then 'recorded failure of '
      when v_readback_verified then 'recorded provider-verified completion of '
      else 'recorded completion awaiting provider verification of ' end||replace(v_plan.tool,'.',' '),
    'planId',v_plan.id,'requestId',v_plan.request_id,'intakeId',v_plan.intake_id,
    'tool',v_plan.tool,'risk',v_plan.risk,'outcome',v_plan.status,
    'supersedesEvidenceId',(select e.id from public.projectos_evidence e
      where e.organization_id=v_plan.organization_id and e.provider=v_provider
      and e.evidence_type='projectos_execution_outcome' and e.external_id=v_plan.id::text limit 1),
    'durationMs',v_plan.duration_ms,'payloadHash',v_plan.payload_hash,
    'resultSummarySha256',v_result_hash,'sourceVersion',v_source_version,
    'evidenceSchemaVersion',2,
    'reconciliationRequired',v_reconciliation_required,'automaticRetryAllowed',false,
    'providerReadback',jsonb_strip_nulls(jsonb_build_object(
      'provider',v_provider,'externalId',v_external_provider_id,'status',v_readback_status,
      'verified',v_readback_verified,'recordedAt',coalesce(v_plan.completed_at,v_plan.updated_at)
    ))
  ));

  insert into public.projectos_evidence(
    organization_id,project_id,evidence_type,provider,external_id,source_url,repository,head_sha,status,verdict,payload_redacted,observed_at
  ) values (
    v_plan.organization_id,v_project.id,'projectos_execution_outcome_v2',v_provider,v_plan.id::text,v_source_url,
    v_project.repository,v_source_sha,
    case when v_reconciliation_required then 'blocked' when v_plan.status='failed' then 'failing'
      when v_readback_verified then 'passing' else 'observed' end,
    case when v_reconciliation_required then 'reconciliation_required' when v_plan.status='failed' then 'fail'
      when v_readback_verified then 'pass' else 'unverified' end,
    v_payload,coalesce(v_plan.completed_at,v_plan.updated_at,now())
  )
  on conflict (organization_id,provider,evidence_type,external_id) where external_id is not null do nothing
  returning id into v_evidence_id;

  if v_evidence_id is null then
    select id into v_evidence_id from public.projectos_evidence
    where organization_id=v_plan.organization_id and provider=v_provider
      and evidence_type='projectos_execution_outcome_v2' and external_id=v_plan.id::text limit 1;
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

-- Repair historical outcomes in explicitly bounded batches; no provider action is replayed.
create or replace function private.pandora_backfill_action_evidence_v2(p_limit integer default 100)
returns integer
language plpgsql
security definer
set search_path = pg_catalog, public, private, pg_temp
as $$
declare v_id uuid; v_count integer := 0;
begin
  for v_id in
    select p.id from private.execution_plans p
    join public.projectos_intake_requests i on i.id=p.intake_id and i.organization_id=p.organization_id
    join public.projectos_projects j on j.id=i.project_id and j.organization_id=p.organization_id
    where p.status in ('completed','failed') and p.risk in ('write','destructive')
      and not exists (
        select 1 from public.projectos_evidence e
        where e.organization_id=p.organization_id and e.evidence_type='projectos_execution_outcome_v2'
          and e.external_id=p.id::text
      )
    order by p.completed_at desc nulls last,p.id
    limit least(greatest(coalesce(p_limit,100),1),500)
  loop
    if private.pandora_record_execution_plan_evidence_v1(v_id) is not null then
      v_count := v_count+1;
    end if;
  end loop;
  return v_count;
end;
$$;
revoke all on function private.pandora_backfill_action_evidence_v2(integer) from public,anon,authenticated;
grant execute on function private.pandora_backfill_action_evidence_v2(integer) to service_role;

-- Preserve the prior rows and immutable audit events, but remove v1's unsafe assertions
-- from current owner evidence and learning queries. v2 records link to their prior IDs.
do $$
declare v_org uuid; v_count integer;
begin
  for v_org in select distinct organization_id from public.projectos_evidence
    where evidence_type='projectos_execution_outcome' and invalidated_at is null
  loop
    update public.projectos_evidence
    set invalidated_at=now(),invalidation_reason='superseded_by_action_evidence_v2',status='superseded'
    where organization_id=v_org and evidence_type='projectos_execution_outcome' and invalidated_at is null;
    get diagnostics v_count=row_count;
    perform private.append_audit_event(v_org,null,null,'system'::public.audit_actor_type,null,
      'projectos_execution_evidence_v1_superseded',
      jsonb_build_object('summary','Prior execution assertions superseded; bounded reclassification required',
        'evidenceSchemaVersion',2,'supersededCount',v_count));
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
  if v_role is null or v_role not in ('owner','admin') then raise exception 'pandora_evidence_owner_required' using errcode='42501'; end if;
  return coalesce((
    select jsonb_agg(jsonb_build_object(
      'id',e.id,'projectId',e.project_id,'projectName',p.name,'projectKey',p.project_key,
      'evidenceType',e.evidence_type,'provider',e.provider,'externalId',e.external_id,
      'repository',e.repository,'headSha',e.head_sha,'status',e.status,'verdict',e.verdict,
      'details',e.payload_redacted,'observedAt',e.observed_at
    ) order by e.observed_at desc)
    from (
      select * from public.projectos_evidence
      where organization_id=p_organization_id and evidence_type='projectos_execution_outcome_v2' and invalidated_at is null
      order by observed_at desc limit least(greatest(coalesce(p_limit,100),1),500)
    ) e join public.projectos_projects p on p.id=e.project_id and p.organization_id=e.organization_id
  ),'[]'::jsonb);
end;
$$;
revoke all on function public.pandora_action_evidence_v1(uuid,integer) from public,anon;
grant execute on function public.pandora_action_evidence_v1(uuid,integer) to authenticated;
