
create or replace function private.pandora_enterprise_session_scope_v1(p_organization_id uuid)
returns boolean
language sql
stable
security definer
set search_path=''
as $$
  select not exists(
    select 1
    from public.pandora_enterprise_accounts
    where organization_id=p_organization_id
  )
  or exists(
    select 1
    from public.pandora_enterprise_accounts a
    where a.organization_id=p_organization_id
      and a.lifecycle_state not in ('suspended','offboarding','archived')
      and (
        not private.pandora_enterprise_internal_actor_v1()
        or private.pandora_tenant_member_role_v1(p_organization_id) in ('owner','admin')
        or exists(
          select 1
          from private.pandora_client_entry_sessions e
          where e.organization_id=p_organization_id
            and e.actor_user_id=auth.uid()
            and e.ended_at is null
            and e.expires_at>now()
            and public.pandora_core_validate_entry_v1(e.id,p_organization_id)
        )
      )
  );
$$;

revoke all on function private.pandora_enterprise_session_scope_v1(uuid)
from public,anon,authenticated;

create or replace function private.pandora_enterprise_assert_v1(
  p_organization_id uuid,
  p_entry_id uuid,
  p_write boolean default false
)
returns text
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_role text;
begin
  v_role:=private.pandora_tenant_member_role_v1(p_organization_id);

  if p_organization_id is null
     or v_role is null
     or not exists(
       select 1
       from public.pandora_enterprise_accounts a
       where a.organization_id=p_organization_id
         and a.lifecycle_state not in ('suspended','offboarding','archived')
     ) then
    raise exception 'ACCESS_DENIED' using errcode='42501';
  end if;

  if p_entry_id is not null then
    if public.pandora_core_validate_entry_v1(p_entry_id,p_organization_id) is not true then
      raise exception 'CLIENT_ENTRY_REQUIRED' using errcode='42501';
    end if;
  elsif private.pandora_enterprise_internal_actor_v1()
        and v_role not in ('owner','admin') then
    raise exception 'CLIENT_ENTRY_REQUIRED' using errcode='42501';
  end if;

  if p_write and v_role not in ('owner','admin','operator','member') then
    raise exception 'ACCESS_DENIED' using errcode='42501';
  end if;

  return v_role;
end;
$$;

revoke all on function private.pandora_enterprise_assert_v1(uuid,uuid,boolean)
from public,anon,authenticated;

create or replace function public.pandora_enterprise_chat_authority_v1(
  p_organization_id uuid,
  p_entry_id uuid default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
declare
  v_platform uuid;
  v_role text;
  v_core text;
  v_account public.pandora_enterprise_accounts%rowtype;
  v_internal boolean;
  v_direct_tenant_admin boolean;
begin
  select platform_organization_id into v_platform
  from private.pandora_core_config
  where singleton;

  if p_organization_id is null then
    raise exception 'ACCESS_DENIED' using errcode='42501';
  end if;

  if p_organization_id=v_platform then
    if p_entry_id is not null then
      raise exception 'ACCESS_DENIED' using errcode='42501';
    end if;
    v_core:=private.pandora_core_assert_v1(
      null,
      array['owner','operator','support','finance'],
      false
    );
    v_role:=private.pandora_tenant_member_role_v1(p_organization_id);
    return jsonb_build_object(
      'organization_id',p_organization_id,
      'actor_role',v_role,
      'scope_kind','platform',
      'requires_operator_entry',false,
      'adapter_key','pandora_core_v1',
      'core_role',v_core,
      'can_execute_core',v_core in ('owner','operator')
    );
  end if;

  select * into v_account
  from public.pandora_enterprise_accounts
  where organization_id=p_organization_id;

  if not found then
    raise exception 'ACCESS_DENIED' using errcode='42501';
  end if;

  v_role:=private.pandora_enterprise_assert_v1(
    p_organization_id,
    p_entry_id,
    false
  );
  v_internal:=private.pandora_enterprise_internal_actor_v1();
  v_direct_tenant_admin:=
    p_entry_id is null and v_internal and v_role in ('owner','admin');

  return jsonb_build_object(
    'organization_id',p_organization_id,
    'actor_role',v_role,
    'scope_kind',case
      when v_direct_tenant_admin then 'member'
      when v_internal then 'administrator'
      else 'member'
    end,
    'requires_operator_entry',v_internal and not v_direct_tenant_admin,
    'core_role',null,
    'can_execute_core',false,
    'adapter_key',case
      when v_account.workspace_type='plp'
       and v_account.property_id is not null
       and exists(
         select 1
         from public.organizations
         where id=p_organization_id
           and slug='plp-boracay'
       )
      then 'plp_v1'
      else 'enterprise_core_v1'
    end
  );
end;
$$;

revoke all on function public.pandora_enterprise_chat_authority_v1(uuid,uuid)
from public,anon;
grant execute on function public.pandora_enterprise_chat_authority_v1(uuid,uuid)
to authenticated;

create or replace function public.pandora_enterprise_my_workspaces_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path=''
as $$
begin
  if auth.uid() is null
     or coalesce(auth.jwt()->>'is_anonymous','false')='true'
     or not exists(
       select 1
       from auth.users u
       where u.id=auth.uid()
         and not coalesce(u.is_anonymous,false)
         and u.deleted_at is null
         and (u.banned_until is null or u.banned_until<=now())
     ) then
    raise exception 'ACCESS_DENIED' using errcode='42501';
  end if;

  return jsonb_build_object(
    'operator_mode',private.pandora_core_role_v1(null) is not null,
    'workspaces',coalesce((
      select jsonb_agg(
        jsonb_build_object(
          'organization_id',o.id,
          'display_name',o.name,
          'slug',o.slug,
          'workspace_type',a.workspace_type,
          'property_id',a.property_id,
          'role',m.role,
          'adapter_key',case
            when a.workspace_type='plp'
             and o.slug='plp-boracay'
             and a.property_id is not null
            then 'plp_v1'
            else 'enterprise_core_v1'
          end,
          'requires_operator_entry',
            private.pandora_enterprise_internal_actor_v1()
            and m.role::text not in ('owner','admin')
        )
        order by o.name
      )
      from public.memberships m
      join public.organizations o
        on o.id=m.organization_id
       and o.status='active'
      join public.pandora_enterprise_accounts a
        on a.organization_id=o.id
      where m.user_id=auth.uid()
        and m.status='active'
        and a.lifecycle_state not in ('suspended','offboarding','archived')
    ),'[]'::jsonb)
  );
end;
$$;

revoke all on function public.pandora_enterprise_my_workspaces_v1()
from public,anon;
grant execute on function public.pandora_enterprise_my_workspaces_v1()
to authenticated;
