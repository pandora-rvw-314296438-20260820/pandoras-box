-- Universal Pandora Chat runtime truth v1
-- Projects are optional context. Capability/plugin questions resolve from live
-- provider/control-plane evidence and never require a Project to exist.

create or replace function public.pandora_chat_capability_registry_v2(
  p_organization_id uuid
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_base jsonb;
  v_vercel_status text;
  v_vercel_last_verified timestamptz;
  v_vercel_stale_after timestamptz;
  v_vercel jsonb;
  v_rows jsonb;
begin
  v_base := public.pandora_chat_capability_registry_v1(p_organization_id);

  select h.status, h.last_success_at, h.stale_after
  into v_vercel_status, v_vercel_last_verified, v_vercel_stale_after
  from public.projectos_integration_health h
  where h.organization_id = p_organization_id
    and h.provider = 'vercel'
  order by h.updated_at desc nulls last
  limit 1;

  v_vercel := jsonb_build_object(
    'provider','vercel',
    'connected', coalesce(v_vercel_status in ('healthy','available','ready','connected','success'), false)
      and (v_vercel_stale_after is null or v_vercel_stale_after > now()),
    'status', coalesce(
      case when v_vercel_stale_after is not null and v_vercel_stale_after <= now() then 'stale' end,
      v_vercel_status,
      'unknown'
    ),
    'lastVerifiedAt',v_vercel_last_verified,
    'temporarilyUnavailable',
      not coalesce(v_vercel_status in ('healthy','available','ready','connected','success'), false)
      or (v_vercel_stale_after is not null and v_vercel_stale_after <= now()),
    'authorization','ProjectOS governs deployment and other consequential Vercel mutations.',
    'capabilities',jsonb_build_array(
      jsonb_build_object('name','deployment.read','mode','read','available',coalesce(v_vercel_status in ('healthy','available','ready','connected','success'), false)),
      jsonb_build_object('name','deployment.write','mode','write','available',coalesce(v_vercel_status in ('healthy','available','ready','connected','success'), false),'approval','projectos')
    )
  );

  select coalesce(jsonb_agg(
    p.item || jsonb_build_object(
      'label', case p.item->>'provider'
        when 'github' then 'GitHub'
        when 'supabase' then 'Supabase'
        when 'vercel' then 'Vercel'
        when 'posthog' then 'PostHog'
        when 'google_drive' then 'Google Drive'
        when 'google_sheets' then 'Google Sheets'
        else initcap(replace(p.item->>'provider','_',' '))
      end,
      'state', case
        when p.item->>'status' in ('needs_authorization','needs_connection') then 'Needs authorization'
        when coalesce((p.item->>'temporarilyUnavailable')::boolean,false)
          or p.item->>'status' in ('stale','down','error','unhealthy','unknown') then 'Problem'
        when coalesce((p.item->>'connected')::boolean,false) then 'Connected'
        else 'Unavailable'
      end,
      'canUseNow', case
        when p.item->>'status' in ('needs_authorization','needs_connection') then false
        when coalesce((p.item->>'temporarilyUnavailable')::boolean,false)
          or p.item->>'status' in ('stale','down','error','unhealthy','unknown') then false
        else coalesce((p.item->>'connected')::boolean,false)
      end
    ) order by p.ord
  ), '[]'::jsonb)
  into v_rows
  from (
    select row_number() over () as ord, value as item
    from jsonb_array_elements(
      coalesce(v_base->'providers','[]'::jsonb) || jsonb_build_array(v_vercel)
    )
  ) p;

  return jsonb_build_object(
    'contractVersion','pandora-chat-capability-registry-v2',
    'organizationId',p_organization_id,
    'observedAt',now(),
    'projectRequired',false,
    'providers',v_rows
  );
end;
$$;

revoke all on function public.pandora_chat_capability_registry_v2(uuid) from public, anon;
grant execute on function public.pandora_chat_capability_registry_v2(uuid) to authenticated;

create or replace function public.pandora_chat_universal_dispatch_v1(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, private, vault, auth, extensions, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_role text;
  v_message text := trim(coalesce(p_message,''));
  v_thread_id uuid := p_thread_id;
  v_registry jsonb;
  v_reply text;
  v_lines text;
  v_is_catalog_query boolean;
begin
  if v_uid is null then
    raise exception 'pandora_chat_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;

  if v_role not in ('owner','admin') then
    raise exception 'pandora_chat_owner_required' using errcode='42501';
  end if;

  if v_message='' or length(v_message)>8000 then
    raise exception 'pandora_chat_invalid_message' using errcode='22023';
  end if;

  v_is_catalog_query :=
    v_message ~* '\m(connection|connections|connector|connectors|capability|capabilities|plugin|plugins|available tools|tools)\M'
    or v_message ~* '(what[[:space:]]+can[[:space:]]+you[[:space:]]+do|what[[:space:]]+are[[:space:]]+you[[:space:]]+able[[:space:]]+to[[:space:]]+do|what[[:space:]]+can[[:space:]]+pandora[[:space:]]+do)';

  if not v_is_catalog_query then
    return public.pandora_chat_capability_dispatch_v1(
      p_organization_id,p_message,p_thread_id,p_project_id
    );
  end if;

  v_registry := public.pandora_chat_capability_registry_v2(p_organization_id);

  select string_agg(
    format('• %s — %s', value->>'label', value->>'state'),
    E'\n' order by ord
  ) into v_lines
  from jsonb_array_elements(v_registry->'providers') with ordinality t(value,ord);

  v_reply := concat(
    'Pandora is ready to work without a Project. Projects are optional persistent context, not a prerequisite.',
    E'\n\nPlugins and connectors right now:\n',
    coalesce(v_lines,'No plugin state is currently available.'),
    E'\n\nTell me the outcome you want. I will use an authorized capability when one exists, route consequential changes through ProjectOS, and tell you when authorization or another dependency is actually required.'
  );

  if v_thread_id is not null then
    if not exists (
      select 1 from public.pandora_intelligence_threads t
      where t.id=v_thread_id
        and t.organization_id=p_organization_id
        and t.created_by=v_uid
        and t.status='active'
    ) then
      raise exception 'pandora_chat_thread_not_found' using errcode='22023';
    end if;
  else
    insert into public.pandora_intelligence_threads(
      organization_id,project_id,created_by,title,status,last_message_at
    ) values (
      p_organization_id,p_project_id,v_uid,
      left(regexp_replace(v_message,'[[:space:]]+',' ','g'),80),
      'active',now()
    ) returning id into v_thread_id;
  end if;

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,attachment_manifest
  ) values (
    v_thread_id,p_organization_id,p_project_id,'user',v_message,'[]'::jsonb
  );

  insert into public.pandora_intelligence_messages(
    thread_id,organization_id,project_id,author_role,content,structured_response,provider,model
  ) values (
    v_thread_id,p_organization_id,p_project_id,'assistant',v_reply,
    jsonb_build_object(
      'intent','chat',
      'confidence',1,
      'needsClarification',false,
      'clarifyingQuestion',null,
      'capabilityResult',v_registry,
      'authority','runtime_capability_registry',
      'projectRequired',false
    ),
    'pandora_capability_gateway',
    'deterministic-v2'
  );

  update public.pandora_intelligence_threads
  set last_message_at=now(),updated_at=now()
  where id=v_thread_id;

  return jsonb_build_object(
    'handled',true,
    'threadId',v_thread_id,
    'reply',v_reply,
    'intent','chat',
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'handoff',null,
    'capabilityResult',v_registry
  );
end;
$$;

revoke all on function public.pandora_chat_universal_dispatch_v1(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_universal_dispatch_v1(uuid,text,uuid,uuid) to authenticated;

comment on function public.pandora_chat_universal_dispatch_v1(uuid,text,uuid,uuid)
is 'Universal Pandora Chat capability router. Projects are optional context; provider/plugin questions resolve from live runtime truth and other capability requests delegate to the governed capability gateway.';
