create or replace function private.enforce_execution_plan_context_before_approval()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'approved'
     and old.status is distinct from 'approved'
     and not exists (
       select 1
       from private.execution_plan_contexts c
       where c.plan_id = new.id
         and c.organization_id = new.organization_id
         and c.request_id = new.request_id
         and c.context_status = 'available'
         and c.namespace = 'real_life'
     ) then
    raise exception 'projectos_memory_context_required_before_approval' using errcode = '55000';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_execution_plan_context_before_approval on private.execution_plans;
create trigger enforce_execution_plan_context_before_approval
before update of status on private.execution_plans
for each row
when (new.status = 'approved' and old.status is distinct from 'approved')
execute function private.enforce_execution_plan_context_before_approval();