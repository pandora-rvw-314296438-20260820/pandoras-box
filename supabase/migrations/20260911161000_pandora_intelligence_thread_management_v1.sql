-- Owner-scoped conversation management for Pandora Intelligence history.
-- Thread metadata mutations remain bounded to the authenticated creator and active org membership.

create or replace function public.pandora_intelligence_thread_manage_v1(
  p_organization_id uuid,
  p_thread_id uuid,
  p_action text,
  p_title text default null,
  p_project_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_action text := lower(trim(coalesce(p_action,'')));
  v_title text := nullif(trim(coalesce(p_title,'')), '');
  v_thread public.pandora_intelligence_threads%rowtype;
begin
  if v_uid is null then
    raise exception 'AUTH_REQUIRED' using errcode = '42501';
  end if;

  if not exists (
    select 1 from public.memberships m
    where m.organization_id = p_organization_id
      and m.user_id = v_uid
      and m.status = 'active'
  ) then
    raise exception 'ORG_MEMBERSHIP_REQUIRED' using errcode = '42501';
  end if;

  select * into v_thread
  from public.pandora_intelligence_threads t
  where t.id = p_thread_id
    and t.organization_id = p_organization_id
    and t.created_by = v_uid
  for update;

  if not found then
    raise exception 'THREAD_NOT_FOUND' using errcode = 'P0002';
  end if;

  if v_action = 'rename' then
    if v_title is null or length(v_title) > 200 then
      raise exception 'INVALID_THREAD_TITLE' using errcode = '22023';
    end if;
    update public.pandora_intelligence_threads
    set title = v_title, updated_at = now()
    where id = p_thread_id;
  elsif v_action = 'archive' then
    update public.pandora_intelligence_threads
    set status = 'archived', updated_at = now()
    where id = p_thread_id;
  elsif v_action = 'restore' then
    update public.pandora_intelligence_threads
    set status = 'active', updated_at = now()
    where id = p_thread_id;
  elsif v_action = 'associate_project' then
    if p_project_id is not null and not private.pandora_control_plane_project_org_matches(p_organization_id, p_project_id) then
      raise exception 'PROJECT_ORG_MISMATCH' using errcode = '22023';
    end if;
    update public.pandora_intelligence_threads
    set project_id = p_project_id, updated_at = now()
    where id = p_thread_id;
    update public.pandora_intelligence_messages
    set project_id = p_project_id
    where thread_id = p_thread_id
      and organization_id = p_organization_id;
  elsif v_action = 'delete' then
    delete from public.pandora_intelligence_threads where id = p_thread_id;
    return jsonb_build_object(
      'ok', true,
      'threadId', p_thread_id,
      'action', 'delete',
      'deleted', true
    );
  else
    raise exception 'UNSUPPORTED_THREAD_ACTION' using errcode = '22023';
  end if;

  select * into v_thread
  from public.pandora_intelligence_threads t
  where t.id = p_thread_id;

  return jsonb_build_object(
    'ok', true,
    'threadId', v_thread.id,
    'action', v_action,
    'title', v_thread.title,
    'status', v_thread.status,
    'projectId', v_thread.project_id,
    'updatedAt', v_thread.updated_at
  );
end;
$$;

revoke all on function public.pandora_intelligence_thread_manage_v1(uuid,uuid,text,text,uuid) from public;
grant execute on function public.pandora_intelligence_thread_manage_v1(uuid,uuid,text,text,uuid) to authenticated;
grant execute on function public.pandora_intelligence_thread_manage_v1(uuid,uuid,text,text,uuid) to service_role;
