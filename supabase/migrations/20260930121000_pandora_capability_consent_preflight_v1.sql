-- Pandora Universal Enterprise capability consent + authorization preflight v1.
-- Adds the missing consent gate without creating a second approval system.
-- Exact-action approval remains owned by Pandora Tool Gateway / public.approvals.

alter table public.pandora_provider_selection_policies
  add column if not exists consent_required boolean not null default false,
  add column if not exists consent_purpose text,
  add column if not exists consent_subject_required boolean not null default true;

alter table public.pandora_provider_selection_policies
  drop constraint if exists pandora_provider_selection_policies_consent_contract_check;

alter table public.pandora_provider_selection_policies
  add constraint pandora_provider_selection_policies_consent_contract_check
  check (
    not consent_required
    or (
      consent_purpose is not null
      and char_length(btrim(consent_purpose)) between 1 and 500
    )
  );

create or replace function public.pandora_capability_consent_preflight_v1(
  p_organization_id uuid,
  p_capability_key text,
  p_capability_version text default '1.0.0',
  p_subject_entity_id uuid default null,
  p_purpose text default null
)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare
  v_policy public.pandora_provider_selection_policies%rowtype;
  v_required boolean:=false;
  v_subject_required boolean:=true;
  v_expected_purpose text;
  v_purpose text:=nullif(btrim(coalesce(p_purpose,'')),'');
  v_grant public.pandora_consent_grants%rowtype;
  v_recent public.pandora_consent_grants%rowtype;
begin
  if not exists(
    select 1
    from public.pandora_capability_specs s
    where s.capability_key=p_capability_key
      and s.capability_version=p_capability_version
      and s.lifecycle_state='active'
  ) then
    return jsonb_build_object(
      'ready',false,
      'required',false,
      'reason','capability_not_active',
      'capabilityKey',p_capability_key,
      'capabilityVersion',p_capability_version
    );
  end if;

  select * into v_policy
  from public.pandora_provider_selection_policies
  where organization_id=p_organization_id
    and capability_key=p_capability_key
    and capability_version=p_capability_version;

  if not found or v_policy.consent_required is not true then
    return jsonb_build_object(
      'ready',true,
      'required',false,
      'reason','consent_not_required',
      'capabilityKey',p_capability_key,
      'capabilityVersion',p_capability_version
    );
  end if;

  v_required:=true;
  v_subject_required:=coalesce(v_policy.consent_subject_required,true);
  v_expected_purpose:=nullif(btrim(coalesce(v_policy.consent_purpose,'')),'');

  if v_expected_purpose is null then
    return jsonb_build_object(
      'ready',false,'required',true,'reason','consent_policy_invalid',
      'capabilityKey',p_capability_key,'capabilityVersion',p_capability_version
    );
  end if;

  if v_purpose is null or v_purpose<>v_expected_purpose then
    return jsonb_build_object(
      'ready',false,'required',true,'reason',
      case when v_purpose is null then 'consent_purpose_required' else 'consent_purpose_mismatch' end,
      'expectedPurpose',v_expected_purpose,
      'capabilityKey',p_capability_key,'capabilityVersion',p_capability_version
    );
  end if;

  if v_subject_required and p_subject_entity_id is null then
    return jsonb_build_object(
      'ready',false,'required',true,'reason','consent_subject_required',
      'purpose',v_expected_purpose,
      'capabilityKey',p_capability_key,'capabilityVersion',p_capability_version
    );
  end if;

  if p_subject_entity_id is not null and not exists(
    select 1
    from public.enterprise_entities e
    where e.id=p_subject_entity_id and e.organization_id=p_organization_id
  ) then
    return jsonb_build_object(
      'ready',false,'required',true,'reason','consent_subject_not_found',
      'purpose',v_expected_purpose,
      'capabilityKey',p_capability_key,'capabilityVersion',p_capability_version
    );
  end if;

  select * into v_grant
  from public.pandora_consent_grants g
  where g.organization_id=p_organization_id
    and g.capability_key=p_capability_key
    and g.capability_version=p_capability_version
    and g.purpose=v_expected_purpose
    and g.subject_entity_id is not distinct from p_subject_entity_id
    and g.granted_at<=clock_timestamp()
    and g.revoked_at is null
    and (g.expires_at is null or g.expires_at>clock_timestamp())
  order by g.granted_at desc,g.id desc
  limit 1;

  if found then
    return jsonb_build_object(
      'ready',true,'required',true,'reason','consent_active',
      'grantId',v_grant.id,
      'subjectEntityId',v_grant.subject_entity_id,
      'purpose',v_grant.purpose,
      'expiresAt',v_grant.expires_at,
      'capabilityKey',p_capability_key,'capabilityVersion',p_capability_version
    );
  end if;

  select * into v_recent
  from public.pandora_consent_grants g
  where g.organization_id=p_organization_id
    and g.capability_key=p_capability_key
    and g.capability_version=p_capability_version
    and g.purpose=v_expected_purpose
    and g.subject_entity_id is not distinct from p_subject_entity_id
  order by g.granted_at desc,g.id desc
  limit 1;

  return jsonb_build_object(
    'ready',false,'required',true,
    'reason',case
      when found and v_recent.revoked_at is not null then 'consent_revoked'
      when found and v_recent.expires_at is not null and v_recent.expires_at<=clock_timestamp() then 'consent_expired'
      else 'consent_missing'
    end,
    'purpose',v_expected_purpose,
    'subjectEntityId',p_subject_entity_id,
    'capabilityKey',p_capability_key,'capabilityVersion',p_capability_version
  );
end;
$$;

create or replace function public.pandora_capability_execution_preflight_v1(
  p_organization_id uuid,
  p_selection_receipt_id uuid,
  p_subject_entity_id uuid default null,
  p_purpose text default null
)
returns jsonb
language plpgsql
security invoker
stable
set search_path='pg_catalog','public'
as $$
declare
  v_receipt public.pandora_provider_selection_receipts%rowtype;
  v_spec public.pandora_capability_specs%rowtype;
  v_policy public.pandora_provider_selection_policies%rowtype;
  v_consent jsonb;
  v_requires_approval boolean:=false;
begin
  select * into v_receipt
  from public.pandora_provider_selection_receipts r
  where r.id=p_selection_receipt_id
    and r.organization_id=p_organization_id;

  if not found then
    return jsonb_build_object(
      'allowed',false,'reason','selection_receipt_not_found',
      'selectionReceiptId',p_selection_receipt_id,
    'capabilityKey',v_receipt.capability_key,
      'capabilityVersion',v_receipt.capability_version
    );
  end if;

  if v_receipt.result_state<>'selected' or v_receipt.selected_provider is null then
    return jsonb_build_object(
      'allowed',false,'reason','provider_not_selected',
      'selectionReceiptId',v_receipt.id,
      'capabilityKey',v_receipt.capability_key,
      'capabilityVersion',v_receipt.capability_version
    );
  end if;

  select * into v_spec
  from public.pandora_capability_specs s
  where s.capability_key=v_receipt.capability_key
    and s.capability_version=v_receipt.capability_version
    and s.lifecycle_state='active';

  if not found then
    return jsonb_build_object(
      'allowed',false,'reason','capability_not_active',
      'selectionReceiptId',v_receipt.id,
      'capabilityKey',v_receipt.capability_key,
      'capabilityVersion',v_receipt.capability_version
    );
  end if;

  select * into v_policy
  from public.pandora_provider_selection_policies p
  where p.organization_id=p_organization_id
    and p.capability_key=v_receipt.capability_key
    and p.capability_version=v_receipt.capability_version;

  v_consent:=public.pandora_capability_consent_preflight_v1(
    p_organization_id,
    v_receipt.capability_key,
    v_receipt.capability_version,
    p_subject_entity_id,
    p_purpose
  );

  if coalesce((v_consent->>'ready')::boolean,false) is not true then
    return jsonb_build_object(
      'allowed',false,
      'reason',v_consent->>'reason',
      'selectionReceiptId',v_receipt.id,
      'selectedProvider',v_receipt.selected_provider,
      'consent',v_consent,
      'authorizationBoundary','pandora_tool_gateway',
      'approvalBinding','exact_action_hash'
    );
  end if;

  v_requires_approval:=
    coalesce(v_receipt.approval_required,false)
    or v_spec.approval_default='required'
    or (
      v_spec.approval_default='policy'
      and found
      and coalesce(v_policy.approval_required,false)
    );

  return jsonb_build_object(
    'allowed',true,
    'reason','preflight_ready',
    'selectionReceiptId',v_receipt.id,
    'selectedProvider',v_receipt.selected_provider,
    'capabilityKey',w_receipt.capability_key,
    'capabilityVersion',v_receipt.capability_version,
    'operationMode',v_spec.operation_mode,
    'evidenceRequired',v_spec.evidence_required,
   'requiresApproval',v_requires_approval,
    'consent',v_consent,
    'authorizationBoundary','pandora_tool_gateway',
   'approvalBinding','exact_action_hash',
   'approvalAuthority','public.approvals'
  );
end;
$$;

revoke all on function public.pandora_capability_consent_preflight_v1(uuid,text,text,uuid,text)
  from public,anon;
revoke all on function public.pandora_capability_execution_preflight_v1(uuid,uuid,uuid,text)
  from public,anon;

grant execute on function public.pandora_capability_consent_preflight_v1(uuid,text,text,uuid,text)
  to authenticated,service_role;
grant execute on function public.pandora_capability_execution_preflight_v1(uuid,uuid,uuid,text)
  to authenticated,service_role;

comment on function public.pandora_capability_consent_preflight_v1(uuid,text,text,uuid,text)
is 'Fail-closed consent eligibility for Universal Enterprise capability execution. Active exact organization/capability/version/purpose/subject grants only; revoked and expired grants are rejected.';

comment on function public.pandora_capability_execution_preflight_v1(uuid,uuid,uuid,text)
is 'Universal capability execution preflight. Consent is checked here; exact-action authorization remains owned by Pandora Tool Gateway/public.approvals and must bind the execution action_hash before provider mutation.';
