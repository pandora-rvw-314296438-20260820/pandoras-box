-- Pandora final build authorization and build-status ACL closure.
-- Binds generated BuildJobs to the exact Worker C request_build@1 policy/action hash
-- and makes Worker D claim fail closed without that immutable ALLOW decision.

revoke all on function public.pandora_project_build_status_20260829(uuid) from public, anon;
grant execute on function public.pandora_project_build_status_20260829(uuid) to authenticated, service_role;

create or replace function private.pandora_authorize_generated_build_20260829(p_build_job_id uuid)
returns jsonb language plpgsql security definer
set search_path='pg_catalog','private','public','extensions' as $$
declare
  j public.pandora_build_jobs%rowtype;
  v public.pandora_project_versions%rowtype;
  a text; ah text; args_h text; tc uuid; existing public.pandora_tool_calls%rowtype;
  pv constant text:='pandora-tool-policy/1.1.0';
begin
  select * into j from public.pandora_build_jobs where id=p_build_job_id for update;
  if not found or j.job_kind<>'build' or j.status<>'queued' or j.target_project_version_id is null or j.requested_by is null or j.idempotency_key is null then
    raise exception 'BUILD_AUTHORIZATION_JOB_INVALID' using errcode='23514';
  end if;
  select * into v from public.pandora_project_versions
   where id=j.target_project_version_id and organization_id=j.organization_id and project_id=j.project_id
     and project_spec_id=j.project_spec_id and build_job_id=j.id for share;
  if not found or v.root_artifact_version_id is null or v.source_sha256 !~ '^[0-9a-f]{64}$' or v.lifecycle_status<>'draft' then
    raise exception 'BUILD_AUTHORIZATION_VERSION_INVALID' using errcode='23514';
  end if;
  if not exists(select 1 from public.memberships where organization_id=j.organization_id and user_id=j.requested_by and status='active') then
    raise exception 'BUILD_AUTHORIZATION_REQUESTER_INVALID' using errcode='42501';
  end if;

  a:='{"environment":"preview","idempotency_key":'||to_jsonb(j.idempotency_key)::text||',"project_id":'||to_jsonb(j.project_id::text)::text||',"request_id":'||to_jsonb(j.idempotency_key)::text||',"version_id":'||to_jsonb(v.id::text)::text||'}';
  args_h:=encode(extensions.digest(convert_to(a,'utf8'),'sha256'),'hex');
  a:='{"arguments":'||a||',"environment":"preview","organization_id":'||to_jsonb(j.organization_id::text)::text||',"policy_version":'||to_jsonb(pv)::text||',"project_id":'||to_jsonb(j.project_id::text)::text||',"project_version":'||to_jsonb(v.id::text)::text||',"target_resource":"BuildExecutor","tool":"request_build","version":1}';
  ah:=encode(extensions.digest(convert_to(a,'utf8'),'sha256'),'hex');

  select * into existing from public.pandora_tool_calls where organization_id=j.organization_id and (action_hash=ah or (project_id=j.project_id and idempotency_key=j.idempotency_key)) limit 1;
  if found then
    if existing.action_hash<>ah or existing.arguments_sha256<>args_h or existing.build_job_id is distinct from j.id or existing.project_version_id is distinct from v.id
       or existing.tool_name<>'request_build' or existing.tool_version<>'1' or existing.decision<>'ALLOW' or existing.status<>'authorized' then
      raise exception 'BUILD_AUTHORIZATION_COLLISION' using errcode='23505';
    end if;
    tc:=existing.id;
  else
    insert into public.pandora_tool_calls(organization_id,project_id,project_spec_id,build_job_id,project_version_id,tool_name,tool_version,action_name,environment,target_resource_ref,policy_version,action_hash,arguments_sha256,risk_level,decision,side_effect,retry_mode,idempotency_mode,idempotency_key,approval_required,status)
    values(j.organization_id,j.project_id,j.project_spec_id,j.id,v.id,'request_build','1','request_build','preview','BuildExecutor',pv,ah,args_h,'LOW','ALLOW','EXTERNAL_MUTATION','IDEMPOTENT_RETRY','REQUIRED',j.idempotency_key,false,'authorized') returning id into tc;
  end if;

  insert into public.pandora_policy_actions(organization_id,project_id,project_spec_id,build_job_id,tool_call_id,project_version_id,tool_name,tool_version,action_name,action_hash,arguments_sha256,policy_version,environment,target_resource_ref,risk_level,disposition,side_effect,approval_required,status)
  values(j.organization_id,j.project_id,j.project_spec_id,j.id,tc,v.id,'request_build','1','request_build',ah,args_h,pv,'preview','BuildExecutor','LOW','ALLOW','EXTERNAL_MUTATION',false,'authorized')
  on conflict (organization_id,action_hash) do nothing;

  if not exists(select 1 from public.pandora_policy_actions p where p.organization_id=j.organization_id and p.project_id=j.project_id and p.project_spec_id=j.project_spec_id and p.build_job_id=j.id and p.tool_call_id=tc and p.project_version_id=v.id and p.action_hash=ah and p.arguments_sha256=args_h and p.policy_version=pv and p.disposition='ALLOW' and p.status='authorized' and p.approval_required=false and (p.expires_at is null or p.expires_at>now())) then
    raise exception 'BUILD_AUTHORIZATION_POLICY_WRITE_FAILED' using errcode='55000';
  end if;
  return jsonb_build_object('buildJobId',j.id,'projectVersionId',v.id,'toolCallId',tc,'tool','request_build@1','capability','build.execute','actionHash',ah,'argumentsSha256',args_h,'decision','ALLOW','environment','preview');
end;$$;
revoke all on function private.pandora_authorize_generated_build_20260829(uuid) from public,anon,authenticated;
grant execute on function private.pandora_authorize_generated_build_20260829(uuid) to service_role;

create or replace function private.pandora_commit_generated_build_intake_v2_20260829(p_organization_id uuid,p_project_id uuid,p_project_spec_id uuid,p_requested_by uuid,p_idempotency_key text,p_source_sha256 text,p_source_byte_size bigint,p_storage_path text,p_model_run_id uuid,p_build_adapter text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare r jsonb; authz jsonb; jid uuid;
begin
  r:=private.pandora_commit_generated_build_intake_20260829(p_organization_id,p_project_id,p_project_spec_id,p_requested_by,p_idempotency_key,p_source_sha256,p_source_byte_size,p_storage_path,p_model_run_id,p_build_adapter);
  jid:=nullif(r->>'buildJobId','')::uuid;
  if jid is null then raise exception 'BUILD_AUTHORIZATION_JOB_MISSING' using errcode='55000'; end if;
  if exists(select 1 from public.pandora_build_jobs where id=jid and status='queued') then authz:=private.pandora_authorize_generated_build_20260829(jid);
  else
    select jsonb_build_object('buildJobId',t.build_job_id,'projectVersionId',t.project_version_id,'toolCallId',t.id,'tool','request_build@1','capability','build.execute','actionHash',t.action_hash,'argumentsSha256',t.arguments_sha256,'decision',t.decision,'environment',t.environment) into authz
      from public.pandora_tool_calls t where t.build_job_id=jid and t.tool_name='request_build' and t.tool_version='1' and t.decision='ALLOW' and t.status='authorized' limit 1;
    if authz is null then raise exception 'BUILD_AUTHORIZATION_REPLAY_MISSING' using errcode='55000'; end if;
  end if;
  return r||jsonb_build_object('authorization',authz);
end;$$;
revoke all on function private.pandora_commit_generated_build_intake_v2_20260829(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text) from public,anon,authenticated;
grant execute on function private.pandora_commit_generated_build_intake_v2_20260829(uuid,uuid,uuid,uuid,text,text,bigint,text,uuid,text) to service_role;

create or replace function private.pandora_claim_build_job(p_job_id uuid,p_worker_identity text,p_lease_token_sha256 text,p_lease_seconds integer default 300)
returns public.pandora_build_jobs language plpgsql security definer set search_path='' as $$
declare j public.pandora_build_jobs;
begin
  if nullif(trim(p_worker_identity),'') is null then raise exception 'worker identity is required' using errcode='22023'; end if;
  if p_lease_token_sha256 !~ '^[0-9a-f]{64}$' then raise exception 'lease token digest must be sha256' using errcode='22023'; end if;
  if p_lease_seconds<30 or p_lease_seconds>1800 then raise exception 'lease seconds out of range' using errcode='22023'; end if;
  select * into j from public.pandora_build_jobs where id=p_job_id for update;
  if not found or j.status<>'queued' or j.attempt_count>=j.max_attempts then raise exception 'build job unavailable for claim' using errcode='55000'; end if;
  if j.job_kind='build' and not exists(
    select 1 from public.pandora_tool_calls t join public.pandora_policy_actions p on p.tool_call_id=t.id and p.organization_id=t.organization_id and p.action_hash=t.action_hash
    where t.build_job_id=j.id and t.organization_id=j.organization_id and t.project_id=j.project_id and t.project_spec_id=j.project_spec_id and t.project_version_id=j.target_project_version_id
      and t.tool_name='request_build' and t.tool_version='1' and t.action_name='request_build' and t.environment='preview' and t.target_resource_ref='BuildExecutor'
      and t.policy_version='pandora-tool-policy/1.1.0' and t.risk_level='LOW' and t.decision='ALLOW' and t.side_effect='EXTERNAL_MUTATION' and t.retry_mode='IDEMPOTENT_RETRY' and t.idempotency_mode='REQUIRED'
      and t.idempotency_key=j.idempotency_key and t.approval_required=false and t.status='authorized'
      and p.project_id=j.project_id and p.project_spec_id=j.project_spec_id and p.build_job_id=j.id and p.project_version_id=j.target_project_version_id and p.arguments_sha256=t.arguments_sha256
      and p.policy_version=t.policy_version and p.environment=t.environment and p.disposition='ALLOW' and p.approval_required=false and p.status='authorized' and (p.expires_at is null or p.expires_at>now())
  ) then raise exception 'build job lacks exact Worker C authorization' using errcode='42501'; end if;
  update public.pandora_build_jobs set status='claimed',attempt_count=attempt_count+1,lease_owner=p_worker_identity,lease_token_sha256=p_lease_token_sha256,lease_expires_at=now()+make_interval(secs=>p_lease_seconds),heartbeat_at=now(),worker_identity=p_worker_identity where id=p_job_id and status='queued' returning * into j;
  if j.id is null then raise exception 'build job unavailable for claim' using errcode='55000'; end if;
  insert into public.pandora_build_job_attempts(organization_id,project_id,build_job_id,attempt_no,worker_identity,lease_token_sha256) values(j.organization_id,j.project_id,j.id,j.attempt_count,p_worker_identity,p_lease_token_sha256);
  return j;
end;$$;
revoke all on function private.pandora_claim_build_job(uuid,text,text,integer) from public,anon,authenticated;
grant execute on function private.pandora_claim_build_job(uuid,text,text,integer) to service_role;
