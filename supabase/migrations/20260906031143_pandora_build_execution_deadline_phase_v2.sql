-- Separate source-generation waiting time from Worker-D execution time.
-- Real canary jobs were terminalized before worker start because the 30-minute
-- execution deadline began at admission while source generation was still pending.

begin;

create or replace function private.pandora_build_execution_deadline_phase_v2()
returns trigger
language plpgsql
security definer
set search_path = ''
as $fn$
begin
  if tg_op = 'INSERT' then
    if new.job_kind = 'build'
       and new.status = 'queued'
       and new.target_project_version_id is null
       and new.source_intent_id is not null
       and new.idempotency_key like 'pandora-admission:%' then
      new.deadline_at := null;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE'
     and old.target_project_version_id is null
     and new.target_project_version_id is not null
     and new.job_kind = 'build'
     and new.status = 'queued'
     and new.source_intent_id is not null
     and new.idempotency_key like 'pandora-admission:%' then
    new.deadline_at := clock_timestamp() + interval '30 minutes';
  end if;

  return new;
end
$fn$;

revoke all on function private.pandora_build_execution_deadline_phase_v2()
from public, anon, authenticated;

drop trigger if exists pandora_build_execution_deadline_admission_v2
on public.pandora_build_jobs;

create trigger pandora_build_execution_deadline_admission_v2
before insert on public.pandora_build_jobs
for each row
execute function private.pandora_build_execution_deadline_phase_v2();

drop trigger if exists pandora_build_execution_deadline_source_ready_v2
on public.pandora_build_jobs;

create trigger pandora_build_execution_deadline_source_ready_v2
before update of target_project_version_id on public.pandora_build_jobs
for each row
execute function private.pandora_build_execution_deadline_phase_v2();

comment on function private.pandora_build_execution_deadline_phase_v2() is
'Separates governed source-generation waiting from worker execution deadline. Server-admitted source-backed builds carry no execution deadline until exact generated source is attached; source-ready transition starts a fresh 30-minute execution deadline.';

commit;
