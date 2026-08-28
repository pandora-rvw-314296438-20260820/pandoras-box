-- Worker D live Vercel Sandbox protocol correction.
-- Keeps the Vault-backed private broker unchanged while normalizing safe control POSTs at the service-only wrapper.

create or replace function public.pandora_worker_d_vercel_sandbox_request_20260829(
  p_method text,
  p_path text,
  p_body jsonb default null
)
returns jsonb
language sql
security definer
set search_path=''
as $$
  select private.pandora_worker_d_vercel_sandbox_api_20260829(
    p_method,
    p_path,
    case
      when upper(coalesce(p_method,''))='POST' and p_body is null then '{}'::jsonb
      else p_body
    end
  );
$$;

revoke all on function public.pandora_worker_d_vercel_sandbox_request_20260829(text,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_worker_d_vercel_sandbox_request_20260829(text,text,jsonb) to service_role;
