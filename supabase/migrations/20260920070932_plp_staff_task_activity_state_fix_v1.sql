
do $migration$
declare
  v_def text;
begin
  select pg_get_functiondef(p.oid)
  into v_def
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='public'
    and p.proname='plp_create_staff_task_v1'
    and pg_get_function_identity_arguments(p.oid)=
      'p_request_id text, p_booking_reference text, p_title text, p_note text, p_category text, p_priority text';

  if v_def is null then
    raise exception 'plp_create_staff_task_v1 not found';
  end if;

  if position('''state'',''executing''' in v_def)=0
     or position('job.writer_epoch,''executing''' in v_def)=0
     or position('''state'',''done''' in v_def)=0
     or position('job.writer_epoch,''done''' in v_def)=0 then
    raise exception 'unexpected PLP staff-task activity state definition';
  end if;

  v_def := replace(v_def, '''state'',''executing''', '''state'',''acting''');
  v_def := replace(v_def, 'job.writer_epoch,''executing''', 'job.writer_epoch,''acting''');
  v_def := replace(v_def, '''state'',''done''', '''state'',''result''');
  v_def := replace(v_def, 'job.writer_epoch,''done''', 'job.writer_epoch,''result''');

  execute v_def;
end;
$migration$;
