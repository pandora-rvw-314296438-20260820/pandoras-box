-- Pandora Meta plugin runtime v4 bridge.
-- Keeps the existing provider-semantics registry intact and adds the current,
-- organization-bound Meta readiness projection as one fail-closed plugin row.

create or replace function public.pandora_plugin_runtime_registry_v4(
  p_organization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_base jsonb;
  v_base_rows jsonb := '[]'::jsonb;
  v_meta jsonb;
  v_meta_item jsonb;
  v_rows jsonb;
  v_meta_can_use boolean := false;
  v_meta_state text := 'Problem';
begin
  -- The existing registry performs the authoritative active owner/admin check.
  -- Keep this outside the Meta error boundary so tenant/auth failures propagate.
  v_base := public.pandora_plugin_runtime_registry_v3(p_organization_id);

  begin
    v_meta := public.pandora_meta_connection_v1(p_organization_id);
  exception
    when sqlstate '42501' then
      raise;
    when others then
      v_meta := jsonb_build_object(
        'connected', false,
        'state', 'Problem',
        'canUseNow', false,
        'rawStatus', 'projection_unavailable'
      );
  end;

  v_meta_can_use := coalesce(
    v_meta->'canUseNow' = 'true'::jsonb,
    false
  );
  v_meta_state := case
    when v_meta->>'state' in (
      'Connected',
      'Needs authorization',
      'Reconnect required',
      'Permissions incomplete',
      'Verification required',
      'Problem'
    ) then v_meta->>'state'
    when v_meta_can_use then 'Connected'
    else 'Problem'
  end;

  v_meta_item := jsonb_build_object(
    'provider', 'meta',
    'label', 'Meta',
    'state', v_meta_state,
    'status', coalesce(nullif(v_meta->>'rawStatus', ''), 'unknown'),
    'connected', v_meta_can_use,
    'canUseNow', v_meta_can_use,
    'readAvailable', v_meta_can_use,
    'writeAvailable', false,
    'authorization',
      'Owner-authorized Facebook Page and Meta Ads reads. Consequential external changes remain separately approval-gated.',
    'account', case
      when jsonb_typeof(v_meta->'account') = 'object' then
        jsonb_build_object(
          'id', v_meta #>> '{account,id}',
          'label', v_meta #>> '{account,label}',
          'verified', coalesce(v_meta #> '{account,verified}' = 'true'::jsonb, false)
        )
      else '{}'::jsonb
    end,
    'scopes', case
      when jsonb_typeof(v_meta->'scopes') = 'array' then v_meta->'scopes'
      else '[]'::jsonb
    end,
    'scopesVerified', coalesce(
      v_meta->'scopesVerified' = 'true'::jsonb,
      false
    ),
    'lastVerifiedAt', v_meta->'lastVerifiedAt',
    'health', jsonb_build_object(
      'rawStatus', coalesce(nullif(v_meta->>'rawStatus', ''), 'unknown'),
      'canUseNow', v_meta_can_use,
      'lastVerifiedAt', v_meta->'lastVerifiedAt'
    ),
    'failure', case
      when v_meta_state = 'Problem' then jsonb_build_object(
        'code', 'META_PROJECTION_UNAVAILABLE',
        'message', 'Pandora could not verify Meta connection state.'
      )
      else null
    end,
    'actions', jsonb_build_array(
      jsonb_build_object('name', 'pages.read', 'mode', 'read', 'available', v_meta_can_use),
      jsonb_build_object('name', 'ads.read', 'mode', 'read', 'available', v_meta_can_use),
      jsonb_build_object(
        'name', 'ads.manage',
        'mode', 'write',
        'available', false,
        'approval', 'owner',
        'reason', 'external_write_not_exposed'
      )
    )
  );

  -- Preserve the existing provider rows and order. Removing a future base Meta
  -- row before append keeps the projection unique and this replacement idempotent.
  select coalesce(
    jsonb_agg(item order by ord)
      filter (where item->>'provider' is distinct from 'meta'),
    '[]'::jsonb
  )
  into v_base_rows
  from jsonb_array_elements(coalesce(v_base->'providers', '[]'::jsonb))
       with ordinality t(item, ord);

  v_base := jsonb_set(
    v_base,
    '{providers}',
    v_base_rows || jsonb_build_array(v_meta_item),
    true
  );

  -- This is the existing v4 usability normalization. Meta participates through
  -- the same state + fresh health + available action rule as every provider.
  select coalesce(
    jsonb_agg(
      p.item || jsonb_build_object(
        'connected', p.usable,
        'canUseNow', p.usable,
        'usableRuntimeAuthority', p.usable,
        'actions', coalesce((
          select jsonb_agg(
            a.action || jsonb_build_object(
              'available', p.usable
                and coalesce((a.action->>'available')::boolean, false)
            )
            order by a.ord
          )
          from jsonb_array_elements(coalesce(p.item->'actions', '[]'::jsonb))
               with ordinality a(action, ord)
        ), '[]'::jsonb),
        'connectionSemantics', case p.item->>'provider'
          when 'github' then jsonb_build_object(
            'requires', 'vault_credential_plus_fresh_provider_health',
            'detail', 'GitHub is Connected only when the governed credential exists and fresh provider health says it is usable.'
          )
          when 'supabase' then jsonb_build_object(
            'requires', 'management_credential_plus_fresh_provider_health',
            'detail', 'Supabase is Connected only when management authority exists and fresh provider health says it is usable.'
          )
          when 'vercel' then jsonb_build_object(
            'requires', 'fresh_projectos_provider_health',
            'detail', 'Vercel is Connected only when current ProjectOS provider evidence says deployment authority is usable.'
          )
          when 'posthog' then jsonb_build_object(
            'requires', 'query_credential_plus_fresh_provider_health',
            'detail', 'PostHog is Connected only with a governed query credential and fresh provider health; ingest tokens never count as query authority.'
          )
          when 'google_drive' then jsonb_build_object(
            'requires', 'verified_google_workspace_authorization',
            'detail', 'Google Drive remains unavailable until Pandora has verified Google Workspace authorization.'
          )
          when 'google_sheets' then jsonb_build_object(
            'requires', 'verified_google_workspace_authorization',
            'detail', 'Google Sheets remains unavailable until Pandora has verified Google Workspace authorization.'
          )
          when 'meta' then jsonb_build_object(
            'requires', 'owner_authorized_meta_oauth_plus_fresh_provider_readback',
            'detail', 'Meta is Connected only after owner-authorized OAuth and current Page, permission, token-expiry, credential and provider-health verification.'
          )
          else jsonb_build_object(
            'requires', 'verified_runtime_authority',
            'detail', 'Connected requires fresh verified runtime authority.'
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
        and coalesce((item #>> '{health,canUseNow}')::boolean, false)
        and exists (
          select 1
          from jsonb_array_elements(coalesce(item->'actions', '[]'::jsonb)) a
          where coalesce((a->>'available')::boolean, false)
        )
      ) as usable
    from jsonb_array_elements(coalesce(v_base->'providers', '[]'::jsonb))
         with ordinality t(item, ord)
  ) p;

  return jsonb_build_object(
    'contractVersion', 'pandora-plugin-runtime-registry-v4',
    'organizationId', p_organization_id,
    'observedAt', now(),
    'projectRequired', false,
    'providers', v_rows
  );
end;
$$;

revoke all on function public.pandora_plugin_runtime_registry_v4(uuid)
  from public, anon;
grant execute on function public.pandora_plugin_runtime_registry_v4(uuid)
  to authenticated;

comment on function public.pandora_plugin_runtime_registry_v4(uuid)
is 'Provider-semantics registry with one fail-closed Meta readiness row. Existing provider health semantics remain unchanged.';
