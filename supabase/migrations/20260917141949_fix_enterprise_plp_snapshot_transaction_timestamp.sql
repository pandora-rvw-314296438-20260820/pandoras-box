do $do$
declare
  v_def text;
  v_old constant text := 'v_property.organization_id,v_property.id,v_business_date,now(),v_occupancy';
  v_new constant text := 'v_property.organization_id,v_property.id,v_business_date,clock_timestamp(),v_occupancy';
begin
  select pg_get_functiondef('public.enterprise_refresh_plp_runtime_overview_v1()'::regprocedure) into v_def;
  if position(v_old in v_def)=0 then
    raise exception 'expected PLP snapshot timestamp anchor not found; aborting';
  end if;
  if length(v_def)-length(replace(v_def,v_old,'')) <> length(v_old) then
    raise exception 'PLP snapshot timestamp anchor is not unique; aborting';
  end if;
  execute replace(v_def,v_old,v_new);
end
$do$;;
