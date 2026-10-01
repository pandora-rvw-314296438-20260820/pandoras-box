alter table pandora_staging.pandora_snapshots alter column build_evidence_sha256 drop not null;
alter table pandora_staging.pandora_snapshots alter column build_evidence_bytes drop not null;
alter table pandora_staging.pandora_snapshots alter column test_results_sha256 drop not null;
alter table pandora_staging.pandora_snapshots alter column test_results_bytes drop not null;

alter table pandora_staging.pandora_snapshots drop constraint if exists pandora_snapshots_build_evidence_pair_ck;
alter table pandora_staging.pandora_snapshots add constraint pandora_snapshots_build_evidence_pair_ck check ((build_evidence_sha256 is null)=(build_evidence_bytes is null));
alter table pandora_staging.pandora_snapshots drop constraint if exists pandora_snapshots_test_results_pair_ck;
alter table pandora_staging.pandora_snapshots add constraint pandora_snapshots_test_results_pair_ck check ((test_results_sha256 is null)=(test_results_bytes is null));
create unique index if not exists pandora_snapshots_source_identity_uq on pandora_staging.pandora_snapshots(project_id,source_bundle_sha256,manifest_sha256,checksums_sha256);

create or replace function public.pandora_staging_register_snapshot_v2(
  p_organization_id uuid,p_project_key text,p_source_bundle_sha256 text,p_source_bundle_bytes bigint,
  p_manifest_sha256 text,p_manifest_bytes bigint,p_checksums_sha256 text,p_checksums_bytes bigint,
  p_actor text,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_project pandora_staging.pandora_projects; v_snapshot pandora_staging.pandora_snapshots; v_created boolean:=false;
begin
  select * into v_project from pandora_staging.pandora_projects where organization_id=p_organization_id and project_key=p_project_key and active is true;
  if not found then raise exception 'pandora_staging_project_not_found' using errcode='P0002'; end if;
  if p_source_bundle_sha256 !~ '^[0-9a-f]{64}$' or p_manifest_sha256 !~ '^[0-9a-f]{64}$' or p_checksums_sha256 !~ '^[0-9a-f]{64}$'
     or p_source_bundle_bytes not between 1 and 26214400 or p_manifest_bytes not between 1 and 1048576 or p_checksums_bytes not between 1 and 1048576
     or nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'pandora_staging_snapshot_invalid' using errcode='22023'; end if;
  select * into v_snapshot from pandora_staging.pandora_snapshots where project_id=v_project.id and source_bundle_sha256=p_source_bundle_sha256 and manifest_sha256=p_manifest_sha256 and checksums_sha256=p_checksums_sha256 order by created_at desc limit 1;
  if not found then
    v_snapshot.id:=gen_random_uuid();
    insert into pandora_staging.pandora_snapshots(id,project_id,state,object_prefix,source_bundle_sha256,source_bundle_bytes,manifest_sha256,manifest_bytes,checksums_sha256,checksums_bytes,metadata,created_by)
    values(v_snapshot.id,v_project.id,'staged',p_project_key||'/'||v_snapshot.id::text,p_source_bundle_sha256,p_source_bundle_bytes,p_manifest_sha256,p_manifest_bytes,p_checksums_sha256,p_checksums_bytes,coalesce(p_metadata,'{}'::jsonb),p_actor)
    returning * into v_snapshot;
    v_created:=true;
    perform pandora_staging.append_event(v_snapshot.id,'snapshot.registered',null,'staged',p_actor,jsonb_build_object('projectKey',p_project_key,'repository',v_project.canonical_repository,'objectPrefix',v_snapshot.object_prefix,'sourceBundleSha256',p_source_bundle_sha256));
  end if;
  return jsonb_build_object('created',v_created,'snapshotId',v_snapshot.id,'state',v_snapshot.state,'sealedAt',v_snapshot.sealed_at,'objectPrefix',v_snapshot.object_prefix,'repository',v_project.canonical_repository,
    'objects',jsonb_build_object(
      'source.bundle',jsonb_build_object('path',v_snapshot.object_prefix||'/source.bundle','sha256',v_snapshot.source_bundle_sha256,'bytes',v_snapshot.source_bundle_bytes),
      'manifest.json',jsonb_build_object('path',v_snapshot.object_prefix||'/manifest.json','sha256',v_snapshot.manifest_sha256,'bytes',v_snapshot.manifest_bytes),
      'checksums.sha256',jsonb_build_object('path',v_snapshot.object_prefix||'/checksums.sha256','sha256',v_snapshot.checksums_sha256,'bytes',v_snapshot.checksums_bytes)));
end; $$;

create or replace function public.pandora_staging_attach_evidence_v1(
  p_snapshot_id uuid,p_build_evidence_sha256 text,p_build_evidence_bytes bigint,p_test_results_sha256 text,p_test_results_bytes bigint,p_actor text
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_snapshot pandora_staging.pandora_snapshots;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state<>'building' then raise exception 'pandora_staging_snapshot_not_building' using errcode='55000'; end if;
  if p_build_evidence_sha256 !~ '^[0-9a-f]{64}$' or p_test_results_sha256 !~ '^[0-9a-f]{64}$' or p_build_evidence_bytes not between 1 and 5242880 or p_test_results_bytes not between 1 and 67108864 or nullif(trim(p_actor),'') is null then raise exception 'pandora_staging_evidence_invalid' using errcode='22023'; end if;
  if v_snapshot.build_evidence_sha256 is not null or v_snapshot.test_results_sha256 is not null then
    if v_snapshot.build_evidence_sha256=p_build_evidence_sha256 and v_snapshot.build_evidence_bytes=p_build_evidence_bytes and v_snapshot.test_results_sha256=p_test_results_sha256 and v_snapshot.test_results_bytes=p_test_results_bytes then
      return jsonb_build_object('snapshotId',v_snapshot.id,'alreadyAttached',true,'objectPrefix',v_snapshot.object_prefix);
    end if;
    raise exception 'pandora_staging_evidence_already_attached' using errcode='55000';
  end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots set build_evidence_sha256=p_build_evidence_sha256,build_evidence_bytes=p_build_evidence_bytes,test_results_sha256=p_test_results_sha256,test_results_bytes=p_test_results_bytes,updated_at=now() where id=p_snapshot_id returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.evidence_attached','building','building',p_actor,jsonb_build_object('buildEvidenceSha256',p_build_evidence_sha256,'testResultsSha256',p_test_results_sha256));
  return jsonb_build_object('snapshotId',v_snapshot.id,'alreadyAttached',false,'objectPrefix',v_snapshot.object_prefix,
    'objects',jsonb_build_object(
      'build-evidence.json',jsonb_build_object('path',v_snapshot.object_prefix||'/build-evidence.json','sha256',v_snapshot.build_evidence_sha256,'bytes',v_snapshot.build_evidence_bytes),
      'test-results.tar.gz',jsonb_build_object('path',v_snapshot.object_prefix||'/test-results.tar.gz','sha256',v_snapshot.test_results_sha256,'bytes',v_snapshot.test_results_bytes)));
end; $$;

revoke all on function public.pandora_staging_register_snapshot_v2(uuid,text,text,bigint,text,bigint,text,bigint,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_staging_attach_evidence_v1(uuid,text,bigint,text,bigint,text) from public,anon,authenticated;
grant execute on function public.pandora_staging_register_snapshot_v2(uuid,text,text,bigint,text,bigint,text,bigint,text,jsonb) to service_role;
grant execute on function public.pandora_staging_attach_evidence_v1(uuid,text,bigint,text,bigint,text) to service_role;

drop function if exists public.pandora_staging_register_snapshot_v1(uuid,text,text,bigint,text,bigint,text,bigint,text,bigint,text,bigint,text,jsonb);
