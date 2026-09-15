-- Pandora M1-005 durable interruption/control transport v1
-- Controls are user-authored, owner-scoped, idempotent, and never direct client writes to Activity events.

create table if not exists public.pandora_activity_controls (
  id uuid primary key default gen_random_uuid(),
  job_id uuid not null references public.pandora_activity_jobs(id) on delete cascade,
  organization_id uuid not null,
  requested_by uuid not null,
  request_id text not null,
  control_sequence bigint generated always as identity,
  control_type text not null check (control_type in ('cancel','redirect','constraint')),
  instruction text,
  status text not null default 'requested' check (status in ('requested','accepted','applied','rejected')),
  requested_at timestamptz not null default now(),
  accepted_at timestamptz,
  applied_at timestamptz,
  rejection_code text,
  unique (job_id, request_id),
  unique (job_id, control_sequence),
  check (
    (control_type in ('redirect','constraint') and length(trim(instruction)) between 1 and 2000)
    or (control_type='cancel' and instruction is null)
  )
);

create index if not exists pandora_activity_controls_job_status_seq_idx
  on public.pandora_activity_controls(job_id,status,control_sequence);

alter table public.pandora_activity_controls enable row level security;
revoke all on table public.pandora_activity_controls from public, anon, authenticated;
grant select on table public.pandora_activity_controls to authenticated;

drop policy if exists pandora_activity_controls_owner_read on public.pandora_activity_controls;
create policy pandora_activity_controls_owner_read
on public.pandora_activity_controls for select to authenticated
using (
  requested_by=auth.uid()
  and exists (
    select 1
    from public.pandora_activity_jobs j
    join public.memberships m on m.organization_id=j.organization_id
    where j.id=pandora_activity_controls.job_id
      and j.organization_id=pandora_activity_controls.organization_id
      and j.requested_by=auth.uid()
      and m.user_id=auth.uid()
      and m.status='active'
  )
);

create or replace function public.pandora_activity_control_request_v1(
  p_organization_id uuid,
  p_job_id uuid,
  p_request_id text,
  p_control_type text,
  p_instruction text default null
) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_uid uuid := auth.uid();
  v_job public.pandora_activity_jobs%rowtype;
  v_control public.pandora_activity_controls%rowtype;
  v_type text := lower(trim(coalesce(p_control_type,'')));
  v_instruction text := nullif(trim(coalesce(p_instruction,'')),'');
begin
  if v_uid is null then raise exception 'pandora_activity_sign_in_required' using errcode='42501'; end if;
  if p_request_id is null or length(trim(p_request_id)) not between 8 and 200 then raise exception 'pandora_activity_control_request_id_invalid' using errcode='22023'; end if;
  if v_type not in ('cancel','redirect','constraint') then raise exception 'pandora_activity_control_type_invalid' using errcode='22023'; end if;
  if (v_type in ('redirect','constraint') and (v_instruction is null or length(v_instruction)>2000)) or (v_type='cancel' and v_instruction is not null) then raise exception 'pandora_activity_control_instruction_invalid' using errcode='22023'; end if;
  if v_instruction is not null and v_instruction ~* '(github_pat_[A-Za-z0-9_]{20,}|gh[pousr]_[A-Za-z0-9_]{20,}|-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----|postgres(ql)?://[^[:space:]@:]+:[^[:space:]@]+@)' then raise exception 'pandora_activity_control_credential_material_rejected' using errcode='22023'; end if;
  if not exists (select 1 from public.memberships m where m.organization_id=p_organization_id and m.user_id=v_uid and m.status='active') then raise exception 'pandora_activity_membership_required' using errcode='42501'; end if;

  select * into v_job from public.pandora_activity_jobs where id=p_job_id and organization_id=p_organization_id and requested_by=v_uid for update;
  if not found then raise exception 'pandora_activity_job_not_found' using errcode='22023'; end if;

  select * into v_control from public.pandora_activity_controls where job_id=v_job.id and request_id=trim(p_request_id);
  if found then
    if v_control.control_type<>v_type or coalesce(v_control.instruction,'')<>coalesce(v_instruction,'') then raise exception 'pandora_activity_control_idempotency_conflict' using errcode='23505'; end if;
    return jsonb_build_object('controlId',v_control.id,'jobId',v_control.job_id,'requestId',v_control.request_id,'controlSequence',v_control.control_sequence,'controlType',v_control.control_type,'status',v_control.status,'requestedAt',v_control.requested_at);
  end if;
  if v_job.terminal_state is not null then raise exception 'pandora_activity_job_terminal' using errcode='55000'; end if;

  insert into public.pandora_activity_controls(job_id,organization_id,requested_by,request_id,control_type,instruction)
  values (v_job.id,v_job.organization_id,v_uid,trim(p_request_id),v_type,v_instruction)
  on conflict (job_id,request_id) do update set request_id=excluded.request_id
  returning * into v_control;
  if v_control.control_type<>v_type or coalesce(v_control.instruction,'')<>coalesce(v_instruction,'') then raise exception 'pandora_activity_control_idempotency_conflict' using errcode='23505'; end if;

  return jsonb_build_object('controlId',v_control.id,'jobId',v_control.job_id,'requestId',v_control.request_id,'controlSequence',v_control.control_sequence,'controlType',v_control.control_type,'status',v_control.status,'requestedAt',v_control.requested_at);
end;
$body$;

revoke all on function public.pandora_activity_control_request_v1(uuid,uuid,text,text,text) from public, anon;
grant execute on function public.pandora_activity_control_request_v1(uuid,uuid,text,text,text) to authenticated;

create or replace function public.pandora_activity_control_claim_v1(p_job_id uuid) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_job public.pandora_activity_jobs%rowtype;
  v_control public.pandora_activity_controls%rowtype;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'pandora_activity_service_role_required' using errcode='42501'; end if;
  select * into v_job from public.pandora_activity_jobs where id=p_job_id for update;
  if not found then raise exception 'pandora_activity_job_not_found' using errcode='22023'; end if;
  if v_job.terminal_state is not null then return null; end if;
  select * into v_control from public.pandora_activity_controls where job_id=p_job_id and status in ('accepted','requested') order by case when status='accepted' then 0 else 1 end, control_sequence for update skip locked limit 1;
  if not found then return null; end if;
  if v_control.status='requested' then
    update public.pandora_activity_controls set status='accepted',accepted_at=now() where id=v_control.id returning * into v_control;
  end if;
  return jsonb_build_object('controlId',v_control.id,'jobId',v_control.job_id,'requestId',v_control.request_id,'controlSequence',v_control.control_sequence,'controlType',v_control.control_type,'instruction',v_control.instruction,'status',v_control.status,'requestedAt',v_control.requested_at,'acceptedAt',v_control.accepted_at);
end;
$body$;

revoke all on function public.pandora_activity_control_claim_v1(uuid) from public, anon, authenticated;
grant execute on function public.pandora_activity_control_claim_v1(uuid) to service_role;

create or replace function public.pandora_activity_control_apply_v1(p_job_id uuid,p_control_id uuid,p_event jsonb) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_control public.pandora_activity_controls%rowtype;
  v_admitted jsonb;
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'pandora_activity_service_role_required' using errcode='42501'; end if;
  select * into v_control from public.pandora_activity_controls where id=p_control_id and job_id=p_job_id for update;
  if not found then raise exception 'pandora_activity_control_not_found' using errcode='22023'; end if;
  if v_control.status='applied' then return jsonb_build_object('controlId',v_control.id,'status',v_control.status,'appliedAt',v_control.applied_at); end if;
  if v_control.status not in ('requested','accepted') then raise exception 'pandora_activity_control_not_applicable' using errcode='55000'; end if;
  if coalesce(p_event->'control'->>'requestId','')<>v_control.request_id or coalesce(p_event->'control'->>'type','')<>v_control.control_type then raise exception 'pandora_activity_control_event_mismatch' using errcode='22023'; end if;
  if not exists (select 1 from jsonb_array_elements(coalesce(p_event->'evidence','[]'::jsonb)) e where e->>'type'='user_control' and e->>'relation'='accepted_control') then raise exception 'pandora_activity_control_evidence_required' using errcode='22023'; end if;
  if v_control.status='requested' then update public.pandora_activity_controls set status='accepted',accepted_at=coalesce(accepted_at,now()) where id=v_control.id returning * into v_control; end if;
  v_admitted := public.pandora_activity_admit_event_v1(p_job_id,p_event);
  update public.pandora_activity_controls set status='applied',applied_at=now(),rejection_code=null where id=v_control.id returning * into v_control;
  return jsonb_build_object('controlId',v_control.id,'status',v_control.status,'appliedAt',v_control.applied_at,'event',v_admitted);
end;
$body$;

revoke all on function public.pandora_activity_control_apply_v1(uuid,uuid,jsonb) from public, anon, authenticated;
grant execute on function public.pandora_activity_control_apply_v1(uuid,uuid,jsonb) to service_role;

create or replace function public.pandora_activity_control_finish_v1(p_job_id uuid,p_control_id uuid,p_applied boolean,p_rejection_code text default null) returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public, auth
as $body$
declare
  v_control public.pandora_activity_controls%rowtype;
  v_code text := nullif(trim(coalesce(p_rejection_code,'')),'');
begin
  if coalesce(auth.role(),'') <> 'service_role' then raise exception 'pandora_activity_service_role_required' using errcode='42501'; end if;
  if p_applied and v_code is not null then raise exception 'pandora_activity_control_finish_invalid' using errcode='22023'; end if;
  if not p_applied and (v_code is null or length(v_code)>120) then raise exception 'pandora_activity_control_rejection_invalid' using errcode='22023'; end if;
  select * into v_control from public.pandora_activity_controls where id=p_control_id and job_id=p_job_id for update;
  if not found then raise exception 'pandora_activity_control_not_found' using errcode='22023'; end if;
  if v_control.status='applied' then return jsonb_build_object('controlId',v_control.id,'status',v_control.status); end if;
  if v_control.status<>'accepted' then raise exception 'pandora_activity_control_not_accepted' using errcode='55000'; end if;
  update public.pandora_activity_controls set status=case when p_applied then 'applied' else 'rejected' end,applied_at=now(),rejection_code=case when p_applied then null else v_code end where id=v_control.id returning * into v_control;
  return jsonb_build_object('controlId',v_control.id,'status',v_control.status,'appliedAt',v_control.applied_at,'rejectionCode',v_control.rejection_code);
end;
$body$;

revoke all on function public.pandora_activity_control_finish_v1(uuid,uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.pandora_activity_control_finish_v1(uuid,uuid,boolean,text) to service_role;
