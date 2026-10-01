
begin;
alter table public.pandora_plp_studio_preview_bindings
  add column if not exists proxy_url text null;
alter table public.pandora_plp_studio_preview_bindings
  drop constraint if exists pandora_plp_studio_preview_bindings_proxy_url_check;
alter table public.pandora_plp_studio_preview_bindings
  add constraint pandora_plp_studio_preview_bindings_proxy_url_check
  check (proxy_url is null or proxy_url ~ '^https://mcpmaster[.]vercel[.]app/preview/[0-9a-f]{64}/index[.]html$');
commit;

