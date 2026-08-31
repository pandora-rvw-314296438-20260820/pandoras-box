-- Pandora Worker I / D: one-time forward convergence for pre-materialization builds.
-- New builds materialize trusted primitive source in the source convergence worker itself.
-- This migration only queues active legacy specs whose latest succeeded build predates
-- project-version primitive composition.

alter table public.pandora_source_generation_queue
  drop constraint if exists pandora_source_generation_queue_reason_check;
alter table public.pandora_source_generation_queue
  drop constraint if exists pandora_source_generation_queue_check;

alter table public.pandora_source_generation_queue
  add constraint pandora_source_generation_queue_reason_check
  check (reason = any (array['active_spec'::text,'acceptance_repair'::text,'primitive_materialization'::text]));

alter table public.pandora_source_generation_queue
  add constraint pandora_source_generation_queue_check
  check (
    (
      reason = any (array['active_spec'::text,'primitive_materialization'::text])
      and repair_of_build_job_id is null
      and repair_of_verification_run_id is null
    )
    or
    (
      reason = 'acceptance_repair'::text
      and repair_of_build_job_id is not null
      and repair_of_verification_run_id is not null
    )
  );

with legacy_candidates as (
  select
    s.organization_id,
    s.project_id,
    s.id as project_spec_id,
    i.requester_id as requested_by,
    latest.target_project_version_id as base_version_id,
    resolution.value as resolution,
    (resolution.value ->> 'primitiveCount')::integer as primitive_count
  from public.pandora_project_specs s
  join public.pandora_project_intents i
    on i.id=s.source_intent_id
   and i.organization_id=s.organization_id
   and i.project_id=s.project_id
  join public.projectos_projects p
    on p.id=s.project_id
   and p.organization_id=s.organization_id
   and p.status='active'
  join lateral (
    select j.id,j.target_project_version_id
    from public.pandora_build_jobs j
    where j.organization_id=s.organization_id
      and j.project_id=s.project_id
      and j.project_spec_id=s.id
      and j.status='succeeded'
      and j.target_project_version_id is not null
    order by j.created_at desc,j.id desc
    limit 1
  ) latest on true
  cross join lateral (
    select public.pandora_worker_i_resolve_project_spec_primitives_20260831(s.id,true) as value
  ) resolution
  where s.status='active'
), eligible as (
  select candidate.*
  from legacy_candidates candidate
  where candidate.resolution ->> 'state' = 'READY'
    and candidate.primitive_count between 1 and 256
    and not exists (
      select 1
      from public.pandora_project_version_compositions composition
      where composition.project_version_id=candidate.base_version_id
        and composition.organization_id=candidate.organization_id
        and composition.project_id=candidate.project_id
        and composition.primitive_count=candidate.primitive_count
    )
)
insert into public.pandora_source_generation_queue(
  organization_id,project_id,project_spec_id,requested_by,reason,
  base_version_id,attempt_no,status,idempotency_key
)
select
  eligible.organization_id,
  eligible.project_id,
  eligible.project_spec_id,
  eligible.requested_by,
  'primitive_materialization',
  eligible.base_version_id,
  0,
  'queued',
  'pandora-primitive-materialize:'||eligible.project_spec_id::text||':'||eligible.base_version_id::text
from eligible
on conflict (idempotency_key) do nothing;
