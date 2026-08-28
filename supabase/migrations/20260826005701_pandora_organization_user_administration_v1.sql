-- Adds the governed Auth-to-membership bridge required by Pandora's
-- organization user-administration experience. The service-role credential
-- remains confined to the Edge Function; this RPC runs with the caller's JWT.

create or replace function public.pandora_add_organization_member(
  p_organization_id uuid,
  p_target_user_id uuid,
  p_role public.member_role
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  actor_user_id uuid := auth.uid();
  actor_role public.member_role;
  target_confirmed boolean;
  target_anonymous boolean;
  existing_membership public.memberships%rowtype;
  desired_status public.membership_status;
  changed_at timestamptz := clock_timestamp();
  audit_event_type text;
begin
  if actor_user_id is null
     or coalesce(auth.role(), '') <> 'authenticated'
     or coalesce(auth.jwt() ->> 'is_anonymous', 'false') = 'true'
     or exists (
       select 1
       from auth.users caller
       where caller.id = actor_user_id
         and caller.is_anonymous = true
     ) then
    raise exception 'authenticated non-anonymous administrator required'
      using errcode = '42501';
  end if;

  if p_organization_id is null or p_target_user_id is null or p_role is null then
    raise exception 'organization, target user, and role are required'
      using errcode = '22023';
  end if;

  if p_target_user_id = actor_user_id then
    raise exception 'cannot change your own membership through the add-user workflow'
      using errcode = '42501';
  end if;

  select membership.role
    into actor_role
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = actor_user_id
    and membership.status = 'active'::public.membership_status;

  if actor_role is null or actor_role not in (
    'owner'::public.member_role,
    'admin'::public.member_role
  ) then
    raise exception 'active owner or administrator membership required'
      using errcode = '42501';
  end if;

  if actor_role = 'admin'::public.member_role
     and p_role not in (
       'operator'::public.member_role,
       'member'::public.member_role,
       'viewer'::public.member_role
     ) then
    raise exception 'administrators cannot grant owner or admin roles'
      using errcode = '42501';
  end if;

  select account.email_confirmed_at is not null,
         coalesce(account.is_anonymous, false)
    into target_confirmed, target_anonymous
  from auth.users account
  where account.id = p_target_user_id;

  if not found or target_anonymous then
    raise exception 'target must be an existing non-anonymous auth user'
      using errcode = '22023';
  end if;

  -- Serialize add/re-add attempts for this exact organization/user pair.
  perform pg_advisory_xact_lock(
    hashtextextended(p_organization_id::text || ':' || p_target_user_id::text, 0)
  );

  select membership.*
    into existing_membership
  from public.memberships membership
  where membership.organization_id = p_organization_id
    and membership.user_id = p_target_user_id
  for update;

  desired_status := case
    when target_confirmed then 'active'::public.membership_status
    else 'invited'::public.membership_status
  end;

  if found then
    if existing_membership.status in (
      'active'::public.membership_status,
      'invited'::public.membership_status
    ) then
      if existing_membership.role <> p_role then
        raise exception 'membership already exists with another role'
          using errcode = '23505';
      end if;

      -- Active membership is never downgraded merely because an Auth record is
      -- temporarily unconfirmed. An invited membership is reconciled to active
      -- when the target account is already confirmed.
      if existing_membership.status = 'active'::public.membership_status
         or existing_membership.status = desired_status then
        return jsonb_build_object(
          'userId', existing_membership.user_id,
          'organizationId', existing_membership.organization_id,
          'role', existing_membership.role,
          'status', existing_membership.status,
          'created', false,
          'restored', false,
          'idempotent', true
        );
      end if;

      update public.memberships
      set status = 'active'::public.membership_status,
          joined_at = coalesce(joined_at, changed_at),
          invited_by = coalesce(invited_by, actor_user_id),
          updated_at = changed_at
      where organization_id = p_organization_id
        and user_id = p_target_user_id;

      desired_status := 'active'::public.membership_status;
      audit_event_type := 'organization.member.activated';
    else
      update public.memberships
      set role = p_role,
          status = desired_status,
          invited_by = actor_user_id,
          joined_at = case when desired_status = 'active' then changed_at else null end,
          updated_at = changed_at
      where organization_id = p_organization_id
        and user_id = p_target_user_id;

      audit_event_type := 'organization.member.restored';
    end if;
  else
    insert into public.memberships (
      organization_id,
      user_id,
      role,
      status,
      invited_by,
      joined_at,
      created_at,
      updated_at
    ) values (
      p_organization_id,
      p_target_user_id,
      p_role,
      desired_status,
      actor_user_id,
      case when desired_status = 'active' then changed_at else null end,
      changed_at,
      changed_at
    );

    audit_event_type := case
      when desired_status = 'active' then 'organization.member.added'
      else 'organization.member.invited'
    end;
  end if;

  perform private.append_audit_event(
    p_organization_id,
    null,
    null,
    'human'::public.audit_actor_type,
    actor_user_id,
    audit_event_type,
    jsonb_build_object(
      'target_user_id', p_target_user_id,
      'role', p_role,
      'status', desired_status,
      'source', 'pandora-user-admin'
    )
  );

  return jsonb_build_object(
    'userId', p_target_user_id,
    'organizationId', p_organization_id,
    'role', p_role,
    'status', desired_status,
    'created', existing_membership.organization_id is null,
    'restored', existing_membership.organization_id is not null,
    'idempotent', false
  );
end;
$function$;

revoke all on function public.pandora_add_organization_member(
  uuid,
  uuid,
  public.member_role
) from public, anon;
grant execute on function public.pandora_add_organization_member(
  uuid,
  uuid,
  public.member_role
) to authenticated;

comment on function public.pandora_add_organization_member(
  uuid,
  uuid,
  public.member_role
) is
  'Organization-scoped, role-bounded, audited membership creation used by pandora-user-admin.';

create or replace function private.activate_invited_memberships()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  activated_membership record;
begin
  if old.email_confirmed_at is null and new.email_confirmed_at is not null then
    for activated_membership in
      update public.memberships
      set status = 'active'::public.membership_status,
          joined_at = coalesce(joined_at, clock_timestamp()),
          updated_at = clock_timestamp()
      where user_id = new.id
        and status = 'invited'::public.membership_status
      returning organization_id, role
    loop
      perform private.append_audit_event(
        activated_membership.organization_id,
        null,
        null,
        'human'::public.audit_actor_type,
        new.id,
        'organization.member.activated',
        jsonb_build_object(
          'target_user_id', new.id,
          'role', activated_membership.role,
          'status', 'active',
          'source', 'auth-email-confirmation'
        )
      );
    end loop;
  end if;

  return new;
end;
$function$;

revoke all on function private.activate_invited_memberships()
  from public, anon, authenticated;

drop trigger if exists on_auth_user_confirmed_memberships on auth.users;
create trigger on_auth_user_confirmed_memberships
after update of email_confirmed_at on auth.users
for each row
when (old.email_confirmed_at is null and new.email_confirmed_at is not null)
execute function private.activate_invited_memberships();
