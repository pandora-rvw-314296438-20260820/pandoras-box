-- Exact hosted audit writer/ACL and immutable boundary, read back 2026-10-03.
CREATE OR REPLACE FUNCTION public.record_audit_event(p_organization_id uuid, p_event_type text, p_actor_type audit_actor_type, p_payload_redacted jsonb DEFAULT '{}'::jsonb, p_run_id uuid DEFAULT NULL::uuid, p_step_id uuid DEFAULT NULL::uuid, p_actor_user_id uuid DEFAULT NULL::uuid)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (
    select 1
    from public.organizations organization
    where organization.id = p_organization_id
  ) then
    raise exception 'organization not found';
  end if;

  return private.append_audit_event(
    p_organization_id,
    p_run_id,
    p_step_id,
    p_actor_type,
    p_actor_user_id,
    p_event_type,
    coalesce(p_payload_redacted, '{}'::jsonb)
  );
end;
$function$
;
revoke all on function public.record_audit_event(uuid,text,public.audit_actor_type,jsonb,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.record_audit_event(uuid,text,public.audit_actor_type,jsonb,uuid,uuid,uuid) to service_role;
revoke all on public.audit_events from anon,authenticated,service_role;
grant select on public.audit_events to authenticated,service_role;
alter table public.audit_events enable row level security;
create policy audit_events_select_privileged_member on public.audit_events for select to authenticated using(private.has_org_role(organization_id,array['owner','admin','operator','viewer']::public.member_role[]));
create function private.prevent_audit_mutation() returns trigger language plpgsql set search_path='' as $$ begin raise exception 'audit events are immutable';end; $$;
create trigger audit_events_prevent_update before update on public.audit_events for each row execute function private.prevent_audit_mutation();
create trigger audit_events_prevent_delete before delete on public.audit_events for each row execute function private.prevent_audit_mutation();
