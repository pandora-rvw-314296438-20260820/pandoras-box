revoke execute on function public.plp_pandora_activity_logs_v1(bigint,integer,text)
  from authenticated;
grant execute on function public.plp_pandora_activity_logs_v1(bigint,integer,text)
  to service_role;
