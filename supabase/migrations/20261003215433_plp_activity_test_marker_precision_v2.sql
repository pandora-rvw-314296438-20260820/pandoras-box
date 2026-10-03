create or replace function private.plp_activity_record_is_test_v2(
  p_record jsonb,
  p_source text,
  p_text text default null
) returns boolean language sql immutable set search_path='' as $classifier$
  select
    exists (
      select 1
      from jsonb_array_elements(jsonb_build_array(
        coalesce(p_record,'{}'::jsonb),
        coalesce(p_record->'metadata','{}'::jsonb),
        coalesce(p_record->'provenance','{}'::jsonb)
      )) scope,
      unnest(array['isMock','is_mock','isTestData','is_test_data','isTest','is_test','synthetic','mock','testOnly','test_only']) flag
      where lower(coalesce(scope->>flag,'')) in ('true','1','yes')
    )
    or lower(trim(coalesce(p_source,'')))
      ~ '^(qa|mock|synthetic|fixture|test|demo)([[:space:]_:/.-]|$)'
    or strpos(lower(coalesce(p_text,'')), '[mock qa]') > 0
    or upper(coalesce(p_record->>'booking_reference',p_record->>'bookingReference','')) like 'MOCK-%';
$classifier$;
revoke all on function private.plp_activity_record_is_test_v2(jsonb,text,text) from public,anon,authenticated;
grant execute on function private.plp_activity_record_is_test_v2(jsonb,text,text) to service_role;

-- Preserve all existing authentication, tenant-entry, and pagination logic.
-- Only replace the test predicates; ordinary guest text and staff names are not
-- test provenance. Raw evidence remains stored in its original tables.
do $repair$
declare
 old_definition text;
 new_definition text;
 marker text;
begin
 old_definition:=pg_get_functiondef('public.plp_recent_business_activity_v1(integer)'::regprocedure);
 if strpos(old_definition,'testDataExcluded')=0 or
    strpos(old_definition,'pandora_core_legacy_client_scope_v1')=0 then
   raise exception 'PLP_ACTIVITY_BASELINE_NOT_RECOGNIZED';
 end if;
 marker:=$old$lower(coalesce(e.source_label,'')) like '%mock%'
        or lower(coalesce(e.source_label,'')) like '%qa%' as is_mock$old$;
 if strpos(old_definition,marker)=0 then raise exception 'PLP_BUSINESS_MARKER_CHANGED'; end if;
 new_definition:=replace(old_definition,marker,
   $new$private.plp_activity_record_is_test_v2(
        to_jsonb(e), e.source_label, concat_ws(' ',e.title,e.summary)
      ) as is_mock$new$);
 marker:=$old$lower(coalesce(t.source,'')) like 'qa_%'
        or lower(coalesce(t.actor,'')) like '%qa%'
        or lower(coalesce(t.note,'')) like '%[mock qa]%'
        or lower(coalesce(t.note,'')) like '%synthetic%' as is_mock$old$;
 if strpos(new_definition,marker)=0 then raise exception 'PLP_TASK_MARKER_CHANGED'; end if;
 new_definition:=replace(new_definition,marker,
   $new$private.plp_activity_record_is_test_v2(
        to_jsonb(t), t.source, concat_ws(' ',t.title,t.note)
      ) as is_mock$new$);
 marker:=$old$lower(coalesce(g.metadata->>'mock','false')) in ('true','1','yes')
        or lower(coalesce(b.source,'')) like 'qa_%'
        or upper(coalesce(b.booking_reference,'')) like 'MOCK-%' as is_mock$old$;
 if strpos(new_definition,marker)=0 then raise exception 'PLP_BOOKING_MARKER_CHANGED'; end if;
 new_definition:=replace(new_definition,marker,
   $new$private.plp_activity_record_is_test_v2(
        jsonb_build_object('metadata',g.metadata), null, null
      ) or private.plp_activity_record_is_test_v2(
        to_jsonb(b), b.source, null
      ) as is_mock$new$);
 execute new_definition;

 old_definition:=pg_get_functiondef('public.plp_pandora_activity_logs_v2(timestamp with time zone,uuid,bigint,integer,text)'::regprocedure);
 if strpos(old_definition,'testDataExcluded')=0 or
    strpos(old_definition,'pandora_core_legacy_client_scope_v1')=0 then
   raise exception 'PLP_LOG_BASELINE_NOT_RECOGNIZED';
 end if;
 marker:=$old$      and lower(coalesce(a.event->>'isTest','false')) not in ('true','1','yes')
      and lower(coalesce(a.event->>'synthetic','false')) not in ('true','1','yes')
      and lower(coalesce(a.event->>'mock','false')) not in ('true','1','yes')
      and lower(coalesce(a.event#>>'{provenance,sourceType}','')) not like '%mock%'
      and lower(coalesce(a.event#>>'{provenance,sourceType}','')) not like '%synthetic%'
      and lower(coalesce(a.event#>>'{provenance,sourceType}','')) not like 'qa_%'
      and lower(coalesce(a.message,'')) not like '%[mock qa]%'
      and lower(coalesce(a.message,'')) not like '%synthetic%'$old$;
 if strpos(old_definition,marker)=0 then raise exception 'PLP_LOG_MARKER_CHANGED'; end if;
 new_definition:=replace(old_definition,marker,
   $new$      and not private.plp_activity_record_is_test_v2(
        a.event, a.event#>>'{provenance,sourceType}', a.message
      )$new$);
 execute new_definition;
end $repair$;

-- Non-persistent classifier acceptance: includes legitimate QA staff and normal
-- product descriptions, not invented customer rows or impersonated sessions.
do $acceptance$
begin
 if private.plp_activity_record_is_test_v2(
      '{"actor":"QA manager","isTestData":false}',
      'Mockingbird PMS','Replace synthetic pillows') then
   raise exception 'PLP_PRODUCTION_FALSE_POSITIVE';
 end if;
 if not private.plp_activity_record_is_test_v2('{}','qa_mock_seed_20260920',null) or
    not private.plp_activity_record_is_test_v2('{"metadata":{"is_test":true}}','production',null) or
    not private.plp_activity_record_is_test_v2('{}','production','[MOCK QA] Completed checkout task') or
    not private.plp_activity_record_is_test_v2('{"bookingReference":"MOCK-PLP-001"}','production',null) then
   raise exception 'PLP_TEST_MARKER_NOT_ISOLATED';
 end if;
end $acceptance$;