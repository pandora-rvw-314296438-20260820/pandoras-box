-- R-058 trusted coordinator gate durable state and replay protection.
-- The GitHub required check remains fail-closed; this migration never publishes PASS by itself.

create table if not exists private.pandora_coordinator_gate_decisions (
  id uuid primary key default extensions.gen_random_uuid(),
  repository text not null,
  pull_request_number integer not null check (pull_request_number > 0),
  decision_generation bigint not null check (decision_generation > 0),
  head_sha text not null check (head_sha ~ '^[0-9a-f]{40}$'),
  base_sha text not null check (base_sha ~ '^[0-9a-f]{40}$'),
  authoritative_snapshot_revision text not null,
  authoritative_snapshot_sha256 text not null check (authoritative_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  envelope_hash text not null check (envelope_hash ~ '^[0-9a-f]{64}$'),
  idempotency_key text not null check (idempotency_key ~ '^[0-9a-f]{64}$'),
  decision_nonce text not null,
  decision text not null check (decision in ('PASS','HOLD')),
  expires_at timestamptz not null,
  check_run_id bigint check (check_run_id is null or check_run_id > 0),
  provider_status text,
  provider_conclusion text,
  provider_state text not null default 'pending_publish',
  merge_claim_id uuid,
  merge_claimed_at timestamptz,
  merged_sha text check (merged_sha is null or merged_sha ~ '^[0-9a-f]{40}$'),
  consumed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create unique index if not exists pandora_coordinator_gate_decision_generation_uq
  on private.pandora_coordinator_gate_decisions(repository,pull_request_number,decision_generation);
create unique index if not exists pandora_coordinator_gate_idempotency_uq
  on private.pandora_coordinator_gate_decisions(idempotency_key);
create unique index if not exists pandora_coordinator_gate_nonce_uq
  on private.pandora_coordinator_gate_decisions(decision_nonce);

create table if not exists private.pandora_coordinator_gate_state (
  repository text not null,
  pull_request_number integer not null check (pull_request_number > 0),
  current_decision_id uuid not null references private.pandora_coordinator_gate_decisions(id),
  current_generation bigint not null check (current_generation > 0),
  head_sha text not null check (head_sha ~ '^[0-9a-f]{40}$'),
  base_sha text not null check (base_sha ~ '^[0-9a-f]{40}$'),
  authoritative_snapshot_revision text not null,
  authoritative_snapshot_sha256 text not null check (authoritative_snapshot_sha256 ~ '^[0-9a-f]{64}$'),
  envelope_hash text not null check (envelope_hash ~ '^[0-9a-f]{64}$'),
  idempotency_key text not null check (idempotency_key ~ '^[0-9a-f]{64}$'),
  decision_nonce text not null,
  decision text not null check (decision in ('PASS','HOLD')),
  expires_at timestamptz not null,
  current_check_run_id bigint check (current_check_run_id is null or current_check_run_id > 0),
  provider_status text,
  provider_conclusion text,
  merge_claim_id uuid,
  merge_claimed_at timestamptz,
  merged_sha text,
  consumed_at timestamptz,
  updated_at timestamptz not null default now(),
  primary key(repository,pull_request_number)
);
do $body$
declare
  v_secret_exists boolean := false;
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema='vault' and table_name='decrypted_secrets' and column_name='name'
  ) then
    execute 'select exists(select 1 from vault.decrypted_secrets where name=$1)'
      into v_secret_exists using 'pandora_coordinator_gate_internal_v1';
    if not v_secret_exists then
      perform vault.create_secret(
        encode(extensions.gen_random_bytes(48),'hex'),
        'pandora_coordinator_gate_internal_v1',
        'R-058 coordinator-only publisher and merge-fence key',
        null
      );
    end if;
  end if;
end;
$body$;

create or replace function public.pandora_validate_coordinator_gate_key_v1(p_token text)
returns boolean
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_secret text;
begin
  if p_token is null or length(p_token)<48 or length(p_token)>256 then return false; end if;
  begin
    select decrypted_secret into v_secret
    from vault.decrypted_secrets
    where name='pandora_coordinator_gate_internal_v1'
    limit 1;
  exception when others then
    return false;
  end;
  if nullif(v_secret,'') is null then return false; end if;
  return encode(extensions.digest(convert_to(p_token,'utf8'),'sha256'),'hex')
       = encode(extensions.digest(convert_to(v_secret,'utf8'),'sha256'),'hex');
end;
$body$;
revoke all on function public.pandora_validate_coordinator_gate_key_v1(text) from public,anon,authenticated;
grant execute on function public.pandora_validate_coordinator_gate_key_v1(text) to service_role;

create or replace function public.pandora_coordinator_gate_read_state_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_row private.pandora_coordinator_gate_state%rowtype;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box' or p_pull_request_number < 1 then
    raise exception 'pandora_coordinator_gate_identity_invalid' using errcode='22023';
  end if;
  select * into v_row
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number;
  if not found then return null; end if;
  return to_jsonb(v_row);
end;
$body$;

revoke all on function public.pandora_coordinator_gate_read_state_v1(text,text,integer) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_read_state_v1(text,text,integer) to service_role;
create or replace function public.pandora_coordinator_gate_begin_decision_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_prior_generation bigint,
  p_prior_check_run_id bigint,
  p_head_sha text,
  p_base_sha text,
  p_authoritative_snapshot_revision text,
  p_authoritative_snapshot_sha256 text,
  p_envelope_hash text,
  p_idempotency_key text,
  p_decision_nonce text,
  p_decision text,
  p_expires_at timestamptz
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_existing private.pandora_coordinator_gate_decisions%rowtype;
  v_id uuid;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_repository <> 'pandora-rvw-314296438-20260820/pandoras-box'
     or p_pull_request_number < 1 or p_decision_generation < 1
     or p_head_sha !~ '^[0-9a-f]{40}$' or p_base_sha !~ '^[0-9a-f]{40}$'
     or p_authoritative_snapshot_sha256 !~ '^[0-9a-f]{64}$'
     or p_envelope_hash !~ '^[0-9a-f]{64}$' or p_idempotency_key !~ '^[0-9a-f]{64}$'
     or p_decision not in ('PASS','HOLD') or p_expires_at <= now() then
    raise exception 'pandora_coordinator_gate_decision_invalid' using errcode='22023';
  end if;
  select * into v_existing
  from private.pandora_coordinator_gate_decisions
  where repository=p_repository and pull_request_number=p_pull_request_number
    and decision_generation=p_decision_generation;
  if found then
    if v_existing.head_sha<>p_head_sha or v_existing.base_sha<>p_base_sha
       or v_existing.authoritative_snapshot_revision<>p_authoritative_snapshot_revision
       or v_existing.authoritative_snapshot_sha256<>p_authoritative_snapshot_sha256
       or v_existing.envelope_hash<>p_envelope_hash
       or v_existing.idempotency_key<>p_idempotency_key
       or v_existing.decision_nonce<>p_decision_nonce
       or v_existing.decision<>p_decision then
      raise exception 'pandora_coordinator_gate_generation_conflict' using errcode='23505';
    end if;
    return jsonb_build_object(
      'mode','replay','decisionId',v_existing.id,
      'generation',v_existing.decision_generation,
      'checkRunId',v_existing.check_run_id,
      'providerState',v_existing.provider_state
    );
  end if;

  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if found then
    if p_decision_generation<>v_state.current_generation+1
       or p_prior_generation is distinct from v_state.current_generation
       or p_prior_check_run_id is distinct from v_state.current_check_run_id then
      raise exception 'pandora_coordinator_gate_chain_mismatch' using errcode='23505';
    end if;
  else
    if p_decision_generation<>1 or p_prior_generation is not null or p_prior_check_run_id is not null then
      raise exception 'pandora_coordinator_gate_chain_mismatch' using errcode='23505';
    end if;
  end if;
  insert into private.pandora_coordinator_gate_decisions(
    repository,pull_request_number,decision_generation,head_sha,base_sha,
    authoritative_snapshot_revision,authoritative_snapshot_sha256,
    envelope_hash,idempotency_key,decision_nonce,decision,expires_at,
    check_run_id,provider_state
  ) values (
    p_repository,p_pull_request_number,p_decision_generation,p_head_sha,p_base_sha,
    p_authoritative_snapshot_revision,p_authoritative_snapshot_sha256,
    p_envelope_hash,p_idempotency_key,p_decision_nonce,p_decision,p_expires_at,
    p_prior_check_run_id,'pending_publish'
  ) returning id into v_id;

  insert into private.pandora_coordinator_gate_state(
    repository,pull_request_number,current_decision_id,current_generation,
    head_sha,base_sha,authoritative_snapshot_revision,authoritative_snapshot_sha256,
    envelope_hash,idempotency_key,decision_nonce,decision,expires_at,
    current_check_run_id,provider_status,provider_conclusion,
    merge_claim_id,merge_claimed_at,merged_sha,consumed_at,updated_at
  ) values (
    p_repository,p_pull_request_number,v_id,p_decision_generation,
    p_head_sha,p_base_sha,p_authoritative_snapshot_revision,p_authoritative_snapshot_sha256,
    p_envelope_hash,p_idempotency_key,p_decision_nonce,p_decision,p_expires_at,
    p_prior_check_run_id,null,null,null,null,null,null,now()
  ) on conflict(repository,pull_request_number) do update set
    current_decision_id=excluded.current_decision_id,
    current_generation=excluded.current_generation,
    head_sha=excluded.head_sha,base_sha=excluded.base_sha,
    authoritative_snapshot_revision=excluded.authoritative_snapshot_revision,
    authoritative_snapshot_sha256=excluded.authoritative_snapshot_sha256,
    envelope_hash=excluded.envelope_hash,idempotency_key=excluded.idempotency_key,
    decision_nonce=excluded.decision_nonce,decision=excluded.decision,
    expires_at=excluded.expires_at,current_check_run_id=excluded.current_check_run_id,
    provider_status=null,provider_conclusion=null,merge_claim_id=null,
    merge_claimed_at=null,merged_sha=null,consumed_at=null,updated_at=now();
  return jsonb_build_object(
    'mode','new','decisionId',v_id,'generation',p_decision_generation,
    'priorCheckRunId',p_prior_check_run_id
  );
end;
$body$;

revoke all on function public.pandora_coordinator_gate_begin_decision_v1(
  text,text,integer,bigint,bigint,bigint,text,text,text,text,text,text,text,text,timestamptz
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_begin_decision_v1(
  text,text,integer,bigint,bigint,bigint,text,text,text,text,text,text,text,text,timestamptz
) to service_role;

create or replace function public.pandora_coordinator_gate_record_publish_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_envelope_hash text,
  p_idempotency_key text,
  p_check_run_id bigint,
  p_provider_app_id bigint,
  p_provider_status text,
  p_provider_conclusion text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_state private.pandora_coordinator_gate_state%rowtype;
  v_expected_conclusion text;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_provider_app_id<>4785021 or p_check_run_id<1 or p_provider_status<>'completed' then
    raise exception 'pandora_coordinator_gate_provider_identity_invalid' using errcode='22023';
  end if;
  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found
     or v_state.current_generation<>p_decision_generation
     or v_state.envelope_hash<>p_envelope_hash
     or v_state.idempotency_key<>p_idempotency_key then
    raise exception 'pandora_coordinator_gate_state_mismatch' using errcode='23505';
  end if;
  v_expected_conclusion := case when v_state.decision='PASS' then 'success' else 'action_required' end;
  if p_provider_conclusion<>v_expected_conclusion then
    raise exception 'pandora_coordinator_gate_provider_state_invalid' using errcode='22023';
  end if;
  if v_state.current_check_run_id is not null and v_state.current_check_run_id<>p_check_run_id then
    raise exception 'pandora_coordinator_gate_check_identity_conflict' using errcode='23505';
  end if;

  update private.pandora_coordinator_gate_decisions
  set check_run_id=p_check_run_id,provider_status=p_provider_status,
      provider_conclusion=p_provider_conclusion,
      provider_state=case when v_state.decision='PASS' then 'completed_success' else 'completed_hold' end,
      updated_at=now()
  where id=v_state.current_decision_id;
  update private.pandora_coordinator_gate_state
  set current_check_run_id=p_check_run_id,provider_status=p_provider_status,
      provider_conclusion=p_provider_conclusion,updated_at=now()
  where repository=p_repository and pull_request_number=p_pull_request_number;
  return jsonb_build_object('ok',true,'checkRunId',p_check_run_id,'decision',v_state.decision);
end;
$body$;
revoke all on function public.pandora_coordinator_gate_record_publish_v1(
  text,text,integer,bigint,text,text,bigint,bigint,text,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_record_publish_v1(
  text,text,integer,bigint,text,text,bigint,bigint,text,text
) to service_role;

create or replace function public.pandora_coordinator_gate_mark_expired_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_check_run_id bigint
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_state private.pandora_coordinator_gate_state%rowtype;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found or v_state.current_generation<>p_decision_generation
     or v_state.current_check_run_id<>p_check_run_id or v_state.expires_at>now() then
    raise exception 'pandora_coordinator_gate_expiry_mismatch' using errcode='23505';
  end if;
  update private.pandora_coordinator_gate_decisions
  set provider_status='completed',provider_conclusion='action_required',
      provider_state='expired',updated_at=now()
  where id=v_state.current_decision_id;
  update private.pandora_coordinator_gate_state
  set provider_status='completed',provider_conclusion='action_required',updated_at=now()
  where repository=p_repository and pull_request_number=p_pull_request_number;
  return jsonb_build_object('ok',true,'state','expired');
end;
$body$;
revoke all on function public.pandora_coordinator_gate_mark_expired_v1(
  text,text,integer,bigint,bigint
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_mark_expired_v1(
  text,text,integer,bigint,bigint
) to service_role;

create or replace function public.pandora_coordinator_gate_claim_merge_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_envelope_hash text,
  p_idempotency_key text,
  p_decision_nonce text,
  p_check_run_id bigint,
  p_head_sha text,
  p_base_sha text,
  p_claim_id uuid
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_state private.pandora_coordinator_gate_state%rowtype;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_claim_id is null then
    raise exception 'pandora_coordinator_gate_merge_claim_invalid' using errcode='22023';
  end if;
  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found or v_state.current_generation<>p_decision_generation
     or v_state.envelope_hash<>p_envelope_hash
     or v_state.idempotency_key<>p_idempotency_key
     or v_state.decision_nonce<>p_decision_nonce
     or v_state.current_check_run_id<>p_check_run_id
     or v_state.head_sha<>p_head_sha or v_state.base_sha<>p_base_sha
     or v_state.decision<>'PASS' or v_state.provider_status<>'completed'
     or v_state.provider_conclusion<>'success' or v_state.expires_at<=now()
     or v_state.consumed_at is not null then
    raise exception 'pandora_coordinator_gate_merge_not_authorized' using errcode='42501';
  end if;
  if v_state.merge_claim_id is not null and v_state.merge_claim_id<>p_claim_id then
    raise exception 'pandora_coordinator_gate_merge_already_claimed' using errcode='23505';
  end if;
  update private.pandora_coordinator_gate_state
  set merge_claim_id=coalesce(merge_claim_id,p_claim_id),
      merge_claimed_at=coalesce(merge_claimed_at,now()),updated_at=now()
  where repository=p_repository and pull_request_number=p_pull_request_number;
  update private.pandora_coordinator_gate_decisions
  set merge_claim_id=coalesce(merge_claim_id,p_claim_id),
      merge_claimed_at=coalesce(merge_claimed_at,now()),provider_state='merge_pending',updated_at=now()
  where id=v_state.current_decision_id;
  return jsonb_build_object(
    'ok',true,'claimId',p_claim_id,'headSha',v_state.head_sha,
    'baseSha',v_state.base_sha,'checkRunId',v_state.current_check_run_id,
    'snapshotRevision',v_state.authoritative_snapshot_revision,
    'snapshotSha256',v_state.authoritative_snapshot_sha256,
    'expiresAt',v_state.expires_at
  );
end;
$body$;

revoke all on function public.pandora_coordinator_gate_claim_merge_v1(
  text,text,integer,bigint,text,text,text,bigint,text,text,uuid
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_claim_merge_v1(
  text,text,integer,bigint,text,text,text,bigint,text,text,uuid
) to service_role;
create or replace function public.pandora_coordinator_gate_complete_merge_v1(
  p_internal_key text,
  p_repository text,
  p_pull_request_number integer,
  p_decision_generation bigint,
  p_claim_id uuid,
  p_merge_sha text
) returns jsonb
language plpgsql
security definer
set search_path=''
as $body$
declare
  v_state private.pandora_coordinator_gate_state%rowtype;
begin
  if not public.pandora_validate_coordinator_gate_key_v1(p_internal_key) then
    raise exception 'pandora_coordinator_gate_auth_invalid' using errcode='42501';
  end if;
  if p_merge_sha !~ '^[0-9a-f]{40}$' then
    raise exception 'pandora_coordinator_gate_merge_sha_invalid' using errcode='22023';
  end if;
  select * into v_state
  from private.pandora_coordinator_gate_state
  where repository=p_repository and pull_request_number=p_pull_request_number
  for update;
  if not found or v_state.current_generation<>p_decision_generation
     or v_state.merge_claim_id<>p_claim_id then
    raise exception 'pandora_coordinator_gate_merge_claim_mismatch' using errcode='23505';
  end if;
  if v_state.consumed_at is not null then
    if v_state.merged_sha<>p_merge_sha then
      raise exception 'pandora_coordinator_gate_merge_replay_conflict' using errcode='23505';
    end if;
    return jsonb_build_object('ok',true,'mode','replay','mergeSha',v_state.merged_sha);
  end if;
  update private.pandora_coordinator_gate_state
  set merged_sha=p_merge_sha,consumed_at=now(),updated_at=now()
  where repository=p_repository and pull_request_number=p_pull_request_number;
  update private.pandora_coordinator_gate_decisions
  set merged_sha=p_merge_sha,consumed_at=now(),provider_state='merged',updated_at=now()
  where id=v_state.current_decision_id;
  return jsonb_build_object('ok',true,'mode','completed','mergeSha',p_merge_sha);
end;
$body$;

revoke all on function public.pandora_coordinator_gate_complete_merge_v1(
  text,text,integer,bigint,uuid,text
) from public,anon,authenticated;
grant execute on function public.pandora_coordinator_gate_complete_merge_v1(
  text,text,integer,bigint,uuid,text
) to service_role;

revoke all on table private.pandora_coordinator_gate_decisions from public,anon,authenticated;
revoke all on table private.pandora_coordinator_gate_state from public,anon,authenticated;
grant select,insert,update on table private.pandora_coordinator_gate_decisions to service_role;
grant select,insert,update on table private.pandora_coordinator_gate_state to service_role;
