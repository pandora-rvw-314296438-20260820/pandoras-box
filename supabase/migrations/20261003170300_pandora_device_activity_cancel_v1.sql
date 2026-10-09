-- Admit cancellation reported at the native executor's before-effect boundary.
-- Extend the exact live scoped RPC without replacing its ownership, current
-- Core access, idempotency, row lock, or immutable terminal-state guards.
-- Live prosrc MD5 read back 2026-10-03: 74f72bcacd0b3177a930dbfcd7bc2df8.
do $migration$
declare
  v_oid oid := to_regprocedure('public.pandora_activity_device_fact_v1(uuid,uuid,text,text,text,timestamp with time zone)');
  v_definition text;
  v_body text;
  v_hash text;
  v_stages text := $stages$'acting','verifying','result','failed','needs_permission',
    'needs_special_access','needs_choice'$stages$;
  v_cancel_case text := $case$    when 'cancelled' then
      v_state := 'cancelled';
      v_message := case v_capability
        when 'calendar.events' then 'Calendar action cancelled before any device change.'
        when 'reminder.local' then 'Reminder cancelled before it was scheduled on the device.'
        when 'communication.sms' then 'SMS cancelled before a message was sent.'
        when 'communication.call' then 'Call cancelled before it was placed.'
        else 'Device action cancelled before execution.'
      end;
$case$;
  v_cancel_evidence text := $evidence$  elsif v_state='cancelled' then
    v_evidence := jsonb_build_array(
      jsonb_build_object('type','device_event','relation','authoritative_cancellation','ref',v_ref)
    );
$evidence$;
begin
  select p.prosrc, pg_get_functiondef(p.oid), md5(p.prosrc)
    into v_body, v_definition, v_hash
  from pg_proc p
  where p.oid=v_oid
    and p.prosecdef
    and p.prorettype='jsonb'::regtype
    and p.prolang=(select oid from pg_language where lanname='plpgsql')
    and p.proconfig=array['search_path=pg_catalog, public, auth'];
  if not found then
    raise exception 'PANDORA_DEVICE_CANCEL_BASELINE_MISSING' using errcode='55000';
  end if;
  -- A repeat application is a no-op only for the exact reviewed new body.
  if v_hash='bcd54210c01e418d17071a77cbef4347' then
    return;
  end if;
  if v_hash is distinct from '74f72bcacd0b3177a930dbfcd7bc2df8' then
    raise exception 'PANDORA_DEVICE_CANCEL_BASELINE_CHANGED' using errcode='55000';
  end if;

  v_definition := replace(v_definition, v_stages, v_stages || ',''cancelled''');
  v_definition := replace(v_definition, E'    when ''failed'' then\n',
    v_cancel_case || E'    when ''failed'' then\n');
  v_definition := replace(v_definition, E'  elsif v_state=''failed'' then\n',
    v_cancel_evidence || E'  elsif v_state=''failed'' then\n');
  execute v_definition;

  select md5(p.prosrc) into v_hash from pg_proc p where p.oid=v_oid;
  if v_hash is distinct from 'bcd54210c01e418d17071a77cbef4347' then
    raise exception 'PANDORA_DEVICE_CANCEL_PATCH_MISMATCH' using errcode='55000';
  end if;
end;
$migration$;

revoke all on function public.pandora_activity_device_fact_v1(uuid,uuid,text,text,text,timestamptz)
  from public, anon;
grant execute on function public.pandora_activity_device_fact_v1(uuid,uuid,text,text,text,timestamptz)
  to authenticated;

comment on function public.pandora_activity_device_fact_v1(uuid,uuid,text,text,text,timestamptz)
is 'Bounded authenticated calendar/reminder/SMS/call facts, including native before-effect cancellation; preserves current Core scope and terminal result truth.';
