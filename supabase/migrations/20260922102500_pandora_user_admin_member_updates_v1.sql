begin;

create or replace function public.pandora_admin_update_organization_member(
  p_actor_user_id uuid,
  p_organization_id uuid,
  p_target_user_id uuid,
  p_role public.member_role default null,
  p_status public.membership_status default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_role public.member_role;
  current_membership public.memberships%rowtype;
  next_role public.member_role;
  next_status public.membership_status;
  changed_at timestamptz := clock_timestamp();
  remaining_active_owners integer;
  event_type text;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service-role broker required'
      using errcode = '42501';
  end if;

  if p_actor_user_id is null
     or not exists (
       select 1
       from auth.users caller
       where caller.id = p_actor_user_id
         and coalesce(caller.is_anonymous, false) = false
     ) then
    raise exception 'existing non-anonymous administrator required'
      using errcode = '22023';
  end if;

  if p_organization_id is null or p_target_user_id is null then
    raise exception 'organization and target user are required'
      using errcode = '22023';
  end if;

  if p_role is null and p_status is null then
    raise exception 'role or status change required'
      using errcode = '22023';
  end if;

  if p_target_user_id = p_actor_user_id then
    raise exception 'cannot change your own membership through the user-admin workflow'
      using errcode = '42501';
  end if;

  select membership.role
    into actor_role
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_actor_user_id
    and membership.status = 'active'::public.membership_status;

  if actor_role is null or actor_role not in (
    'owner'::public.member_role,
    'admin'::public.member_role
  ) then
    raise exception 'active owner or administrator membership required'
      using errcode = '42501';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':' || p_target_user_id::text, 0)
  );

  select membership.*
    into current_membership
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_target_user_id
  for update;

  if not found then
    raise exception 'target membership not found'
      using errcode = 'P0002';
  end if;

  next_role := coalesce(p_role, current_membership.role);
  next_status := coalesce(p_status, current_membership.status);

  if next_status = 'invited'::public.membership_status then
    raise exception 'use invitation workflow for invited membership'
      using errcode = '22023';
  end if;

  if actor_role = 'admin'::public.member_role then
    if current_membership.role in (
      'owner'::public.member_role,
      'admin'::public.member_role
    ) then
      raise exception 'administrators cannot modify owner or admin memberships'
        using errcode = '42501';
    end if;
    if next_role in (
      'owner'::public.member_role,
      'admin'::public.member_role
    ) then
      raise exception 'administrators cannot grant owner or admin roles'
        using errcode = '42501';
    end if;
  end if;

  if current_membership.role = 'owner'::public.member_role
     and current_membership.status = 'active'::public.membership_status
     and (
       next_role <> 'owner'::public.member_role
       or next_status <> 'active'::public.membership_status
     ) then
    select count(*)
      into remaining_active_owners
    from public.memberships membership
    where membership.organization_id = p_organization_id
      and membership.user_id <> p_target_user_id
      and membership.role = 'owner'::public.member_role
      and membership.status = 'active'::public.membership_status;

    if remaining_active_owners < 1 then
      raise exception 'cannot remove the last active owner'
        using errcode = '42501';
    end if;
  end if;

  if current_membership.role = next_role
     and current_membership.status = next_status then
    return jsonb_build_object(
      'userId', current_membership.user_id,
      'organizationId', current_membership.organization_id,
      'previousRole', current_membership.role,
      'role', current_membership.role,
      'previousStatus', current_membership.status,
      'status', current_membership.status,
      'changed', false,
      'idempotent', true
    );
  end if;

  update public.memberships
  set role = next_role,
      status = next_status,
      joined_at = case
        when next_status = 'active'::public.membership_status
          then coalesce(joined_at, changed_at)
        else joined_at
      end,
      updated_at = changed_at
  where organization_id = p_organization_id
    and user_id = p_target_user_id;

  event_type := case
    when next_status = 'revoked'::public.membership_status
      then 'organization.member.revoked'
    when next_status = 'suspended'::public.membership_status
      then 'organization.member.suspended'
    when current_membership.status <> 'active'::public.membership_status
         and next_status = 'active'::public.membership_status
      then 'organization.member.activated'
    when current_membership.role <> next_role
      then 'organization.member.role_changed'
    else 'organization.member.updated'
  end;

  perform private.append_audit_event(
    p_organization_id,
    null,
    null,
    'human'::public.audit_actor_type,
    p_actor_user_id,
    event_type,
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'previous_role', current_membership.role,
      'role', next_role,
      'previous_status', current_membership.status,
      'status', next_status,
      'source', 'pandora-user-admin'
    )
  );

  return jsonb_build_object(
    'userId', p_target_user_id,
    'organizationId', p_organization_id,
    'previousRole', current_membership.role,
    'role', next_role,
    'previousStatus', current_membership.status,
    'status', next_status,
    'changed', true,
    'idempotent', false
  );
end;
$function$;

revoke all on function public.pandora_admin_update_organization_member(
  uuid,
  uuid,
  uuid,
  public.member_role,
  public.membership_status
) from public, anon, authenticated;

grant execute on function public.pandora_admin_update_organization_member(
  uuid,
  uuid,
  uuid,
  public.member_role,
  public.membership_status
) to service_role;

comment on function public.pandora_admin_update_organization_member(
  uuid,
  uuid,
  uuid,
  public.member_role,
  public.membership_status
) is
  'Service-role-brokered, organization-scoped, audited membership role/status mutation used by pandora-user-admin.';

commit;
