-- Pandora plugin runtime registry v3
-- Enriches the universal capability registry with explicit runtime detail fields for
-- the Plugins experience. Unknown provider account/scope identity remains unknown;
-- Pandora must never infer authority from a friendly connection label.

create or replace function public.pandora_plugin_runtime_registry_v3(
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
  v_base := public.pandora_chat_capability_registry_v2(p_organization_id);

  select coalesce(
    jsonb_agg(
      p.item || jsonb_build_object(
        'account', jsonb_build_object(
          'label', null,
          'verified', false,
          'reason', 'Provider account identity is not exposed by current verified runtime evidence.'
        ),
        'scopes', '[]'::jsonb,
        'scopesVerified', false,
        'actions', coalesce(p.item->'capabilities', '[]'::jsonb),
        'health', jsonb_build_object(
          'state', coalesce(p.item->>'state', 'Unavailable'),
          'rawStatus', coalesce(p.item->>'status', 'unknown'),
          'canUseNow', coalesce((p.item->>'canUseNow')::boolean, false),
          'lastVerifiedAt', p.item->'lastVerifiedAt'
        ),
        'failure', case
          when coalesce(p.item->>'state','Unavailable') = 'Connected' then null
          when coalesce(p.item->>'state','Unavailable') = 'Needs authorization' then
            jsonb_build_object(
              'code','authorization_required',
              'message',coalesce(p.item->>'authorization','Provider authorization is required.')
            )
          when coalesce(p.item->>'state','Unavailable') = 'Problem' then
            jsonb_build_object(
              'code','runtime_problem',
              'message',format(
                '%s runtime evidence is not currently healthy (%s).',
                coalesce(p.item->>'label', initcap(replace(coalesce(p.item->>'provider','provider'),'_',' '))),
                coalesce(p.item->>'status','unknown')
              )
            )
          else
            jsonb_build_object(
              'code','unavailable',
              'message',coalesce(p.item->>'authorization','This provider is not currently available to Pandora.')
            )
        end,
        'readAvailable', exists(
          select 1
          from jsonb_array_elements(coalesce(p.item->'capabilities','[]'::jsonb)) c
          where c->>'mode' = 'read' and coalesce((c->>'available')::boolean,false)
        ),
        'writeAvailable', exists(
          select 1
          from jsonb_array_elements(coalesce(p.item->'capabilities','[]'::jsonb)) c
          where c->>'mode' = 'write' and coalesce((c->>'available')::boolean,false)
        )
      )
      order by p.ord
    ),
    '[]'::jsonb
  )
  into v_rows
  from jsonb_array_elements(coalesce(v_base->'providers','[]'::jsonb))
       with ordinality p(item, ord);

  return jsonb_build_object(
    'contractVersion','pandora-plugin-runtime-registry-v3',
    'organizationId',p_organization_id,
    'observedAt',now(),
    'projectRequired',false,
    'providers',v_rows
  );
end;
$$;

revoke all on function public.pandora_plugin_runtime_registry_v3(uuid) from public, anon;
grant execute on function public.pandora_plugin_runtime_registry_v3(uuid) to authenticated;

comment on function public.pandora_plugin_runtime_registry_v3(uuid)
is 'Runtime-authoritative plugin registry for Pandora UI. Models provider state/actions/health/verification and explicitly leaves unverified account/scope identity unknown.';
