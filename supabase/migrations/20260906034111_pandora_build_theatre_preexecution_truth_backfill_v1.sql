-- Backfill only the latest pre-execution terminal Build Theatre projections.
-- This changes presentation state only; it does not replay or reopen any build.

with latest_preexecution_terminal as (
  select distinct on (j.project_id)
    j.id,
    j.project_id,
    j.error_code
  from public.pandora_build_jobs j
  where j.status in ('failed','cancelled')
    and coalesce(j.attempt_count,0)=0
    and j.started_at is null
  order by j.project_id,j.created_at desc,j.id desc
)
update public.pandora_build_theatre_projection p
set owner_stage='understanding',
    progress_percent=0,
    public_message=case
      when l.error_code='BUILD_DEADLINE_EXCEEDED'
        then 'Pandora could not start this build before its execution window ended.'
      when l.error_code='BUILD_BUDGET_EXHAUSTED'
        then 'Pandora did not start this build because its build budget was unavailable.'
      else 'Pandora did not start this build. You can try again.'
    end,
    needs_you=false,
    retry_available=true,
    last_event_at=now(),
    updated_at=now()
from latest_preexecution_terminal l
where p.project_id=l.project_id
  and p.build_job_id=l.id
  and (
    p.owner_stage is distinct from 'understanding'
    or p.progress_percent is distinct from 0
    or p.public_message is distinct from case
      when l.error_code='BUILD_DEADLINE_EXCEEDED'
        then 'Pandora could not start this build before its execution window ended.'
      when l.error_code='BUILD_BUDGET_EXHAUSTED'
        then 'Pandora did not start this build because its build budget was unavailable.'
      else 'Pandora did not start this build. You can try again.'
    end
  );
