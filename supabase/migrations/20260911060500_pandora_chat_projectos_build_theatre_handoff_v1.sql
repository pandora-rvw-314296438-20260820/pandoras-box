-- Pandora Chat governed mutation handoff v1
-- A mutating capability request is first admitted by the existing deterministic
-- gateway into ProjectOS. This wrapper only exposes the resulting governed
-- project handoff so the mobile client enters the existing real workspace/build
-- stream. It does not execute a provider mutation and it never fabricates build
-- progress.

do $$
begin
  if to_regprocedure('public.pandora_chat_capability_dispatch_core_v1(uuid,text,uuid,uuid)') is null then
    alter function public.pandora_chat_capability_dispatch_v1(uuid,text,uuid,uuid)
      rename to pandora_chat_capability_dispatch_core_v1;
  end if;
end;
$$;

create or replace function public.pandora_chat_capability_dispatch_v1(
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
  v_result jsonb;
  v_project_id text;
begin
  v_result := public.pandora_chat_capability_dispatch_core_v1(
    p_organization_id,
    p_message,
    p_thread_id,
    p_project_id
  );

  if coalesce(v_result->>'handled','false') = 'true'
     and v_result #>> '{capabilityResult,authority}' = 'projectos' then
    v_project_id := nullif(v_result #>> '{capabilityResult,projectId}','');
    if v_project_id is not null then
      v_result := jsonb_set(
        v_result,
        '{handoff}',
        jsonb_build_object(
          'required', true,
          'request', trim(coalesce(p_message,'')),
          'projectId', v_project_id,
          'source', 'projectos_intake',
          'intakeId', v_result #>> '{capabilityResult,intakeId}'
        ),
        true
      );
    end if;
  end if;

  return v_result;
end;
$$;

revoke all on function public.pandora_chat_capability_dispatch_core_v1(uuid,text,uuid,uuid) from public, anon, authenticated;
revoke all on function public.pandora_chat_capability_dispatch_v1(uuid,text,uuid,uuid) from public, anon;
grant execute on function public.pandora_chat_capability_dispatch_v1(uuid,text,uuid,uuid) to authenticated;

comment on function public.pandora_chat_capability_dispatch_core_v1(uuid,text,uuid,uuid)
is 'Internal deterministic capability gateway retained as the execution/readback core. Direct authenticated execution is intentionally revoked; use pandora_chat_capability_dispatch_v1.';

comment on function public.pandora_chat_capability_dispatch_v1(uuid,text,uuid,uuid)
is 'Authenticated Pandora Chat gateway. Stateful requests remain ProjectOS-governed, then return a real project handoff so the existing workspace can render Build Theatre from backend execution events.';
