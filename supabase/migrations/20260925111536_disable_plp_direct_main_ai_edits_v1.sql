
begin;

create or replace function private.pandora_direct_plp_code_edit_v1(
  p_organization_id uuid,
  p_message text,
  p_thread_id uuid default null,
  p_project_id uuid default null
) returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private','auth','pg_temp'
as $fn$
declare
  v_uid uuid:=auth.uid();
  v_role text;
  v_project_id uuid;
begin
  if v_uid is null then
    raise exception 'pandora_direct_plp_sign_in_required' using errcode='42501';
  end if;

  select m.role into v_role
  from public.memberships m
  where m.organization_id=p_organization_id
    and m.user_id=v_uid
    and m.status='active'
  limit 1;

  if v_role not in ('owner','admin') then
    raise exception 'pandora_direct_plp_owner_required' using errcode='42501';
  end if;

  select id into v_project_id
  from public.projectos_projects
  where organization_id=p_organization_id
    and project_key='plp-boracay'
  limit 1;

  return jsonb_build_object(
    'handled',true,
    'threadId',p_thread_id,
    'reply','PLP website edits now use preview-before-publish. Open Pueblo La Perla Boracay in Projects, describe the change under Tell Pandora, review the exact preview, then click Publish.',
    'intent','plp_studio_preview_required',
    'confidence',1,
    'needsClarification',false,
    'clarifyingQuestion',null,
    'projectRequired',true,
    'projectId',coalesce(p_project_id,v_project_id),
    'handoff',null,
    'providerReadback',jsonb_build_object(
      'capability','plp.studio.preview_before_publish',
      'verified',true,
      'productionMutation',false,
      'legacyDirectMainDisabled',true,
      'observedAt',now()
    )
  );
end;
$fn$;

revoke all on function private.pandora_direct_plp_code_edit_v1(uuid,text,uuid,uuid)
  from public,anon,authenticated;

commit;

