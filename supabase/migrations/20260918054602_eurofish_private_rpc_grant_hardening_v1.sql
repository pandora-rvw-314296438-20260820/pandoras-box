
revoke all on function public.pandora_eurofish_private_workspace_v1(text) from public;
revoke all on function public.pandora_eurofish_private_workspace_v1(text) from anon;
revoke all on function public.pandora_eurofish_private_workspace_v1(text) from authenticated;
grant execute on function public.pandora_eurofish_private_workspace_v1(text) to authenticated;
;
