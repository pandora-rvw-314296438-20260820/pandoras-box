-- Pandora provider connection semantics v4
-- Connected means Pandora has fresh, usable runtime authority for at least one bounded action.
-- Credential presence alone is never sufficient and unavailable providers expose no usable actions.

create or replace function public.pandora_plugin_runtime_registry_v4(
  p_organization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_base jsonb;
  v_rows jsonb;
begin
  v_base := public.pandora_plugin_runtime_registry_v3(p_organization_id);

  select coalesce(
    jsonb_agg(
      p.item || jsonb_build_object(
        'connected', p.usable,
        'canUseNow', p.usable,
        'usableRuntimeAuthority', p.usable,
        'actions', coalesce((
          select jsonb_agg(
            a.action || jsonb_build_object(
              'available', p.usable and coalesce((a.action->>'available')::boolean,false)
            )
            order by a.ord
          )
          from jsonb_array_elements(coalesce(p.item->'actions','[]'::jsonb))
               with ordinality a(action,ord)
        ), '[]'::jsonb),
        'connectionSemantics', case p.item->>'provider'
          when 'github' then jsonb_build_object(
            'requires','vault_credential_plus_fresh_provider_health',
            'detail','GitHub is Connected only when the governed credential exists and fresh provider health says it is usable.'
          )
          when 'supabase' then jsonb_build_object(
            'requires','management_credential_plus_fresh_provider_health',
            'detail','Supabase is Connected only when management authority exists and fresh provider health says it is usable.'
          )
          when 'vercel' then jsonb_build_object(
            'requires','fresh_projectos_provider_health',
            'detail','Vercel is Connected only when current ProjectOS provider evidence says deployment authority is usable.'
          )
          when 'posthog' then jsonb_build_object(
            'requires','query_credential_plus_fresh_provider_health',
            'detail','PostHog is Connected only with a governed query credential and fresh provider health; ingest tokens never count as query authority.'
          )
          when 'google_drive' then jsonb_build_object(
            'requires','verified_google_workspace_authorization',
            'detail','Google Drive remains unavailable until Pandora has verified Google Workspace authorization.'
          )
          when 'google_sheets' then jsonb_build_object(
            'requires','verified_google_workspace_authorization',
            'detail','Google Sheets remains unavailable until Pandora has verified Google Workspace authorization.'
          )
          else jsonb_build_object(
            'requires','verified_runtime_authority',
            'detail','Connected requires fresh verified runtime authority.'
          )
        end
      )
      order by p.ord
    ),
    '[]'::jsonb
  )
  into v_rows
  from (
    select
      item,
      ord,
      (
        item->>'state' = 'Connected'
        and coalesce((item #>> '{health,canUseNow}')::boolean,false)
        and exists (
          select 1
          from jsonb_array_elements(coalesce(item->'actions','[]'::jsonb)) a
          where coalesce((a->>'available')::boolean,false)
        )
      ) as usable
    from jsonb_array_elements(coalesce(v_base->'providers','[]'::jsonb))
         with ordinality t(item,ord)
  ) p;

  return jsonb_build_object(
    'contractVersion','pandora-plugin-runtime-registry-v4',
    'organizationId',p_organization_id,
    'observedAt',now(),
    'projectRequired',false,
    'providers',v_rows
  );
end;
$$;

revoke all on function public.pandora_plugin_runtime_registry_v4(uuid) from public, anon;
grant execute on function public.pandora_plugin_runtime_registry_v4(uuid) to authenticated;

comment on function public.pandora_plugin_runtime_registry_v4(uuid)
is 'Provider-semantics registry. Connected means fresh usable runtime authority; credential presence alone never exposes actions.';
