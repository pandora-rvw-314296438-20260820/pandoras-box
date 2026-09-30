-- Pandora internal closure v1.
-- Adds supported schema reads, sync-loop guards, legal evidence version history,
-- and capability deprecation dependency fencing.

create table if not exists public.enterprise_schema_compatibility (
  entity_kind text not null references public.enterprise_entity_type_registry(entity_kind) on delete restrict,
  from_version text not null check (from_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  to_version text not null check (to_version ~ '^[0-9]+[.][0-9]+[.][0-9]+$'),
  read_compatible boolean not null default false,
  transform_contract jsonb not null default '{}'::jsonb check (jsonb_typeof(transform_contract)='object'),
  created_at timestamptz not null default clock_timestamp(),
  primary key(entity_kind,from_version,to_version)
);

insert into public.enterprise_schema_compatibility(
  entity_kind,from_version,to_version,read_compatible,transform_contract
) values (
  'person','0.9.0','1.0.0',true,
  '{"mode":"field_rename","fieldRenames":{"name":"display_name"}}'::jsonb
)
on conflict(entity_kind,from_version,to_version) do nothing;

create or replace function public.pandora_enterprise_read_compatible_payload_v1(
  p_entity_kind text,
  p_payload_version text,
  p_reader_version text,
  p_payload jsonb
)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare
  v_rule public.enterprise_schema_compatibility%rowtype;
  v_payload jsonb:=coalesce(p_payload,'{}'::jsonb);
  v_old text;
  v_new text;
begin
  if jsonb_typeof(v_payload)<>'object' then
    return jsonb_build_object('compatible',false,'reason','payload_must_be_object');
  end if;

  if p_payload_version=p_reader_version then
    return jsonb_build_object(
      'compatible',true,'strategy','identity','payload',v_payload,
      'entityKind',p_entity_kind,'payloadVersion',p_payload_version,'readerVersion',p_reader_version
    );
  end if;

  select * into v_rule
  from public.enterprise_schema_compatibility
  where entity_kind=p_entity_kind
    and from_version=p_payload_version
    and to_version=p_reader_version;

  if not found or v_rule.read_compatible is not true then
    return jsonb_build_object(
      'compatible',false,'reason','unsupported_version_transition',
      'entityKind',p_entity_kind,'payloadVersion',p_payload_version,'readerVersion',p_reader_version
    );
  end if;

  if v_rule.transform_contract->>'mode'='field_rename' then
    for v_old,v_new in
      select key,value
      from jsonb_each_text(coalesce(v_rule.transform_contract->'fieldRenames','{}'::jsonb))
    loop
      if v_payload ? v_old then
        if not (v_payload ? v_new) then
          v_payload:=jsonb_set(v_payload,array[v_new],v_payload->v_old,true);
        end if;
        v_payload:=v_payload-v_old;
      end if;
    end loop;
  elsif coalesce(v_rule.transform_contract->>'mode','identity')<>'identity' then
    return jsonb_build_object('compatible',false,'reason','unsupported_transform_contract');
  end if;

  return jsonb_build_object(
    'compatible',true,
    'strategy',coalesce(v_rule.transform_contract->>'mode','identity'),
    'payload',v_payload,
    'entityKind',p_entity_kind,
    'payloadVersion',p_payload_version,
    'readerVersion',p_reader_version
  );
end;
$$;

alter table public.enterprise_sync_receipts
  add column if not exists origin_receipt_id uuid,
  add column if not exists loop_token text;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.enterprise_sync_receipts'::regclass
      and conname='enterprise_sync_receipts_origin_org_fkey'
  ) then
    alter table public.enterprise_sync_receipts
      add constraint enterprise_sync_receipts_origin_org_fkey
      foreign key(origin_receipt_id,organization_id)
      references public.enterprise_sync_receipts(id,organization_id)
      on delete restrict;
  end if;
end;
$constraints$;

create index if not exists enterprise_sync_receipts_origin_idx
  on public.enterprise_sync_receipts(organization_id,origin_receipt_id);

create or replace function public.pandora_sync_loop_preflight_v1(
  p_organization_id uuid,
  p_mapping_spec_id uuid,
  p_direction text,
  p_source_event_digest text,
  p_origin_receipt_id uuid default null
)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare
  v_origin public.enterprise_sync_receipts%rowtype;
begin
  if p_direction not in ('inbound','outbound') then
    raise exception 'sync_direction_invalid' using errcode='22023';
  end if;
  if coalesce(p_source_event_digest,'') !~ '^[0-9a-f]{64}$' then
    raise exception 'sync_source_digest_invalid' using errcode='22023';
  end if;

  if p_origin_receipt_id is not null then
    select * into v_origin
    from public.enterprise_sync_receipts
    where id=p_origin_receipt_id and organization_id=p_organization_id;

    if not found then
      return jsonb_build_object('ready',false,'reason','origin_receipt_not_found');
    end if;

    if v_origin.mapping_spec_id=p_mapping_spec_id and v_origin.direction<>p_direction then
      return jsonb_build_object(
        'ready',false,'reason','round_trip_origin_detected',
        'originReceiptId',v_origin.id,'originDirection',v_origin.direction
      );
    end if;
  end if;

  if exists(
    select 1 from public.enterprise_sync_receipts r
    where r.organization_id=p_organization_id
      and r.mapping_spec_id=p_mapping_spec_id
      and r.source_event_digest=p_source_event_digest
      and r.direction<>p_direction
  ) then
    return jsonb_build_object('ready',false,'reason','round_trip_digest_detected');
  end if;

  if exists(
    select 1 from public.enterprise_sync_receipts r
    where r.organization_id=p_organization_id
      and r.mapping_spec_id=p_mapping_spec_id
      and r.source_event_digest=p_source_event_digest
      and r.direction=p_direction
  ) then
    return jsonb_build_object('ready',false,'reason','duplicate_source_event');
  end if;

  return jsonb_build_object('ready',true,'reason','new_sync_event');
end;
$$;

create table if not exists public.enterprise_legal_evidence_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  document_entity_id uuid not null,
  version_number integer not null check (version_number>=1),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  source_record_id uuid,
  parent_version_id uuid,
  processing_state text not null default 'preserved'
    check (processing_state in ('preserved','extracted','reviewed','derived')),
  processing_metadata_redacted jsonb not null default '{}'::jsonb
    check (jsonb_typeof(processing_metadata_redacted)='object'),
  created_at timestamptz not null default clock_timestamp(),
  unique(id,organization_id),
  unique(organization_id,document_entity_id,version_number),
  constraint enterprise_legal_evidence_versions_item_org_fkey
    foreign key(document_entity_id,organization_id)
    references public.enterprise_legal_evidence_items(document_entity_id,organization_id)
    on delete restrict,
  constraint enterprise_legal_evidence_versions_source_org_fkey
    foreign key(source_record_id,organization_id)
    references public.enterprise_source_records(id,organization_id)
    on delete restrict,
  constraint enterprise_legal_evidence_versions_parent_org_fkey
    foreign key(parent_version_id,organization_id)
    references public.enterprise_legal_evidence_versions(id,organization_id)
    on delete restrict
);

create index if not exists enterprise_legal_evidence_versions_history_idx
  on public.enterprise_legal_evidence_versions(organization_id,document_entity_id,version_number);

create or replace function private.pandora_reject_legal_evidence_version_mutation_v1()
returns trigger
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
begin
  raise exception 'legal_evidence_versions_are_append_only' using errcode='55000';
end;
$$;

drop trigger if exists enterprise_legal_evidence_versions_append_only
  on public.enterprise_legal_evidence_versions;
create trigger enterprise_legal_evidence_versions_append_only
before update or delete on public.enterprise_legal_evidence_versions
for each row execute function private.pandora_reject_legal_evidence_version_mutation_v1();

create or replace function public.pandora_legal_evidence_history_v1(
  p_organization_id uuid,
  p_document_entity_id uuid
)
returns jsonb
language sql
security invoker
stable
set search_path='pg_catalog','public'
as $$
  select jsonb_build_object(
    'documentEntityId',i.document_entity_id,
    'originalContentSha256',i.original_content_sha256,
    'evidenceState',i.evidence_state,
    'versions',coalesce((
      select jsonb_agg(jsonb_build_object(
        'versionId',v.id,
        'versionNumber',v.version_number,
        'contentSha256',v.content_sha256,
        'sourceRecordId',v.source_record_id,
        'parentVersionId',v.parent_version_id,
        'processingState',v.processing_state,
        'createdAt',v.created_at
      ) order by v.version_number)
      from public.enterprise_legal_evidence_versions v
      where v.organization_id=i.organization_id
        and v.document_entity_id=i.document_entity_id
    ),'[]'::jsonb)
  )
  from public.enterprise_legal_evidence_items i
  where i.organization_id=p_organization_id
    and i.document_entity_id=p_document_entity_id;
$$;

create table if not exists public.pandora_capability_dependencies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  workflow_key text not null check (workflow_key ~ '^[a-z][a-z0-9_.:-]{1,159}$'),
  capability_key text not null,
  capability_version text not null,
  dependency_state text not null default 'active'
    check (dependency_state in ('active','migrated','retired')),
  replacement_capability_key text,
  replacement_capability_version text,
  updated_at timestamptz not null default clock_timestamp(),
  created_at timestamptz not null default clock_timestamp(),
  unique(organization_id,workflow_key,capability_key,capability_version),
  unique(id,organization_id),
  constraint pandora_capability_dependencies_spec_fkey
    foreign key(capability_key,capability_version)
    references public.pandora_capability_specs(capability_key,capability_version)
    on delete restrict
);

create table if not exists public.pandora_capability_deprecation_reports (
  id uuid primary key default gen_random_uuid(),
  capability_key text not null,
  capability_version text not null,
  blocking_dependency_count integer not null check (blocking_dependency_count>=0),
  dependencies jsonb not null default '[]'::jsonb check (jsonb_typeof(dependencies)='array'),
  generated_at timestamptz not null default clock_timestamp(),
  constraint pandora_capability_deprecation_reports_spec_fkey
    foreign key(capability_key,capability_version)
    references public.pandora_capability_specs(capability_key,capability_version)
    on delete restrict
);

create index if not exists pandora_capability_dependencies_spec_idx
  on public.pandora_capability_dependencies(
    capability_key,capability_version,dependency_state,organization_id
  );

create or replace function private.pandora_reject_capability_deprecation_report_mutation_v1()
returns trigger
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
begin
  raise exception 'capability_deprecation_reports_are_append_only' using errcode='55000';
end;
$$;

drop trigger if exists pandora_capability_deprecation_reports_append_only
  on public.pandora_capability_deprecation_reports;
create trigger pandora_capability_deprecation_reports_append_only
before update or delete on public.pandora_capability_deprecation_reports
for each row execute function private.pandora_reject_capability_deprecation_report_mutation_v1();

create or replace function public.pandora_capability_deprecation_report_v1(
  p_capability_key text,
  p_capability_version text
)
returns jsonb
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
declare
  v_blocking integer;
  v_dependencies jsonb;
  v_report_id uuid;
begin
  if not exists(
    select 1 from public.pandora_capability_specs
    where capability_key=p_capability_key and capability_version=p_capability_version
  ) then
    raise exception 'capability_not_found' using errcode='22023';
  end if;

  select
    count(*) filter(where dependency_state='active')::integer,
    coalesce(jsonb_agg(jsonb_build_object(
      'organizationId',organization_id,
      'workflowKey',workflow_key,
      'state',dependency_state,
      'replacementCapabilityKey',replacement_capability_key,
      'replacementCapabilityVersion',replacement_capability_version
    ) order by organization_id,workflow_key),'[]'::jsonb)
  into v_blocking,v_dependencies
  from public.pandora_capability_dependencies
  where capability_key=p_capability_key and capability_version=p_capability_version;

  insert into public.pandora_capability_deprecation_reports(
    capability_key,capability_version,blocking_dependency_count,dependencies
  ) values (
    p_capability_key,p_capability_version,coalesce(v_blocking,0),v_dependencies
  ) returning id into v_report_id;

  return jsonb_build_object(
    'reportId',v_report_id,
    'capabilityKey',p_capability_key,
    'capabilityVersion',p_capability_version,
    'blockingDependencyCount',coalesce(v_blocking,0),
    'dependencies',v_dependencies
  );
end;
$$;

create or replace function public.pandora_capability_set_lifecycle_v1(
  p_capability_key text,
  p_capability_version text,
  p_target_state text,
  p_report_id uuid
)
returns jsonb
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
declare
  v_report public.pandora_capability_deprecation_reports%rowtype;
begin
  if p_target_state not in ('deprecated','retired') then
    raise exception 'capability_lifecycle_target_invalid' using errcode='22023';
  end if;

  select * into v_report
  from public.pandora_capability_deprecation_reports
  where id=p_report_id
    and capability_key=p_capability_key
    and capability_version=p_capability_version;

  if not found then
    raise exception 'capability_deprecation_report_required' using errcode='22023';
  end if;
  if v_report.generated_at<clock_timestamp()-interval '24 hours' then
    raise exception 'capability_deprecation_report_stale' using errcode='22023';
  end if;
  if v_report.blocking_dependency_count>0 then
    raise exception 'capability_has_active_dependencies' using errcode='55000';
  end if;

  update public.pandora_capability_specs
  set lifecycle_state=p_target_state
  where capability_key=p_capability_key and capability_version=p_capability_version;

  if not found then
    raise exception 'capability_not_found' using errcode='22023';
  end if;

  return jsonb_build_object(
    'ok',true,'capabilityKey',p_capability_key,'capabilityVersion',p_capability_version,
    'lifecycleState',p_target_state,'reportId',p_report_id
  );
end;
$$;

alter table public.enterprise_schema_compatibility enable row level security;
revoke all on table public.enterprise_schema_compatibility from public,anon,authenticated;
grant select on table public.enterprise_schema_compatibility to authenticated,service_role;
grant select,insert,update,delete on table public.enterprise_schema_compatibility to service_role;
drop policy if exists enterprise_schema_compatibility_authenticated_read on public.enterprise_schema_compatibility;
create policy enterprise_schema_compatibility_authenticated_read
  on public.enterprise_schema_compatibility for select to authenticated using(true);
drop policy if exists enterprise_schema_compatibility_service_all on public.enterprise_schema_compatibility;
create policy enterprise_schema_compatibility_service_all
  on public.enterprise_schema_compatibility for all to service_role using(true) with check(true);

do $rls$
declare
  v_table text;
  v_read text;
  v_service text;
begin
  foreach v_table in array array[
    'enterprise_legal_evidence_versions',
    'pandora_capability_dependencies'
  ] loop
    execute format('alter table public.%I enable row level security',v_table);
    execute format('revoke all on table public.%I from public,anon,authenticated',v_table);
    execute format('grant select on table public.%I to authenticated',v_table);
    execute format('grant select,insert,update,delete on table public.%I to service_role',v_table);
    v_read:=v_table||'_member_select';
    v_service:=v_table||'_service_all';
    execute format('drop policy if exists %I on public.%I',v_read,v_table);
    execute format(
      'create policy %I on public.%I for select to authenticated using (exists (select 1 from public.memberships m where m.organization_id=%I.organization_id and m.user_id=(select auth.uid()) and m.status=''active''))',
      v_read,v_table,v_table
    );
    execute format('drop policy if exists %I on public.%I',v_service,v_table);
    execute format('create policy %I on public.%I for all to service_role using(true) with check(true)',v_service,v_table);
  end loop;
end;
$rls$;

revoke update,delete on table public.enterprise_legal_evidence_versions from service_role;

alter table public.pandora_capability_deprecation_reports enable row level security;
revoke all on table public.pandora_capability_deprecation_reports from public,anon,authenticated;
grant select,insert on table public.pandora_capability_deprecation_reports to service_role;
drop policy if exists pandora_capability_deprecation_reports_service_all
  on public.pandora_capability_deprecation_reports;
create policy pandora_capability_deprecation_reports_service_all
  on public.pandora_capability_deprecation_reports for all to service_role using(true) with check(true);

revoke all on function public.pandora_enterprise_read_compatible_payload_v1(text,text,text,jsonb) from public,anon;
grant execute on function public.pandora_enterprise_read_compatible_payload_v1(text,text,text,jsonb) to authenticated,service_role;

revoke all on function public.pandora_sync_loop_preflight_v1(uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.pandora_sync_loop_preflight_v1(uuid,uuid,text,text,uuid) to service_role;

revoke all on function public.pandora_legal_evidence_history_v1(uuid,uuid) from public,anon;
grant execute on function public.pandora_legal_evidence_history_v1(uuid,uuid) to authenticated,service_role;

revoke all on function public.pandora_capability_deprecation_report_v1(text,text) from public,anon,authenticated;
revoke all on function public.pandora_capability_set_lifecycle_v1(text,text,text,uuid) from public,anon,authenticated;
grant execute on function public.pandora_capability_deprecation_report_v1(text,text) to service_role;
grant execute on function public.pandora_capability_set_lifecycle_v1(text,text,text,uuid) to service_role;
