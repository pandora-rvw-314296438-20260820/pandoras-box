-- Pandora multi-capability workflow routing v1
-- One owner request may span multiple providers, but execution remains ordered,
-- fail-closed, and governed. This migration plans and records the workflow only;
-- it never bypasses ProjectOS or claims provider completion.

create or replace function private.pandora_multi_capability_workflow_v1(
  p_organization_id uuid,
  p_message text,
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
  v_registry jsonb;
  v_steps jsonb := '[]'::jsonb;
  v_step jsonb;
  v_provider jsonb;
  v_action jsonb;
  v_provider_count integer := 0;
  v_available_count integer := 0;
  v_has_write boolean := false;
  v_project public.projectos_projects%rowtype;
  v_intake jsonb;
  v_idempotency text;
  v_blocked jsonb := '[]'::jsonb;

  procedure add_step(p_provider text, p_action text, p_mode text, p_reason text)
  language plpgsql
  as $proc$
  declare
    v_available boolean := false;
  begin
    select exists(
      select 1
      from jsonb_array_elements(coalesce(v_registry->'providers','[]'::jsonb)) p,
         jsonb_array_elements(coalesce(p->'actions','[]'::jsonb)) a
      where p->>'provider'=p_provider
        and coalesce((p->>'canUseNow')::boolean,false)
        and a->>'name'=p_action
        and coalesce((a->>'available')::boolean,false)
    ) into v_available;

    v_step := jsonb_build_object(
      'sequence', jsonb_array_length(v_steps) + 1,
      'provider', p_provider,
      'action', p_action,
      'mode', p_mode,
      'reason', p_reason,
      'runtimeAvailable', v_available,
      'authority',
case when p_mode='write' then 'projectos' else 'governed_adapter' end,
      'verifiedComplete', false
    );
    v_steps := v_steps || jsonb_build_array(v_step);
    v_provider_count := v_provider_count + 1;
    if v_available then
      v_available_count := v_available_count + 1;
    else
      v_blocked := v_blocked || jsonb_build_array(jsonb_build_object(
        'provider',p_provider,'action',p_action,'reason','runtime_authority_unavailable'
      ));
    end if;
    if p_mode='write' then v_has_write := true; end if;
  end;
  $proc$;
begin
  if v_uid is null then
    raise exception 'pandora_multi_workflow_sign_in_required' using errcode='42501';
  end if;
  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;
  if v_role not in ('owner','admin') then
    raise exception 'pandora_multi_workflow_owner_required' using errcode='42501';
  end if;
  if v_message='' or length(v_message)>8000 then
    raise exception 'pandora_multi_workflow_invalid_message' using errcode='22023';
  end if;

  if p_project_id is not null then
    select * into v_project
    from public.projectos_projects
    where organization_id=p_organization_id and id=p_project_id
    limit 1;
    if not found then
      raise exception 'pandora_multi_workflow_project_not_found' using errcode='22023';
    end if;
  end if;

  v_registry := public.pandora_plugin_runtime_registry_v4(p_organization_id);

  -- Canonical cross-capability remediation chain:
  -- analytics -> code read -> code fix -> deploy.
  if v_message ~* '\\m(posthog|analytics|funnel|retention|events)\\M'
     and v_message ~,J‹(Å*archived too large to show fully."}}'ssensething