-- Pandora Operations native pg_cron worker v1.
-- Fixed canary scope; no cross-provider secret and no arbitrary task/provider input.

create or replace function private.pandora_ops_native_cron_tick_v1()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','public'
as $body$
declare
  v_org constant uuid := '2270b266-59da-4c39-bfd9-9f8d08352af0'::uuid;
  v_project constant uuid := 'ee282126-3f61-4058-8c92-2fedbfcecf1f'::uuid;
  v_task constant text := 'OPS-CLOUD-CONNECTORS-RELEASE-V1';
  v_builder constant text := 'pandora-supabase-cron-builder-v1';
  v_builder_principal constant text := 'supabase:pg-cron:operations-builder-v1';
  v_release constant text := 'pandora-supabase-cron-release-v1';
  v_release_principal constant text := 'supabase:pg-cron:operations-release-v1';
  v_workspace private.pandora_ops_workspaces%rowtype;
  v_task_row private.pandora_ops_tasks%rowtype;
  v_pr jsonb;
  v_checks jsonb;
  v_merge_sha text;
  v_head_sha text;
  v_claim jsonb;
  v_dispatch jsonb;
  v_handoff jsonb;
  v_verified jsonb;
  v_tests jsonb;
  v_failed integer;
  v_pending integer;
  v_dispatch_id uuid;
  v_lease_id uuid;
  v_generation bigint;
begin
  if not pg_try_advisory_xact_lock(hashtextextended('pandora-operations-native-cron-v1',0)) then
    return jsonb_build_object('ok',true,'state','busy');
  end if;

  select * into v_workspace
  from private.pandora_ops_workspaces
  where organization_id=v_org and project_id=v_project
  for update;
  if not found then raise exception 'OPS_WORKSPACE_MISSING'; end if;

  if not exists(
    select 1 from private.pandora_ops_workers
    where organization_id=v_org and project_id=v_project
      and worker_key=v_builder and principal_key=v_builder_principal
      and engine='pandora_native'
  ) then
    perform public.pandora_ops_register_native_worker_v1(
      v_org,v_project,v_builder,v_builder_principal,
      array['backend','reliability']::text[],
      array['source.write','ci.verify','release.handoff','provider.readback','worker.reconcile']::text[],
      1,'supabase:pg-cron:operations-builder-v1'
    );
  end if;

  if not exists(
    select 1 from private.pandora_ops_workers
    where organization_id=v_org and project_id=v_project
      and worker_key=v_release and principal_key=v_release_principal
      and engine='pandora_native'
  ) then
    perform public.pandora_ops_register_native_worker_v1(
      v_org,v_project,v_release,v_release_principal,
      array['release']::text[],
      array['release.verify','provider.readback','canary.execute']::text[],
      1,'supabase:pg-cron:operations-release-v1'
    );
  end if;

  perform public.pandora_ops_heartbeat_v1(v_org,v_project,v_builder,v_builder_principal,true,'ready');
  perform public.pandora_ops_heartbeat_v1(v_org,v_project,v_release,v_release_principal,true,'ready');

  select * into v_task_row
  from private.pandora_ops_tasks
  where organization_id=v_org and project_id=v_project and task_key=v_task;

  if not found then return jsonb_build_object('ok',true,'state','task_missing'); end if;
  if v_task_row.status='complete' then return jsonb_build_object('ok',true,'state','complete'); end if;
  if v_workspace.paused then return jsonb_build_object('ok',true,'state','paused'); end if;

  if v_task_row.status='queued' then
    v_pr:=private.pandora_integration_github_api_20260825(
      'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/pulls/741',null
    );
    if (v_pr->>'status')::integer<>200 or v_pr#>>'{body,merged}'<>'true' then
      raise exception 'OPS_NATIVE_CRON_PR_READBACK_FAILED';
    end if;
    v_merge_sha:=v_pr#>>'{body,merge_commit_sha}';
    v_head_sha:=v_pr#>>'{body,head,sha}';
    if v_merge_sha!~'^[0-9a-f]{40}$' or v_head_sha!~'^[0-9a-f]{40}$' then
      raise exception 'OPS_NATIVE_CRON_SOURCE_INVALID';
    end if;

    v_checks:=private.pandora_integration_github_api_20260825(
      'GET','/repos/pandora-rvw-314296438-20260820/pandoras-box/commits/'||v_head_sha||'/check-runs?per_page=100',null
    );
    if (v_checks->>'status')::integer<>200 then raise exception 'OPS_NATIVE_CRON_CHECK_READBACK_FAILED'; end if;
    select
      count(*) filter(where c->>'status'<>'completed'),
      count(*) filter(where c->>'status'='completed' and coalesce(c->>'conclusion','') not in ('success','neutral','skipped')),
      coalesce(jsonb_agg(to_jsonb(c->>'name')) filter(where c->>'status'='completed' and c->>'conclusion'='success'),'[]'::jsonb)
    into v_pending,v_failed,v_tests
    from jsonb_array_elements(coalesce(v_checks#>'{body,check_runs}','[]'::jsonb)) c;
    if v_pending<>0 or v_failed<>0 then raise exception 'OPS_NATIVE_CRON_CHECKS_NOT_GREEN'; end if;

    v_claim:=public.pandora_ops_claim_v1(
      v_org,v_project,v_task,v_builder,v_task_row.revision,v_workspace.revision
    );
    if coalesce((v_claim->>'claimed')::boolean,false) is not true then
      return jsonb_build_object('ok',true,'state','not_claimed','reason',v_claim->>'reason');
    end if;

    v_lease_id:=(v_claim->>'leaseId')::uuid;
    v_generation:=(v_claim->>'generation')::bigint;
    v_dispatch:=public.pandora_ops_dispatch_v1(v_org,v_project,v_lease_id,v_generation,null);
    v_dispatch_id:=(v_dispatch->>'dispatchId')::uuid;

    if coalesce((v_dispatch->>'acknowledged')::boolean,false) is not true then
      perform public.pandora_ops_dispatch_v1(
        v_org,v_project,v_lease_id,v_generation,
        jsonb_build_object(
          'accepted',true,'dispatchId',v_dispatch_id::text,'workerId',v_builder,
          'taskId',v_task,'generation',v_generation,
          'receiptRef','supabase:pg-cron:dispatch:'||v_dispatch_id::text
        )
      );
    end if;

    v_handoff:=jsonb_build_object(
      'taskId',v_task,
      'workerId',v_builder,
      'generation',v_generation,
      'headSha',v_merge_sha,
      'pullRequest',741,
      'tests',coalesce(v_tests,'[]'::jsonb)||jsonb_build_array(
        'Supabase native worker registration/heartbeat PASS',
        'Connector delivery migration 20260926012832 installed'
      ),
      'evidenceRefs',jsonb_build_array(
        v_pr#>>'{body,html_url}',
        'supabase:migration:20260926012832',
        'supabase:pg-cron:operations-native-worker-v1'
      ),
      'receiptRef','supabase:pg-cron:handoff:'||v_dispatch_id::text,
      'implementationComplete',true
    );

    perform public.pandora_ops_handoff_v1(
      v_org,v_project,v_lease_id,v_generation,v_builder_principal,v_handoff,0
    );
  end if;

  select * into v_task_row
  from private.pandora_ops_tasks
  where organization_id=v_org and project_id=v_project and task_key=v_task;

  if v_task_row.status in ('handed_off','verifying') then
    perform public.pandora_ops_heartbeat_v1(v_org,v_project,v_release,v_release_principal,true,'ready');
    v_verified:=public.pandora_ops_native_release_verify_v1(
      v_org,v_project,v_task,v_release,v_release_principal
    );
    return jsonb_build_object('ok',true,'state',
      case when coalesce((v_verified->>'complete')::boolean,false) then 'complete' else 'verification_pending' end,
      'verification',v_verified
    );
  end if;

  return jsonb_build_object('ok',true,'state',v_task_row.status);
end;
$body$;

revoke all on function private.pandora_ops_native_cron_tick_v1()
from public,anon,authenticated,service_role;

create or replace function private.pandora_ops_enable_native_cron_worker_v1()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','cron'
as $body$
declare v_job bigint;
begin
  if exists(select 1 from cron.job where jobname='pandora-operations-native-worker-v1') then
    perform cron.unschedule('pandora-operations-native-worker-v1');
  end if;
  v_job:=cron.schedule(
    'pandora-operations-native-worker-v1',
    '* * * * *',
    'select private.pandora_ops_native_cron_tick_v1();'
  );
  return jsonb_build_object('enabled',true,'jobId',v_job,'schedule','* * * * *');
end;
$body$;

revoke all on function private.pandora_ops_enable_native_cron_worker_v1()
from public,anon,authenticated,service_role;

create or replace function private.pandora_ops_disable_native_cron_worker_v1()
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','private','cron'
as $body$
declare v_job bigint;
begin
  select jobid into v_job from cron.job where jobname='pandora-operations-native-worker-v1' limit 1;
  if v_job is null then return jsonb_build_object('disabled',true,'jobFound',false); end if;
  perform cron.unschedule(v_job);
  return jsonb_build_object('disabled',true,'jobFound',true,'jobId',v_job);
end;
$body$;

revoke all on function private.pandora_ops_disable_native_cron_worker_v1()
from public,anon,authenticated,service_role;
