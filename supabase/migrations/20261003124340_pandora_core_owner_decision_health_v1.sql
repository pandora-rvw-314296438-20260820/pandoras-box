-- Owner decisions are distinct from provider verification. No provider probes,
-- credentials, account activations, approvals or historical evidence are changed.
begin;

create function private.pandora_connection_assessment_v1(p_connection_id uuid)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare
 a private.pandora_connection_accounts_v1%rowtype;
 c private.pandora_connection_manifest_contracts_v1%rowtype;
 v_public boolean:=false;v_readback boolean:=false;v_selected boolean:=false;
 v_reason text;v_health text;v_owner boolean:=false;v_max_age integer;
begin
 select * into a from private.pandora_connection_accounts_v1 where id=p_connection_id;
 if not found then return jsonb_build_object('health','unknown','owner_action_required',false,'readback_verified',false,'selected',false);end if;
 select * into c from private.pandora_connection_manifest_contracts_v1 where provider_key=a.provider_key and manifest_version=a.manifest_version;
 -- This is the existing governed public-safe-read adapter's exact allowlist.
 -- Account metadata alone cannot exempt a credentialed manifest from rotation.
 v_public:=coalesce(c.credential_policy->>'credentialMode'='none'
  and c.auth->>'credentialMode'='none' and c.auth->>'type'='service_credential'
  and a.provider_key in ('ph.psa.openstat','ph.phivolcs.hazard_gis','ph.namria.geoportal'),false);
 v_max_age:=case when c.health->>'maxAgeSeconds' ~ '^[0-9]{1,7}$'
  then greatest(1,least((c.health->>'maxAgeSeconds')::integer,86400)) else 900 end;
 v_selected:=exists(select 1 from private.pandora_connection_active_accounts_v1 s
  where s.organization_id=a.organization_id and s.provider_key=a.provider_key
   and s.connection_id=a.id and s.tenant_key=a.tenant_key);
 v_readback:=coalesce(a.provider_readback_hash ~ '^[0-9a-f]{64}$' and
  case when v_public then
   a.metadata_redacted->>'connectionMode'='public_safe_read'
   and a.metadata_redacted->>'credentialMode'='none'
   and a.metadata_redacted->'httpStatus'='200'::jsonb
   and a.metadata_redacted->>'bodySha256' ~ '^[0-9a-f]{64}$'
   and length(trim(a.metadata_redacted->>'providerIdentity')) between 1 and 320
   and a.account_subject_hash=encode(extensions.digest(convert_to(a.provider_key||':'||trim(a.metadata_redacted->>'providerIdentity'),'UTF8'),'sha256'),'hex')
  else a.metadata_redacted->>'verifiedBy'='provider_readback'
   and a.metadata_redacted->>'probe'=c.health->>'probe'
   and a.metadata_redacted->'identityVerified'='true'::jsonb end,false);
 v_reason:=case
  when a.revoked_at is not null or a.status='revoked' then 'CREDENTIAL_REVOKED'
  when c.provider_key is null or (c.credential_policy->>'credentialMode'='none' and not v_public) then 'PROVIDER_READBACK_UNVERIFIED'
  when not v_public and a.credential_expires_at<=now() then 'CREDENTIAL_EXPIRED'
  when not v_public and (a.rotation_due_at is null or a.rotation_due_at<=now()) then 'CREDENTIAL_ROTATION_DUE'
  when cardinality(private.pandora_connection_required_scopes_v1(a.provider_key))=0
   or array_position(a.granted_scopes,null) is not null
   or not (private.pandora_connection_required_scopes_v1(a.provider_key)<@a.granted_scopes
    and a.granted_scopes<@private.pandora_connection_required_scopes_v1(a.provider_key)) then 'REQUIRED_SCOPES_MISSING'
  when cardinality(private.pandora_connection_required_capabilities_v1(a.provider_key))=0
   or array_position(a.granted_capabilities,null) is not null
   or not (private.pandora_connection_required_capabilities_v1(a.provider_key)<@a.granted_capabilities
    and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(a.provider_key)) then 'REQUIRED_CAPABILITIES_MISSING'
  when not v_readback then 'PROVIDER_READBACK_UNVERIFIED'
  when a.last_verified_at is null or a.last_verified_at>now()+interval '1 minute'
   or a.last_verified_at<now()-make_interval(secs=>v_max_age) then 'PROVIDER_READBACK_STALE'
  when exists(select 1 from public.pandora_connection_verification_observations_v1 o
   where o.organization_id=a.organization_id and o.provider_key=a.provider_key
    and o.observed_at>=a.last_verified_at and o.state<>'verified') then 'PROVIDER_READBACK_UNVERIFIED'
  -- Public adapters retain their governed Vault marker; no secret is read here.
  when not exists(select 1 from vault.secrets s where s.id=a.credential_secret_id) then
   case when v_public then 'PROVIDER_READBACK_UNVERIFIED' else 'CREDENTIAL_UNAVAILABLE' end
  when a.status<>'connected' or a.health_state<>'healthy' then
   case when v_public and a.failure_code='CREDENTIAL_ROTATION_DUE' then 'PROVIDER_READBACK_UNVERIFIED'
    else coalesce(nullif(a.failure_code,''),'PROVIDER_HEALTH_FAILED') end
  else null end;
 v_health:=case when v_reason is null then 'healthy' when v_reason='CREDENTIAL_REVOKED' then 'revoked'
  when v_reason='PROVIDER_READBACK_STALE' then 'stale'
  when v_reason='PROVIDER_READBACK_UNVERIFIED' then 'verification_required' else 'unhealthy' end;
 v_owner:=v_selected and a.revoked_at is null and a.status<>'revoked'
  and coalesce(c.credential_policy->>'credentialMode','required')<>'none'
  and v_reason in ('CREDENTIAL_EXPIRED','CREDENTIAL_ROTATION_DUE','CREDENTIAL_UNAVAILABLE',
   'REQUIRED_SCOPES_MISSING','REQUIRED_CAPABILITIES_MISSING','GOOGLE_SCOPE_OVERPRIVILEGED');
 return jsonb_build_object('health',v_health,'failure_code',v_reason,
  'owner_action_required',coalesce(v_owner,false),'readback_verified',v_readback and v_reason is null,
  'selected',v_selected,'public_safe_read',v_public);
end;
$$;
revoke all on function private.pandora_connection_assessment_v1(uuid) from public,anon,authenticated,service_role;

-- Refuse to patch a provider body other than the exact inspected implementation.
do $fence$
declare v record;
begin
 for v in select * from (values
  ('private.pandora_core_connections_v1(uuid)','67122e1a886ea80acad1540db33a1eb019f3db163a39a533d28aec3cd3e11ffc'),
  ('private.pandora_connection_reconcile_health_v1()','77edcef4e95f1ac01fe7f4fb6bf09e0485a5a2abf1a34a88aa3fc567e0bbfcf6'),
  ('public.pandora_live_connections_v1(uuid)','c1015337d57b16f02f7b715b0f7b70f401eca129b978a23fda26070ecdf1760c'),
  ('public.pandora_core_snapshot_v1(text,uuid)','12969bb63c92fcc875ed08d41c846e3c9419fc169fb36f330210ebd025ef34e6'),
  ('private.pandora_core_usage_v1(uuid)','2d0657c82ecdea0f345a6a51eabd88fdc7a869f1b5e069b27e2e6566587228c5'),
  ('public.pandora_bedrock_chat_routing_config_v1()','0b491258b1ff236dd0738d28d5a1986d9ba9da9ab0e39890f1ef1754cf0cc4e7')
 ) x(signature,body_sha256) loop
  if not exists(select 1 from pg_proc p where p.oid=to_regprocedure(v.signature)
   and encode(extensions.digest(p.prosrc,'sha256'),'hex')=v.body_sha256) then
   raise exception 'OWNER_DECISION_SOURCE_DRIFT: %',v.signature;
  end if;
 end loop;
end;
$fence$;

-- Read-only owner projection of the actual current chat routing catalog.
-- It mirrors the hash-fenced service config predicate, never returns targets,
-- never calls that service-only RPC as an owner, and never probes or changes routing.
create function private.pandora_core_models_v1()
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare v_result jsonb;
begin
 if private.pandora_core_role_v1(null) is null
  or private.pandora_core_role_v1(null) not in ('owner','operator') then
  return jsonb_build_object('models','[]'::jsonb,'model_routing',null);
 end if;
 with models as materialized (
  select c.model_id,c.model_name,c.provider_name,c.region,c.observed_at,c.runtime_tested_at,
   c.runtime_verification_status,c.lifecycle_status,c.routable,
   (c.routable=true and c.conversational=true and c.present_in_latest_sync=true
    and c.runtime_verification_status='passed' and c.lifecycle_status='ACTIVE'
    and nullif(c.invocation_target,'') is not null) eligible,
   case when c.runtime_tested_at is null or c.runtime_tested_at>now()+interval '1 minute' then 'unknown'
    when c.runtime_tested_at<now()-interval '24 hours' then 'stale' else 'fresh' end runtime_evidence_state,
   case when c.lifecycle_status<>'ACTIVE' then 'model_not_active'
    when c.runtime_verification_status='failed' then 'runtime_verification_failed'
    when c.runtime_verification_status<>'passed' then 'runtime_not_verified'
    when not c.routable then 'not_routable'
    when nullif(c.invocation_target,'') is null then 'invocation_unavailable'
    else 'eligible_by_current_routing_policy' end availability_reason
  from private.pandora_bedrock_reasoning_catalog c
  where c.conversational=true and c.present_in_latest_sync=true
 )
 select jsonb_build_object(
  'model_routing',jsonb_build_object('mode','Auto','provider','bedrock',
   'policy_version','bedrock-live-catalog-chat-v1',
   'enabled',exists(select 1 from models where eligible),
   'routing_eligible',exists(select 1 from models where eligible),'fallback_enabled',true,
   'configured_eligible_models',(select count(*) from models where eligible),
   'verified_eligible_models',(select count(*) from models where eligible and runtime_tested_at is not null and runtime_tested_at<=now()+interval '1 minute'),
   'fresh_verified_eligible_models',(select count(*) from models where eligible and runtime_evidence_state='fresh'),
   'conversational_models',(select count(*) from models),
   'models_returned',(select least(count(*),200) from models),
   'policy_observed_at',now(),'policy_updated_at',null,
   'catalog_observed_at',(select max(observed_at) from models),
   'coverage','Current Bedrock chat routing policy and recorded runtime evidence; freshness does not alter configured routing'),
  'models',coalesce((select jsonb_agg(to_jsonb(q) order by q.configured_eligible desc,q.provider_name,q.name,q.model_id) from (
   select 'bedrock'::text provider,provider_name,model_id,model_name name,model_id model,region,
    case when eligible then 'eligible' when runtime_verification_status='failed' then 'rejected' else 'unavailable' end state,
    eligible configured_eligible,runtime_verification_status verification_state,
    runtime_tested_at,case when runtime_verification_status='passed' then runtime_tested_at else null end runtime_verified_at,
    runtime_evidence_state,availability_reason,
    observed_at catalog_observed_at
   from models order by eligible desc,provider_name,model_name,model_id limit 200
  ) q),'[]'::jsonb)) into v_result;
 return v_result;
end;
$$;
revoke all on function private.pandora_core_models_v1() from public,anon,authenticated,service_role;

create or replace function private.pandora_core_connections_v1(p_organization_id uuid default null)
returns jsonb language sql stable security definer set search_path='' as $$
 select coalesce(jsonb_agg(x order by x->>'client_name',x->>'provider'),'[]') from (
 select jsonb_build_object('id',c.id,'organization_id',c.organization_id,
  'client_name',case when c.organization_id=config.platform_organization_id then 'Pandora' else o.name end,
  'provider',c.provider_key,'provider_display_name',coalesce(m.display_name,c.provider_key),
  'name',c.account_label,'status',c.status,'health',assessment->>'health',
  'owner_action_required',assessment->'owner_action_required','selected',assessment->'selected',
  'last_verified_at',c.last_verified_at,'failure_code',assessment->>'failure_code',
  'capabilities',c.granted_capabilities,'scopes',c.granted_scopes,
  'verification_source','connection_broker','evidence_hash',c.provider_readback_hash) x
 from private.pandora_connection_accounts_v1 c join public.organizations o on o.id=c.organization_id
 cross join private.pandora_core_config config
 left join public.pandora_provider_manifests m on m.provider_key=c.provider_key and m.manifest_version=c.manifest_version
 cross join lateral (select private.pandora_connection_assessment_v1(c.id) assessment) checked
 where config.singleton and (p_organization_id is null or c.organization_id=p_organization_id)
 and private.pandora_core_role_v1(c.organization_id) is not null
 order by c.updated_at desc limit 200
 ) q;
$$;

create or replace function private.pandora_connection_reconcile_health_v1()
returns jsonb language plpgsql security definer
set search_path='pg_catalog','public','private','vault','extensions','pg_temp' as $$
declare v_row record;v_assessment jsonb;v_count integer:=0;
begin
 if current_user not in ('service_role','postgres','supabase_admin')
  and coalesce(auth.jwt()->>'role','')<>'service_role' then
  raise exception 'pandora_connection_service_role_required' using errcode='42501';
 end if;
 for v_row in
   -- Lock before assessment; do not overwrite a concurrently refreshed receipt
   -- using a stale assessment from an earlier materialized statement snapshot.
   select a.*
   from private.pandora_connection_accounts_v1 a
   where a.revoked_at is null and (a.status='connected'
    or (a.status='needs_attention' and a.failure_code='CREDENTIAL_ROTATION_DUE'
     and exists(select 1 from private.pandora_connection_manifest_contracts_v1 c
      where c.provider_key=a.provider_key and c.manifest_version=a.manifest_version
       and c.credential_policy->>'credentialMode'='none')))
   order by a.id for update of a skip locked
 loop
  v_assessment:=private.pandora_connection_assessment_v1(v_row.id);
  if v_assessment->>'failure_code' is null or (v_row.status,v_row.health_state,v_row.failure_code)
   is not distinct from ('needs_attention','unhealthy',v_assessment->>'failure_code') then continue;end if;
  update private.pandora_connection_accounts_v1 set status='needs_attention',health_state='unhealthy',
   failure_code=v_assessment->>'failure_code',updated_at=clock_timestamp() where id=v_row.id;
  v_count:=v_count+1;
  perform private.append_audit_event(v_row.organization_id,null,null,'provider'::public.audit_actor_type,null,
   'connection.health_needs_attention',jsonb_build_object('provider',v_row.provider_key,
    'connection_id',v_row.id,'tenant_key',v_row.tenant_key,'failure_code',v_assessment->>'failure_code'));
 end loop;
 return jsonb_build_object('ok',true,'reconciled',v_count,'observedAt',clock_timestamp());
end;
$$;

do $patch$
declare v_definition text;v_old text;v_new text;
begin
 select pg_get_functiondef('public.pandora_live_connections_v1(uuid)'::regprocedure) into v_definition;
 v_old:=$old$      'state',case
        when a.id is null then 'Needs authorization'
        when a.revoked_at is not null or a.status='revoked' then 'Needs attention'
        when a.credential_expires_at is not null and a.credential_expires_at<=clock_timestamp() then 'Needs attention'
        when a.rotation_due_at is null or a.rotation_due_at<=clock_timestamp() then 'Needs attention'
        when a.health_state<>'healthy' then 'Needs attention'
        when a.last_verified_at is null
          or a.last_verified_at>clock_timestamp()+interval '1 minute'
          or a.last_verified_at<clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
          then 'Needs attention'
        when not (
          private.pandora_connection_required_scopes_v1(c.provider_key)<@a.granted_scopes
          and a.granted_scopes<@private.pandora_connection_required_scopes_v1(c.provider_key)
        ) then 'Needs attention'
        when not (
          private.pandora_connection_required_capabilities_v1(c.provider_key)<@a.granted_capabilities
          and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(c.provider_key)
        ) then 'Needs attention'
        when a.provider_readback_hash is null
          or a.metadata_redacted->>'verifiedBy'<>'provider_readback'
          or a.metadata_redacted->>'probe'<>c.health->>'probe'
          or coalesce((a.metadata_redacted->>'identityVerified')::boolean,false) is not true
          then 'Needs attention'
        when not exists(select 1 from vault.secrets s where s.id=a.credential_secret_id) then 'Needs attention'
        else 'Connected'
      end,
      'connected',coalesce(
        a.id is not null
        and a.revoked_at is null
        and a.status='connected'
        and a.health_state='healthy'
        and (a.credential_expires_at is null or a.credential_expires_at>clock_timestamp())
        and a.rotation_due_at>clock_timestamp()
        and a.last_verified_at between
          clock_timestamp()-make_interval(secs=>coalesce((c.health->>'maxAgeSeconds')::int,900))
          and clock_timestamp()+interval '1 minute'
        and private.pandora_connection_required_scopes_v1(c.provider_key)<@a.granted_scopes
        and a.granted_scopes<@private.pandora_connection_required_scopes_v1(c.provider_key)
        and private.pandora_connection_required_capabilities_v1(c.provider_key)<@a.granted_capabilities
        and a.granted_capabilities<@private.pandora_connection_required_capabilities_v1(c.provider_key)
        and cardinality(private.pandora_connection_required_capabilities_v1(c.provider_key))>0
        and a.provider_readback_hash is not null
        and a.metadata_redacted->>'verifiedBy'='provider_readback'
        and a.metadata_redacted->>'probe'=c.health->>'probe'
        and coalesce((a.metadata_redacted->>'identityVerified')::boolean,false)
        and exists(select 1 from vault.secrets s where s.id=a.credential_secret_id),
        false
      ),
$old$;
 v_new:=$new$      'state',case when a.id is null then 'Not connected'
        when assessment->>'health'='healthy' then 'Connected'
        when assessment->>'health'='revoked' then 'Revoked'
        when assessment->'owner_action_required'='true'::jsonb then 'Needs authorization'
        else 'Needs verification' end,
      'connected',coalesce(assessment->>'health'='healthy',false),
      'ownerActionRequired',coalesce(assessment->'owner_action_required','false'::jsonb),
      'verificationState',assessment->>'health',
$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_DECISION_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$        'providerReadbackVerified',
          a.provider_readback_hash is not null
          and a.metadata_redacted->>'verifiedBy'='provider_readback'
          and a.metadata_redacted->>'probe'=c.health->>'probe'
          and coalesce((a.metadata_redacted->>'identityVerified')::boolean,false)$old$;
 v_new:=$new$        'providerReadbackVerified',coalesce(assessment->'readback_verified','false'::jsonb)$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_DECISION_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$'health',a.health_state,
        'failureCode',a.failure_code,$old$;
 v_new:=$new$'health',assessment->>'health',
        'failureCode',assessment->>'failure_code',$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_DECISION_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$    where m.lifecycle_state='active'$old$;
 v_new:=$new$    cross join lateral (select private.pandora_connection_assessment_v1(a.id) assessment) checked
    where m.lifecycle_state='active'$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_DECISION_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 execute v_definition;
end;
$patch$;

do $patch$
declare v_definition text;v_old text;v_new text;
begin
 select pg_get_functiondef('public.pandora_core_snapshot_v1(text,uuid)'::regprocedure) into v_definition;
 v_old:=$old$  union all select jsonb_build_object('id','connection:'||(c->>'id'),'kind','connection','organization_id',c->>'organization_id','client_name',c->>'client_name','title',(c->>'provider')||' needs attention','why','The current connection cannot be verified as usable','risk','medium','action','open_connections','evidence',c->>'evidence_hash') from jsonb_array_elements(v_connections) c where c->>'status'='needs_attention'$old$;
 v_new:=$new$  union all select jsonb_build_object('id','connection:'||(c->>'id'),'kind','connection',
   'organization_id',c->>'organization_id','client_name',c->>'client_name',
   'title',coalesce(c->>'provider_display_name',c->>'provider')||' authorization required',
   'why','Reconnect or review the access required by this connection','risk','medium',
   'action','open_connections','evidence',c->>'evidence_hash')
  from jsonb_array_elements(v_connections) c where c->'owner_action_required'='true'::jsonb$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_DECISION_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$  union all select jsonb_build_object('id','gate:'||g.task_key||':'||g.gate_kind,'kind','operations_gate','organization_id',g.organization_id,'title',initcap(replace(g.gate_kind,'_',' ')),'why','Operations Room is waiting for a human decision','risk','medium','action','open_operations','evidence',g.evidence_ref)
  from private.pandora_ops_human_gates g where g.state='blocked' and g.updated_at>now()-interval '7 days' and (p_organization_id is null or g.organization_id=p_organization_id) and private.pandora_core_role_v1(g.organization_id) is not null$old$;
 v_new:=$new$  -- Legacy Operations gates have no current owner-decision operation. They remain
  -- in Operations task history, not in the canonical actionable decision queue.
$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_DECISION_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$jsonb_agg(x order by x->>'deadline' nulls last)$old$;
 v_new:=$new$jsonb_agg(x||jsonb_build_object('state','needs_decision','needs_decision',true) order by x->>'deadline' nulls last)$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_DECISION_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$'client_name',o.name$old$;
 v_new:=$new$'client_name',case when o.id=v_platform then 'Pandora' else o.name end$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_DECISION_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 v_old:=$old$   'models',coalesce((select jsonb_agg(to_jsonb(q)) from (
    select m.organization_id,m.provider_key provider,m.capability_key capability,m.region,m.verified_success_count success_count,m.verified_failure_count failure_count,m.p95_latency_ms,m.observed_at,
     case when m.observed_at<now()-interval '24 hours' then 'stale' else 'measured' end evidence_state
    from public.pandora_provider_capability_metrics m where (p_organization_id is null or m.organization_id=p_organization_id) and private.pandora_core_role_v1(m.organization_id) is not null order by m.observed_at desc limit 50
   ) q),'[]'::jsonb),
$old$;
 v_new:=$new$   'model_routing',case when p_organization_id is null then private.pandora_core_models_v1()->'model_routing' else null end,
   'models',case when p_organization_id is null then private.pandora_core_models_v1()->'models' else '[]'::jsonb end,
$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_MODELS_PATCH_NOT_FOUND';end if;
 v_definition:=replace(v_definition,v_old,v_new);
 execute v_definition;
end;
$patch$;


do $patch$
declare v_definition text;v_old text;v_new text;
begin
 select pg_get_functiondef('private.pandora_core_usage_v1(uuid)'::regprocedure) into v_definition;
 v_old:=$old$select r.organization_id,o.name client_name,r.provider provider,r.model model,$old$;
 v_new:=$new$select r.organization_id,case when r.organization_id=(select platform_organization_id from private.pandora_core_config where singleton) then 'Pandora' else o.name end client_name,r.provider provider,r.model model,$new$;
 if strpos(v_definition,v_old)=0 then raise exception 'OWNER_USAGE_PATCH_NOT_FOUND';end if;
 execute replace(v_definition,v_old,v_new);
end;
$patch$;

-- CREATE OR REPLACE retains existing ACLs; no new exposed table or RPC.
commit;
