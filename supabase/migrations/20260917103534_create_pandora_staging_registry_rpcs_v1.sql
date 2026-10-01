create or replace function public.pandora_staging_register_snapshot_v1(
  p_organization_id uuid,p_project_key text,p_source_bundle_sha256 text,p_source_bundle_bytes bigint,
  p_manifest_sha256 text,p_manifest_bytes bigint,p_checksums_sha256 text,p_checksums_bytes bigint,
  p_build_evidence_sha256 text,p_build_evidence_bytes bigint,p_test_results_sha256 text,p_test_results_bytes bigint,
  p_actor text,p_metadata jsonb default '{}'::jsonb
) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_project pandora_staging.pandora_projects; v_snapshot pandora_staging.pandora_snapshots; v_created boolean:=false;
begin
  select * into v_project from pandora_staging.pandora_projects where organization_id=p_organization_id and project_key=p_project_key and active is true;
  if not found then raise exception 'pandora_staging_project_not_found' using errcode='P0002'; end if;
  if p_source_bundle_sha256 !~ '^[0-9a-f]{64}$' or p_manifest_sha256 !~ '^[0-9a-f]{64}$' or p_checksums_sha256 !~ '^[0-9a-f]{64}$' or p_build_evidence_sha256 !~ '^[0-9a-f]{64}$' or p_test_results_sha256 !~ '^[0-9a-f]{64}$'
     or p_source_bundle_bytes not between 1 and 26214400 or p_manifest_bytes not between 1 and 1048576 or p_checksums_bytes not between 1 and 1048576 or p_build_evidence_bytes not between 1 and 5242880 or p_test_results_bytes not between 1 and 67108864
     or nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_metadata,'{}'::jsonb))<>'object' then raise exception 'pandora_staging_snapshot_invalid' using errcode='22023'; end if;
  select * into v_snapshot from pandora_staging.pandora_snapshots where project_id=v_project.id and source_bundle_sha256=p_source_bundle_sha256 and manifest_sha256=p_manifest_sha256 and checksums_sha256=p_checksums_sha256 and build_evidence_sha256=p_build_evidence_sha256 and test_results_sha256=p_test_results_sha256 order by created_at desc limit 1;
  if not found then
    v_snapshot.id:=gen_random_uuid();
    insert into pandora_staging.pandora_snapshots(id,project_id,state,object_prefix,source_bundle_sha256,source_bundle_bytes,manifest_sha256,manifest_bytes,checksums_sha256,checksums_bytes,build_evidence_sha256,build_evidence_bytes,test_results_sha256,test_results_bytes,metadata,created_by)
    values(v_snapshot.id,v_project.id,'staged',p_project_key||'/'||v_snapshot.id::text,p_source_bundle_sha256,p_source_bundle_bytes,p_manifest_sha256,p_manifest_bytes,p_checksums_sha256,p_checksums_bytes,p_build_evidence_sha256,p_build_evidence_bytes,p_test_results_sha256,p_test_results_bytes,coalesce(p_metadata,'{}'::jsonb),p_actor)
    returning * into v_snapshot;
    v_created:=true;
    perform pandora_staging.append_event(v_snapshot.id,'snapshot.registered',null,'staged',p_actor,jsonb_build_object('projectKey',p_project_key,'repository',v_project.canonical_repository,'objectPrefix',v_snapshot.object_prefix,'sourceBundleSha256',p_source_bundle_sha256));
  end if;
  return jsonb_build_object('created',v_created,'snapshotId',v_snapshot.id,'state',v_snapshot.state,'sealedAt',v_snapshot.sealed_at,'objectPrefix',v_snapshot.object_prefix,'repository',v_project.canonical_repository,
    'objects',jsonb_build_object(
      'source.bundle',jsonb_build_object('path',v_snapshot.object_prefix||'/source.bundle','sha256',v_snapshot.source_bundle_sha256,'bytes',v_snapshot.source_bundle_bytes),
      'manifest.json',jsonb_build_object('path',v_snapshot.object_prefix||'/manifest.json','sha256',v_snapshot.manifest_sha256,'bytes',v_snapshot.manifest_bytes),
      'checksums.sha256',jsonb_build_object('path',v_snapshot.object_prefix||'/checksums.sha256','sha256',v_snapshot.checksums_sha256,'bytes',v_snapshot.checksums_bytes),
      'build-evidence.json',jsonb_build_object('path',v_snapshot.object_prefix||'/build-evidence.json','sha256',v_snapshot.build_evidence_sha256,'bytes',v_snapshot.build_evidence_bytes),
      'test-results.tar.gz',jsonb_build_object('path',v_snapshot.object_prefix||'/test-results.tar.gz','sha256',v_snapshot.test_results_sha256,'bytes',v_snapshot.test_results_bytes)));
end; $$;

create or replace function public.pandora_staging_get_snapshot_v1(p_snapshot_id uuid) returns jsonb language sql stable security definer set search_path=pg_catalog,public,pandora_staging as $$
select jsonb_build_object('snapshotId',s.id,'projectId',s.project_id,'organizationId',p.organization_id,'projectKey',p.project_key,'repository',p.canonical_repository,'state',s.state,'objectPrefix',s.object_prefix,
'sourceBundleSha256',s.source_bundle_sha256,'sourceBundleBytes',s.source_bundle_bytes,'manifestSha256',s.manifest_sha256,'manifestBytes',s.manifest_bytes,'checksumsSha256',s.checksums_sha256,'checksumsBytes',s.checksums_bytes,
'buildEvidenceSha256',s.build_evidence_sha256,'buildEvidenceBytes',s.build_evidence_bytes,'testResultsSha256',s.test_results_sha256,'testResultsBytes',s.test_results_bytes,'metadata',s.metadata,'createdBy',s.created_by,'createdAt',s.created_at,
'sealedAt',s.sealed_at,'verifiedAt',s.verified_at,'publishedAt',s.published_at,'githubBranch',s.github_branch,'githubCommitSha',s.github_commit_sha,'githubPrNumber',s.github_pr_number,'promotionReadback',s.promotion_readback)
from pandora_staging.pandora_snapshots s join pandora_staging.pandora_projects p on p.id=s.project_id where s.id=p_snapshot_id;
$$;

create or replace function public.pandora_staging_seal_snapshot_v1(p_snapshot_id uuid,p_actor text,p_evidence jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_snapshot pandora_staging.pandora_snapshots;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state<>'staged' then raise exception 'pandora_staging_snapshot_not_staged' using errcode='55000'; end if;
  if v_snapshot.sealed_at is not null then return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'sealedAt',v_snapshot.sealed_at,'alreadySealed',true); end if;
  if nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' then raise exception 'pandora_staging_seal_invalid' using errcode='22023'; end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots set sealed_at=now(),updated_at=now() where id=p_snapshot_id returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.sealed','staged','staged',p_actor,coalesce(p_evidence,'{}'::jsonb));
  return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'sealedAt',v_snapshot.sealed_at,'alreadySealed',false);
end; $$;

create or replace function public.pandora_staging_transition_snapshot_v1(p_snapshot_id uuid,p_expected_state text,p_new_state text,p_actor text,p_evidence jsonb default '{}'::jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_snapshot pandora_staging.pandora_snapshots; v_allowed boolean:=false;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state<>p_expected_state then raise exception 'pandora_staging_state_moved' using errcode='40001'; end if;
  if nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_evidence,'{}'::jsonb))<>'object' then raise exception 'pandora_staging_transition_invalid' using errcode='22023'; end if;
  v_allowed:=(p_expected_state='staged' and p_new_state in ('building','rejected')) or (p_expected_state='building' and p_new_state in ('verified','rejected')) or (p_expected_state='verified' and p_new_state='rejected');
  if not v_allowed then raise exception 'pandora_staging_transition_not_allowed' using errcode='22023'; end if;
  if p_new_state='building' and v_snapshot.sealed_at is null then raise exception 'pandora_staging_snapshot_not_sealed' using errcode='55000'; end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots set state=p_new_state,verified_at=case when p_new_state='verified' then now() else verified_at end,updated_at=now() where id=p_snapshot_id returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.'||p_new_state,p_expected_state,p_new_state,p_actor,coalesce(p_evidence,'{}'::jsonb));
  return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'verifiedAt',v_snapshot.verified_at);
end; $$;

create or replace function public.pandora_staging_record_github_promotion_v1(p_snapshot_id uuid,p_branch text,p_commit_sha text,p_pr_number integer,p_actor text,p_readback jsonb) returns jsonb language plpgsql security definer set search_path=pg_catalog,public,pandora_staging as $$
declare v_snapshot pandora_staging.pandora_snapshots;
begin
  select * into v_snapshot from pandora_staging.pandora_snapshots where id=p_snapshot_id for update;
  if not found then raise exception 'pandora_staging_snapshot_not_found' using errcode='P0002'; end if;
  if v_snapshot.state='published' then
    if v_snapshot.github_branch=p_branch and v_snapshot.github_commit_sha=p_commit_sha and v_snapshot.github_pr_number=p_pr_number then return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'alreadyPublished',true,'branch',v_snapshot.github_branch,'commitSha',v_snapshot.github_commit_sha,'prNumber',v_snapshot.github_pr_number); end if;
    raise exception 'pandora_staging_snapshot_already_published' using errcode='55000';
  end if;
  if v_snapshot.state<>'verified' then raise exception 'pandora_staging_snapshot_not_verified' using errcode='55000'; end if;
  if p_branch !~ '^pandora/staging-[a-z0-9-]{8,64}$' or p_commit_sha !~ '^[0-9a-f]{40}$' or p_pr_number is null or p_pr_number<=0 or nullif(trim(p_actor),'') is null or jsonb_typeof(coalesce(p_readback,'{}'::jsonb))<>'object' then raise exception 'pandora_staging_promotion_invalid' using errcode='22023'; end if;
  perform set_config('pandora_staging.allow_snapshot_mutation','on',true);
  update pandora_staging.pandora_snapshots set state='published',published_at=now(),updated_at=now(),github_branch=p_branch,github_commit_sha=p_commit_sha,github_pr_number=p_pr_number,promotion_readback=coalesce(p_readback,'{}'::jsonb) where id=p_snapshot_id returning * into v_snapshot;
  perform pandora_staging.append_event(v_snapshot.id,'snapshot.published','verified','published',p_actor,jsonb_build_object('branch',p_branch,'commitSha',p_commit_sha,'prNumber',p_pr_number,'readback',coalesce(p_readback,'{}'::jsonb)));
  return jsonb_build_object('snapshotId',v_snapshot.id,'state',v_snapshot.state,'alreadyPublished',false,'branch',v_snapshot.github_branch,'commitSha',v_snapshot.github_commit_sha,'prNumber',v_snapshot.github_pr_number);
end; $$;

revoke all on function public.pandora_staging_register_snapshot_v1(uuid,text,text,bigint,text,bigint,text,bigint,text,bigint,text,bigint,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_staging_get_snapshot_v1(uuid) from public,anon,authenticated;
revoke all on function public.pandora_staging_seal_snapshot_v1(uuid,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_staging_transition_snapshot_v1(uuid,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_staging_record_github_promotion_v1(uuid,text,text,integer,text,jsonb) from public,anon,authenticated;
grant execute on function public.pandora_staging_register_snapshot_v1(uuid,text,text,bigint,text,bigint,text,bigint,text,bigint,text,bigint,text,jsonb) to service_role;
grant execute on function public.pandora_staging_get_snapshot_v1(uuid) to service_role;
grant execute on function public.pandora_staging_seal_snapshot_v1(uuid,text,jsonb) to service_role;
grant execute on function public.pandora_staging_transition_snapshot_v1(uuid,text,text,text,jsonb) to service_role;
grant execute on function public.pandora_staging_record_github_promotion_v1(uuid,text,text,integer,text,jsonb) to service_role;
