-- Release source-model reservations whenever an attempt stops owning provider work.
-- Prevents failed/retried queues from consuming a ProjectSpec budget with zero actual spend.

begin;

alter table public.pandora_source_model_budget_reservations
  drop constraint if exists pandora_source_model_budget_reservation_status_check;

alter table public.pandora_source_model_budget_reservations
  add constraint pandora_source_model_budget_reservation_status_check
  check (status in ('reserved','settled','retained','denied','released'));

create or replace function private.pandora_release_source_model_reservations_v2(
  p_queue_id uuid,
  p_through_attempt integer default null
) returns integer
language plpgsql
security definer
set search_path=''
as $fn$
declare
  v_row public.pandora_source_model_budget_reservations%rowtype;
  v_released integer := 0;
begin
  for v_row in
    select *
    from public.pandora_source_model_budget_reservations
    where queue_id=p_queue_id
      and status='reserved'
      and model_run_id is null
      and (p_through_attempt is null or dispatch_attempt <= p_through_attempt)
    order by dispatch_attempt
    for update
  loop
    if private.pandora_release_budget(
      v_row.budget_limit_id,
      v_row.reservation_micros
    ) then
      update public.pandora_source_model_budget_reservations
         set status='released',
             settled_at=coalesce(settled_at,clock_timestamp())
       where id=v_row.id
         and status='reserved';
      if found then
        v_released := v_released + 1;
      end if;
    end if;
  end loop;
  return v_released;
end
$fn$;

revoke all on function private.pandora_release_source_model_reservations_v2(uuid,integer)
  from public,anon,authenticated;
grant execute on function private.pandora_release_source_model_reservations_v2(uuid,integer)
  to service_role;

create or replace function private.pandora_release_source_model_reservations_on_queue_v2()
returns trigger
language plpgsql
security definer
set search_path=''
as $fn$
begin
  if old.status='dispatching' and new.status='queued' then
    perform private.pandora_release_source_model_reservations_v2(
      new.id,
      new.dispatch_count
    );
  elsif new.status in ('failed','cancelled','succeeded')
        and new.status is distinct from old.status then
    perform private.pandora_release_source_model_reservations_v2(new.id,null);
  end if;
  return new;
end
$fn$;

drop trigger if exists pandora_release_source_model_reservations_on_queue_v2
  on public.pandora_source_generation_queue;
create trigger pandora_release_source_model_reservations_on_queue_v2
after update of status on public.pandora_source_generation_queue
for each row
when (old.status is distinct from new.status)
execute function private.pandora_release_source_model_reservations_on_queue_v2();

do $backfill$
declare
  v_queue record;
begin
  for v_queue in
    select q.id,q.status,q.dispatch_count
    from public.pandora_source_generation_queue q
    where q.status in ('failed','cancelled','succeeded','queued')
      and exists (
        select 1
        from public.pandora_source_model_budget_reservations r
        where r.queue_id=q.id
          and r.status='reserved'
          and r.model_run_id is null
          and (
            q.status <> 'queued'
            or r.dispatch_attempt <= q.dispatch_count
          )
      )
  loop
    perform private.pandora_release_source_model_reservations_v2(
      v_queue.id,
      case
        when v_queue.status='queued' then v_queue.dispatch_count
        else null
      end
    );
  end loop;
end
$backfill$;

commit;
