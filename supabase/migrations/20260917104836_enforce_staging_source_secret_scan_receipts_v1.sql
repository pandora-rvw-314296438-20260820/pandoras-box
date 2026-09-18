
create table if not exists pandora_staging.pandora_secret_scan_receipts (
  id uuid primary key default gen_random_uuid(),
  snapshot_id uuid not null unique references pandora_staging.pandora_snapshots(id) on delete restrict,
  source_bundle_sha256 text not null check (source_bundle_sha256 ~ '^[0-9a-f]{64}$'),
  engine_version text not null check (engine_version ~ '^[A-Za-z0-9._-]{1,80}$'),
  scanned_file_count integer not null check (scanned_file_count > 0 and scanned_file_count <= 5000),
  scanned_bytes bigint not null check (scanned_bytes > 0 and scanned_bytes <= 19922944),
  findings_count integer not null default 0 check (findings_count = 0),
  passed boolean not null check (passed is true),
  evidence jsonb not null default '{}'::jsonb check (jsonb_typeof(evidence)='object'),
  created_by text not null check (length(created_by) between 1 and 200),
  created_at timestamptz not null default now()
);

alter table pandora_staging.pandora_secret_scan_receipts enable row level security;
revoke all on pandora_staging.pandora_secret_scan_receipts from public, anon, authenticated, service_role;

create or replace function pandora_staging.reject_secret_scan_receipt_mutation()
returns trigger
language plpgsql
set search_path=pg_catalog,pandora_staging
as $$
begin
  raise exception 'pandora_staging_secret_scan_receipt_immutable' using errcode='42501';
end;
$$;

drop trigger if exists pandora_secret_scan_receipts_immutable on pandora_staging.pandora_secret_scan_receipts;
create trigger pandora_secret_scan_receipts_immutable
before update or delete on pandora_staging.pandora_secret_scan_receipts
for each row execute function pandora_staging.reject_secret_scan_receipt_mutation();

create or replace function public.pandora_staging_record_secret_scan_v1(
  p_snapshot_id uuid,
  p_source_bundle_sha256 text,
  p_engine_version text,
  p_scanned_file_count integer,
  p_scanned_bytes bigint,
  p_actor text,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pandora_staging
as $$
declare
  v_snapshot pandora_staging.pandora_snapshots;
  v_receipt pandora_staging.pandora_secret_scan_receipts;
begin
  select * into v_snapshot
  from pandora_staging.pandora_snapshots
  where id=p_snapshot_id
  for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state <> 'staged' then raise exception 'pandora_staging_secret_scan_wrong_state' using errcode='55000'; end if;
  if v_snapshot.source_bundle_sha256 <> p_source_bundle_sha256
     or p_source_bundle_sha256 !~ '^[0-9a-f]{64}$'
     or p_engine_version !~ '^[A-Za-z0-9._-]{1,80}$'
     or p_scanned_file_count not between 1 and 5000
     or p_scanned_bytes not between 1 and 19922944
     or nullif(trim(p_actor),'') is null
     or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb)) <> 'object' then
    raise exception 'pandora_staging_secret_scan_receipt_invalid' using errcode='22023';
  end if;

  select * into v_receipt
  from pandora_staging.pandora_secret_scan_receipts
  where snapshot_id=p_snapshot_id;
  if found then
    if v_receipt.source_bundle_sha256=p_source_bundle_sha256
       and v_receipt.engine_version=p_engine_version
       and v_receipt.scanned_file_count=p_scanned_file_count
       and v_receipt.scanned_bytes=p_scanned_bytes then
      return jsonb_build_object(
        'snapshotId',p_snapshot_id,'receiptId',v_receipt.id,'passed',true,
        'findingsCount',0,'engineVersion',v_receipt.engine_version,'alreadyRecorded',true
      );
    end if;
    raise exception 'pandora_staging_secret_scan_receipt_conflict' using errcode='55000';
  end if;

  insert into pandora_staging.pandora_secret_scan_receipts(
    snapshot_id,source_bundle_sha256,engine_version,scanned_file_count,scanned_bytes,
    findings_count,passed,evidence,created_by
  ) values (
    p_snapshot_id,p_source_bundle_sha256,p_engine_version,p_scanned_file_count,p_scanned_bytes,
    0,true,coalesce(p_evidence,'{}'::jsonb),p_actor
  ) returning * into v_receipt;

  perform pandora_staging.append_event(
    p_snapshot_id,'snapshot.secret_scan_passed','staged','staged',p_actor,
    jsonb_build_object(
      'receiptId',v_receipt.id,
      'sourceBundleSha256',p_source_bundle_sha256,
      'engineVersion',p_engine_version,
      'scannedFileCount',p_scanned_file_count,
      'scannedBytes',p_scanned_bytes,
      'findingsCount',0
    ) || coalesce(p_evidence,'{}'::jsonb)
  );

  return jsonb_build_object(
    'snapshotId',p_snapshot_id,'receiptId',v_receipt.id,'passed',true,
    'findingsCount',0,'engineVersion',v_receipt.engine_version,'alreadyRecorded',false
  );
end;
$$;

create or replace function public.pandora_staging_seal_snapshot_v1(
  p_snapshot_id uuid,
  p_actor text,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pandora_staging
as $$
declare
  v_snapshot pandora_staging.pandora_snapshots;
  v_scan pandora_staging.pandora_secret_scan_receipts;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state <> 'staged' then raise exception 'pandora_staging_snapshot_not_staged' using errcode='55000'; end if;
  if v_snapshot.sealed_at is not null then
    return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'sealedAt',v_snapshot.sealed_at,'alreadySealed',true);
  end if;
  if nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb)) <> 'object' then
    raise exception 'pandora_staging_seal_invalid' using errcode='22023';
  end if;
  select * into v_scan
  from pandora_staging.pandora_secret_scan_receipts
  where snapshot_id=p_snapshot_id
    and source_bundle_sha256=v_snapshot.source_bundle_sha256
    and passed is true
    and findings_count=0;
  if not found then raise exception 'pandora_staging_secret_scan_required' using errcode='55000'; end if;

  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots
  set sealed_at=now(),updated_at=now()
  where id=p_snapshot_id
  returning * into v_snapshot;
  perform pandora_staging.append_event(
    v_snapshot.id,'snapshot.sealed','staged','staged',p_actor,
    coalesce(p_evidence,'{}'::jsonb) || jsonb_build_object('secretScanReceiptId',v_scan.id,'secretScanEngineVersion',v_scan.engine_version)
  );
  return jsonb_build_object(
    'snapshotId',v_snapshot.id,'state',v_snapshot.state,'sealedAt',v_snapshot.sealed_at,
    'secretScanReceiptId',v_scan.id,'alreadySealed',false
  );
end;
$$;

create or replace function public.pandora_staging_transition_snapshot_v1(
  p_snapshot_id uuid,
  p_expected_state text,
  p_new_state text,
  p_actor text,
  p_evidence jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path=pg_catalog,public,pandora_staging
as $$
declare
  v_snapshot pandora_staging.pandora_snapshots;
  v_allowed boolean:=false;
  v_secret_scan_ok boolean:=false;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state <> p_expected_state then raise exception 'pandora_staging_state_moved' using errcode='40001'; end if;
  if nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb)) <> 'object' then
    raise exception 'pandora_staging_transition_invalid' using errcode='22023';
  end if;
  v_allowed :=
    (p_expected_state='staged' and p_new_state in ('building','rejected')) or
    (p_expected_state='building' and p_new_state in ('verified','rejected')) or
    (p_expected_state='verified' and p_new_state='rejected');
  if not v_allowed then raise exception 'pandora_staging_transition_not_allowed' using errcode='22023'; end if;
  if p_new_state='building' then
    if v_snapshot.sealed_at is null then raise exception 'pandora_staging_snapshot_not_sealed' using errcode='55000'; end if;
    select exists(
      select 1 from pandora_staging.pandora_secret_scan_receipts r
      where r.snapshot_id=p_snapshot_id
        and r.source_bundle_sha256=v_snapshot.source_bundle_sha256
        and r.passed is true and r.findings_count=0
    ) into v_secret_scan_ok;
    if not v_secret_scan_ok then raise exception 'pandora_staging_secret_scan_required' using errcode='55000'; end if;
  end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots
  set state=p_new_state,
      verified_at=case when p_new_state='verified' then now() else verified_at end,
      updated_at=now()
  where id=p_snapshot_id
  returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.'||p_new_state,p_expected_state,p_new_state,p_actor,coalesce(p_evidence,'{}'::jsonb));
  return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'verifiedAt',v_snapshot.verified_at);
end;
$$;

revoke all on function public.pandora_staging_record_secret_scan_v1(uuid,text,text,integer,bigint,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_staging_record_secret_scan_v1(uuid,text,text,integer,bigint,text,jsonb) to service_role;

revoke all on function pandora_staging.append_event(uuid,text,text,text,text,jsonb) from public,anon,authenticated,service_role;
revoke all on function pandora_staging.reject_snapshot_direct_mutation() from public,anon,authenticated,service_role;
revoke all on function pandora_staging.reject_event_mutation() from public,anon,authenticated,service_role;
revoke all on function pandora_staging.reject_secret_scan_receipt_mutation() from public,anon,authenticated,service_role;

comment on table pandora_staging.pandora_secret_scan_receipts is 'Append-only successful source-secret scan receipts. A snapshot cannot be sealed or enter building without a zero-finding receipt bound to the exact source bundle SHA-256.';
