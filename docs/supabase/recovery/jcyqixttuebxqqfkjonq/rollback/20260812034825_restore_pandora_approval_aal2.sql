-- TESTED DATABASE ROLLBACK FOR 20260812034825.
-- Restores the immediately preceding AAL2 approval boundary without altering history.
-- Apply only as a separately authorized incident rollback; this file is not an active migration.

create or replace function public.decide_approval(
  approval_id uuid,
  requested_decision public.approval_decision,
  reason text default null
)
returns public.approvals
language plpgsql
security definer
set search_path = ''
as $$
declare
  current_user_id uuid := (select auth.uid());
  current_session_id uuid;
  approval_row public.approvals%rowtype;
  step_risk public.risk_class := 'R1'::public.risk_class;
begin
  if current_user_id is null then
    raise exception 'authentication required' using errcode = '28000';
  end if;

  if coalesce(auth.jwt() ->> 'is_anonymous', 'false') = 'true' then
    raise exception 'permanent account required' using errcode = '42501';
  end if;

  if coalesce(auth.jwt() ->> 'aal', 'aal1') <> 'aal2' then
    raise exception 'aal2 required' using errcode = '42501';
  end if;

  begin
    current_session_id := nullif(auth.jwt() ->> 'session_id', '')::uuid;
  exception when invalid_text_representation then
    raise exception 'valid aal2 session required' using errcode = '42501';
  end;

  if current_session_id is null or not exists (
    select 1
    from auth.sessions s
    where s.id = current_session_id
      and s.user_id = current_user_id
      and s.aal = 'aal2'::auth.aal_level
      and (s.not_after is null or s.not_after > now())
  ) then
    raise exception 'valid aal2 session required' using errcode = '42501';
  end if;

  if requested_decision not in (
    'approved'::public.approval_decision,
    'denied'::public.approval_decision
  ) then
    raise exception 'decision must be approved or denied';
  end if;

  select *
    into approval_row
  from public.approvals
  where id = approval_id
  for update;

  if not found then
    raise exception 'approval not found';
  end if;

  if approval_row.step_id is not null then
    select risk
      into step_risk
    from public.workflow_steps
    where id = approval_row.step_id;
  end if;

  if approval_row.decision <> 'pending'::public.approval_decision then
    raise exception 'approval is no longer pending';
  end if;

  if approval_row.expires_at <= timezone('utc', now()) then
    raise exception 'approval has expired';
  end if;

  if approval_row.assigned_to is not null
     and approval_row.assigned_to <> current_user_id then
    raise exception 'approval is assigned to another staff member';
  end if;

  if not private.has_org_role(
    approval_row.organization_id,
    array['owner', 'admin', 'operator']::public.member_role[]
  ) then
    raise exception 'insufficient approval role' using errcode = '42501';
  end if;

  if step_risk in ('R3'::public.risk_class, 'R4'::public.risk_class)
     and approval_row.requested_by = current_user_id then
    raise exception 'high-risk requests require a different approver';
  end if;

  update public.approvals
  set decision = requested_decision,
      decision_by = current_user_id,
      decision_reason = reason,
      decided_at = timezone('utc', now()),
      updated_at = timezone('utc', now())
  where id = approval_id
  returning * into approval_row;

  perform private.append_audit_event(
    approval_row.organization_id,
    approval_row.run_id,
    approval_row.step_id,
    'human'::public.audit_actor_type,
    current_user_id,
    'approval.' || requested_decision::text,
    jsonb_build_object(
      'approval_id', approval_row.id,
      'action_hash', approval_row.action_hash
    )
  );

  return approval_row;
end;
$$;

comment on function public.decide_approval(uuid, public.approval_decision, text)
is 'Decides an approval only for a current, permanent AAL2 session with the existing role, assignment, expiry, and separation-of-duty checks.';
