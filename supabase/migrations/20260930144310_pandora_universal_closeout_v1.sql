-- Pandora Universal Roadmap Closeout v1
-- Adds acceptance/runtime controls for schema compatibility, two-way sync echo suppression,
-- verified authority reconciliation, and provider deprecation impact reporting.
-- Additive only; incumbent provider execution and enterprise domain runtimes remain authoritative.

create table if not exists public.pandora_schema_compatibility_rules (
  schema_key text not null check (schema_key ~ '^[a-z][a-z0-9_.-]{1,127}$'),
  from_version text not null check (from_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  to_version text not null check (to_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  compatibility_mode text not null check (compatibility_mode in ('backward_read','bidirectional','breaking')),
  migration_ref text,
  notes text,
  created_at timestamptz not null default clock_timestamp(),
  primary key(schema_key,from_version,to_version)
);

create or replace function public.pandora_schema_read_compatibility_v1(
  p_schema_key text,p_from_version text,p_to_version text
)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare v_rule public.pandora_schema_compatibility_rules%rowtype;
begin
  if p_schema_key is null or p_from_version is null or p_to_version is null
     or p_schema_key !~ '^[a-z][a-z0-9_.-]{1,127}$'
     or p_from_version !~ '^[0-9]+[.][0-9]+[.][0-9]+$'
     or p_to_version !~ '^[0-9]+[.][0-9]+[.][0-9]+$' then
    raise exception 'schema_compatibility_input_invalid' using errcode='22023';
  end if;
  if p_from_version=p_to_version then
    return jsonb_build_object('readable',true,'schemaKey',p_schema_key,'fromVersion',p_from_version,
      'toVersion',p_to_version,'mode','exact','reason','exact_version');
  end if;
  select * into v_rule from public.pandora_schema_compatibility_rules r
   where r.schema_key=p_schema_key and r.from_version=p_from_version and r.to_version=p_to_version;
  if not found then
    return jsonb_build_object('readable',false,'schemaKey',p_schema_key,'fromVersion',p_from_version,
      'toVersion',p_to_version,'mode','unsupported','reason','compatibility_rule_missing');
  end if;
  return jsonb_build_object(
    'readable',v_rule.compatibility_mode in ('backward_read','bidirectional'),
    'schemaKey',p_schema_key,'fromVersion',p_from_version,'toVersion',p_to_version,
    'mode',v_rule.compatibility_mode,'migrationRef',v_rule.migration_ref,
    'reason',case when v_rule.compatibility_mode in ('backward_read','bidirectional')
      then 'supported_version_transition' else 'breaking_transition' end
  );
end;
$$;

create or replace function public.pandora_sync_guard_v1(
  p_organization_id uuid,p_mapping_spec_id uuid,p_direction text,
  p_source_event_digest text,p_target_write_digest text,p_idempotency_key text,
  p_evidence_refs jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
declare
  v_opposite text;
  v_existing public.enterprise_sync_receipts%rowtype;
  v_echo public.enterprise_sync_receipts%rowtype;
  v_inserted public.enterprise_sync_receipts%rowtype;
begin
  if p_direction not in ('inbound','outbound') then
    raise exception 'sync_direction_invalid' using errcode='22023';
  end if;
  if p_source_event_digest is null or p_source_event_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'sync_source_digest_invalid' using errcode='22023';
  end if;
  if p_target_write_digest is not null and p_target_write_digest !~ '^[0-9a-f]{64}$' then
    raise exception 'sync_target_digest_invalid' using errcode='22023';
  end if;
  if p_idempotency_key is null or char_length(p_idempotency_key) not between 16 and 160 then
    raise exception 'sync_idempotency_key_invalid' using errcode='22023';
  end if;
  if p_evidence_refs is null or jsonb_typeof(p_evidence_refs)<>'array' then
    raise exception 'sync_evidence_invalid' using errcode='22023';
  end if;
  perform 1 from public.enterprise_mapping_specs m
   where m.organization_id=p_organization_id and m.id=p_mapping_spec_id;
  if not found then raise exception 'sync_mapping_not_found' using errcode='P0002'; end if;

  select * into v_existing from public.enterprise_sync_receipts r
   where r.organization_id=p_organization_id and r.mapping_spec_id=p_mapping_spec_id
     and r.direction=p_direction and r.source_event_digest=p_source_event_digest
   order by r.created_at desc limit 1;
  if found then
    return jsonb_build_object('ok',true,'apply',false,'duplicate',true,
      'reason','duplicate_source_event','receiptId',v_existing.id);
  end if;

  v_opposite:=case when p_direction='inbound' then 'outbound' else 'inbound' end;
  select * into v_echo from public.enterprise_sync_receipts r
   where r.organization_id=p_organization_id and r.mapping_spec_id=p_mapping_spec_id
     and r.direction=v_opposite and r.target_write_digest=p_source_event_digest
     and r.outcome in ('applied','pending_verification','verified')
   order by r.created_at desc limit 1;
  if found then
    insert into public.enterprise_sync_receipts(
      organization_id,mapping_spec_id,direction,source_event_digest,target_write_digest,
      idempotency_key,outcome,evidence_refs
    ) values(
      p_organization_id,p_mapping_spec_id,p_direction,p_source_event_digest,p_target_write_digest,
      p_idempotency_key,'duplicate',
      p_evidence_refs || jsonb_build_array(jsonb_build_object('type','sync_echo','ref','receipt:'||v_echo.id::text))
    ) returning * into v_inserted;
    return jsonb_build_object('ok',true,'apply',false,'duplicate',true,
      'reason','opposite_direction_echo_suppressed','receiptId',v_inserted.id,'echoOfReceiptId',v_echo.id);
  end if;
  return jsonb_build_object('ok',true,'apply',true,'duplicate',false,'reason','new_source_event');
end;
$$;

create table if not exists public.enterprise_reconciliation_decisions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  entity_id uuid not null,
  field_path text not null check (field_path ~ '^[a-z][a-z0-9_.]{0,254}$'),
  incoming_provenance_id uuid not null,
  current_provenance_id uuid,
  authority_policy_id uuid,
  outcome text not null check (outcome in (
    'accepted_no_current','accepted_same_value','accepted_authoritative',
    'retained_current','manual_review','recompute_required','blocked'
  )),
  reason text not null,
  evidence_refs jsonb not null default '[]'::jsonb check (jsonb_typeof(evidence_refs)='array'),
  created_at timestamptz not null default clock_timestamp(),
  unique(id,organization_id),
  constraint enterprise_reconciliation_decisions_entity_org_fkey
    foreign key(entity_id,organization_id) references public.enterprise_entities(id,organization_id) on delete restrict,
  constraint enterprise_reconciliation_decisions_incoming_org_fkey
    foreign key(incoming_provenance_id,organization_id) references public.enterprise_field_provenance(id,organization_id) on delete restrict,
  constraint enterprise_reconciliation_decisions_current_org_fkey
    foreign key(current_provenance_id,organization_id) references public.enterprise_field_provenance(id,organization_id) on delete restrict,
  constraint enterprise_reconciliation_decisions_authority_org_fkey
    foreign key(authority_policy_id,organization_id) references public.enterprise_authority_policies(id,organization_id) on delete restrict
);

create index if not exists enterprise_reconciliation_decisions_entity_idx
  on public.enterprise_reconciliation_decisions(organization_id,entity_id,field_path,created_at desc);

create or replace function private.pandora_reject_reconciliation_decision_mutation_v1()
returns trigger language plpgsql security invoker set search_path='pg_catalog','public' as $$
begin
  raise exception 'reconciliation_decisions_are_append_only' using errcode='55000';
end;
$$;

drop trigger if exists enterprise_reconciliation_decisions_append_only on public.enterprise_reconciliation_decisions;
create trigger enterprise_reconciliation_decisions_append_only
before update or delete on public.enterprise_reconciliation_decisions
for each row execute function private.pandora_reject_reconciliation_decision_mutation_v1();

create or replace function public.pandora_reconcile_verified_field_v1(
  p_organization_id uuid,p_incoming_provenance_id uuid,p_evidence_refs jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
declare
  v_incoming public.enterprise_field_provenance%rowtype;
  v_current public.enterprise_field_provenance%rowtype;
  v_policy public.enterprise_authority_policies%rowtype;
  v_entity_kind text;
  v_outcome text;
  v_reason text;
  v_apply boolean:=false;
  v_incoming_authoritative boolean:=false;
  v_decision_id uuid;
begin
  if p_evidence_refs is null or jsonb_typeof(p_evidence_refs)<>'array' then
    raise exception 'reconciliation_evidence_invalid' using errcode='22023';
  end if;
  select * into v_incoming from public.enterprise_field_provenance p
   where p.organization_id=p_organization_id and p.id=p_incoming_provenance_id
     and p.verified_at is not null and p.confidence_state='verified';
  if not found then raise exception 'incoming_provenance_not_verified' using errcode='55000'; end if;
  if jsonb_array_length(v_incoming.evidence_refs)=0 then
    raise exception 'incoming_provenance_evidence_required' using errcode='55000';
  end if;

  select e.entity_kind into v_entity_kind from public.enterprise_entities e
   where e.organization_id=p_organization_id and e.id=v_incoming.entity_id;
  if not found then raise exception 'reconciliation_entity_not_found' using errcode='P0002'; end if;

  select * into v_policy from public.enterprise_authority_policies p
   where p.organization_id=p_organization_id and p.entity_kind=v_entity_kind
     and p.field_path in (v_incoming.field_path,'*') and p.superseded_at is null
     and p.effective_from<=clock_timestamp()
     and (p.effective_to is null or p.effective_to>clock_timestamp())
   order by case when p.field_path=v_incoming.field_path then 0 else 1 end,p.effective_from desc limit 1;

  if not found then
    insert into public.enterprise_reconciliation_decisions(
      organization_id,entity_id,field_path,incoming_provenance_id,outcome,reason,evidence_refs
    ) values(
      p_organization_id,v_incoming.entity_id,v_incoming.field_path,v_incoming.id,
      'blocked','authority_policy_missing',p_evidence_refs
    ) returning id into v_decision_id;
    return jsonb_build_object('ok',false,'applied',false,'outcome','blocked',
      'reason','authority_policy_missing','decisionId',v_decision_id);
  end if;

  select * into v_current from public.enterprise_field_provenance p
   where p.organization_id=p_organization_id and p.entity_id=v_incoming.entity_id
     and p.field_path=v_incoming.field_path and p.id<>v_incoming.id
     and p.superseded_at is null and p.confidence_state='verified'
   order by coalesce(p.effective_at,p.observed_at,p.created_at) desc,p.created_at desc limit 1;

  if not found then
    v_outcome:='accepted_no_current'; v_reason:='verified_value_has_no_current_competitor'; v_apply:=true;
  elsif v_current.value_hmac_sha256=v_incoming.value_hmac_sha256 then
    update public.enterprise_field_provenance
      set confidence_state='superseded',superseded_at=clock_timestamp()
      where id=v_current.id and organization_id=p_organization_id;
    update public.enterprise_field_provenance
      set supersedes_provenance_id=v_current.id,authority_policy_id=v_policy.id
      where id=v_incoming.id and organization_id=p_organization_id;
    v_outcome:='accepted_same_value'; v_reason:='verified_value_matches_current'; v_apply:=true;
  else
    v_incoming_authoritative:=case
      when v_policy.authority_kind='pandora_derived' then v_incoming.source_connection_id is null
      else v_incoming.source_connection_id=v_policy.source_connection_id end;
    if v_incoming_authoritative then
      update public.enterprise_field_provenance
        set confidence_state='superseded',superseded_at=clock_timestamp()
        where id=v_current.id and organization_id=p_organization_id;
      update public.enterprise_field_provenance
        set supersedes_provenance_id=v_current.id,authority_policy_id=v_policy.id
        where id=v_incoming.id and organization_id=p_organization_id;
      v_outcome:='accepted_authoritative'; v_reason:='incoming_source_matches_authority_policy'; v_apply:=true;
    else
      update public.enterprise_field_provenance
        set confidence_state='disputed',authority_policy_id=v_policy.id
        where id=v_incoming.id and organization_id=p_organization_id;
      case v_policy.conflict_action
        when 'manual_review' then v_outcome:='manual_review'; v_reason:='non_authoritative_conflict_requires_manual_review';
        when 'recompute' then v_outcome:='recompute_required'; v_reason:='non_authoritative_conflict_requires_recompute';
        when 'retain_current' then v_outcome:='retained_current'; v_reason:='current_authoritative_value_retained';
        else v_outcome:='blocked'; v_reason:='non_authoritative_conflict_blocked';
      end case;
    end if;
  end if;

  insert into public.enterprise_reconciliation_decisions(
    organization_id,entity_id,field_path,incoming_provenance_id,current_provenance_id,
    authority_policy_id,outcome,reason,evidence_refs
  ) values(
    p_organization_id,v_incoming.entity_id,v_incoming.field_path,v_incoming.id,v_current.id,
    v_policy.id,v_outcome,v_reason,p_evidence_refs
  ) returning id into v_decision_id;

  return jsonb_build_object('ok',true,'applied',v_apply,'outcome',v_outcome,'reason',v_reason,
    'decisionId',v_decision_id,'authorityPolicyId',v_policy.id,
    'currentProvenanceId',v_current.id,'incomingProvenanceId',v_incoming.id);
end;
$$;

create table if not exists public.pandora_provider_deprecation_notices (
  provider_key text not null,
  manifest_version text not null,
  notice_at timestamptz not null,
  sunset_at timestamptz not null,
  replacement_provider_key text,
  reason text not null check (char_length(reason) between 1 and 1000),
  notice_state text not null default 'announced' check (notice_state in ('announced','cancelled','completed')),
  created_at timestamptz not null default clock_timestamp(),
  primary key(provider_key,manifest_version),
  constraint pandora_provider_deprecation_notices_manifest_fkey
    foreign key(provider_key,manifest_version)
    references public.pandora_provider_manifests(provider_key,manifest_version) on delete restrict,
  check (sunset_at>notice_at)
);

create or replace function public.pandora_provider_deprecation_impact_v1(
  p_provider_key text,p_manifest_version text
)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare
  v_capabilities jsonb;
  v_active_activations bigint;
  v_required_policies bigint;
  v_preferred_policies bigint;
  v_fallback_policies bigint;
  v_notice public.pandora_provider_deprecation_notices%rowtype;
  v_has_notice boolean:=false;
begin
  if not exists(select 1 from public.pandora_provider_manifests m
    where m.provider_key=p_provider_key and m.manifest_version=p_manifest_version) then
    raise exception 'provider_manifest_not_found' using errcode='P0002';
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'capabilityKey',c.capability_key,'capabilityVersion',c.capability_version,
    'operationMode',c.operation_mode,'implementationState',c.implementation_state
  ) order by c.capability_key,c.capability_version),'[]'::jsonb)
  into v_capabilities from public.pandora_provider_capabilities c
  where c.provider_key=p_provider_key and c.manifest_version=p_manifest_version;

  select count(*) into v_active_activations from public.pandora_provider_activations a
   where a.provider_key=p_provider_key and a.manifest_version=p_manifest_version and a.activation_state='authorized';
  select count(*) into v_required_policies from public.pandora_provider_selection_policies p
   where p.required_provider=p_provider_key;
  select count(*) into v_preferred_policies from public.pandora_provider_selection_policies p
   where p_provider_key=any(p.preferred_providers);
  select count(*) into v_fallback_policies from public.pandora_provider_selection_policies p
   where p_provider_key=any(p.fallback_providers);

  select * into v_notice from public.pandora_provider_deprecation_notices n
   where n.provider_key=p_provider_key and n.manifest_version=p_manifest_version;
  v_has_notice:=found;

  return jsonb_build_object(
    'providerKey',p_provider_key,'manifestVersion',p_manifest_version,'capabilities',v_capabilities,
    'activeActivations',v_active_activations,'requiredPolicyDependencies',v_required_policies,
    'preferredPolicyDependencies',v_preferred_policies,'fallbackPolicyDependencies',v_fallback_policies,
    'warningVisible',v_has_notice and v_notice.notice_state='announced' and v_notice.sunset_at>clock_timestamp(),
    'noticeAt',case when v_has_notice then v_notice.notice_at else null end,
    'sunsetAt',case when v_has_notice then v_notice.sunset_at else null end,
    'replacementProviderKey',case when v_has_notice then v_notice.replacement_provider_key else null end,
    'readyForSunset',v_has_notice and v_notice.notice_state='announced'
      and v_notice.sunset_at>clock_timestamp() and v_active_activations=0
      and v_required_policies=0 and v_preferred_policies=0 and v_fallback_policies=0
  );
end;
$$;

alter table public.pandora_schema_compatibility_rules enable row level security;
alter table public.enterprise_reconciliation_decisions enable row level security;
alter table public.pandora_provider_deprecation_notices enable row level security;

revoke all on table public.pandora_schema_compatibility_rules,
  public.enterprise_reconciliation_decisions,
  public.pandora_provider_deprecation_notices from public,anon,authenticated;

grant select on table public.pandora_schema_compatibility_rules,
  public.pandora_provider_deprecation_notices to authenticated,service_role;
grant select on table public.enterprise_reconciliation_decisions to authenticated,service_role;
grant insert,update,delete on table public.pandora_schema_compatibility_rules,
  public.pandora_provider_deprecation_notices to service_role;
grant insert on table public.enterprise_reconciliation_decisions to service_role;

drop policy if exists pandora_schema_compatibility_rules_authenticated_read on public.pandora_schema_compatibility_rules;
create policy pandora_schema_compatibility_rules_authenticated_read
 on public.pandora_schema_compatibility_rules for select to authenticated using(true);
drop policy if exists pandora_schema_compatibility_rules_service_all on public.pandora_schema_compatibility_rules;
create policy pandora_schema_compatibility_rules_service_all
 on public.pandora_schema_compatibility_rules for all to service_role using(true) with check(true);

drop policy if exists pandora_provider_deprecation_notices_authenticated_read on public.pandora_provider_deprecation_notices;
create policy pandora_provider_deprecation_notices_authenticated_read
 on public.pandora_provider_deprecation_notices for select to authenticated using(true);
drop policy if exists pandora_provider_deprecation_notices_service_all on public.pandora_provider_deprecation_notices;
create policy pandora_provider_deprecation_notices_service_all
 on public.pandora_provider_deprecation_notices for all to service_role using(true) with check(true);

drop policy if exists enterprise_reconciliation_decisions_member_select on public.enterprise_reconciliation_decisions;
create policy enterprise_reconciliation_decisions_member_select
 on public.enterprise_reconciliation_decisions for select to authenticated
 using(exists(select 1 from public.memberships m
  where m.organization_id=enterprise_reconciliation_decisions.organization_id
    and m.user_id=(select auth.uid()) and m.status='active'));
drop policy if exists enterprise_reconciliation_decisions_service_insert on public.enterprise_reconciliation_decisions;
create policy enterprise_reconciliation_decisions_service_insert
 on public.enterprise_reconciliation_decisions for insert to service_role with check(true);
drop policy if exists enterprise_reconciliation_decisions_service_select on public.enterprise_reconciliation_decisions;
create policy enterprise_reconciliation_decisions_service_select
 on public.enterprise_reconciliation_decisions for select to service_role using(true);

revoke update,delete on table public.enterprise_reconciliation_decisions from service_role;

revoke all on function public.pandora_schema_read_compatibility_v1(text,text,text) from public,anon;
revoke all on function public.pandora_sync_guard_v1(uuid,uuid,text,text,text,text,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_reconcile_verified_field_v1(uuid,uuid,jsonb) from public,anon,authenticated;
revoke all on function public.pandora_provider_deprecation_impact_v1(text,text) from public,anon;

grant execute on function public.pandora_schema_read_compatibility_v1(text,text,text) to authenticated,service_role;
grant execute on function public.pandora_sync_guard_v1(uuid,uuid,text,text,text,text,jsonb) to service_role;
grant execute on function public.pandora_reconcile_verified_field_v1(uuid,uuid,jsonb) to service_role;
grant execute on function public.pandora_provider_deprecation_impact_v1(text,text) to authenticated,service_role;

