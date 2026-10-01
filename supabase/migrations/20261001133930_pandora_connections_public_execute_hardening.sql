-- Restrict Lane A connection RPCs to the roles granted by the foundation
-- migration. PostgreSQL grants EXECUTE to PUBLIC for new functions unless it
-- is explicitly revoked; anon inherits that access through PUBLIC.

revoke execute on function public.pandora_connection_catalog_v1() from public, anon;
revoke execute on function public.pandora_connection_oauth_prepare_v1(uuid, text, text, text) from public, anon;
revoke execute on function public.pandora_connection_select_account_v1(uuid, uuid, text) from public, anon;
revoke execute on function public.pandora_connection_revoke_v1(uuid, uuid, text) from public, anon;
revoke execute on function public.pandora_connection_write_preview_v1(uuid, text, uuid, text, text, jsonb) from public, anon;
revoke execute on function public.pandora_connection_write_approve_v1(uuid, uuid, text, uuid, text, text) from public, anon;
revoke execute on function public.pandora_live_connections_v1(uuid) from public, anon;
revoke execute on function public.pandora_google_workspace_oauth_commit_v1(text, text, text, text, text, text[], text) from public, anon;
