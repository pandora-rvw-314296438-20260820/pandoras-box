-- Pandora universal consent enforcement v1.
-- Consent-bound provider routing is explicit, evidence-backed, and fail-closed.
-- The legacy selector remains defined for source compatibility but is no longer executable by service_role.

alter table public.pandora_provider_selection_policies
  add column if not exists consent_required boolean not null default false,
  add column if not exists consent_purpose text,
  add column if not exists consent_subject_required boolean not null default false;

do $constraints$
begin
  if not exists (
    select 1 from pg_constraint
    where conrelid='public.pandora_provider_selection_policies'::regclass
      and conname='pandora_provider_selection_policy_consent_purpose_check'
  ) then
    alter table public.pandora_provider_selection_policies
      add constraint pandora_provider_selection_policy_consent_purpose_check
      check (
        (not consent_required)
        or (
          nullif(btrim(consent_purpose),'') is not null
          and char_length(btrim(consent_purpose)) between 1 and 500
        )
      );
  end if;

  if not exists (
    select 1 from pg_constraint
    where conrelid='public.pandora_provider_selection_policies'::regclass
      and conname='pandora_provider_selection_policy_consent_subject_check'
  ) then
    alter table public.pandora_provider_selection_policies
      add constraint pandora_provider_selection_policy_consent_subject_check
      check (not consent_subject_required or consent_required);
  end if;
end;
$constraints$;

create or replace function private.pandora_select_provider_core_v1(
  p_organization_id uuid,
  p_capability_key text,
  p_capability_version text default '1.0.0',
  p_region text default null,
  p_mode text default null
)
returns jsonb
language plpgsql
security invoker
set search_path='pg_catalog','public'
as $$
declare
  v_policy public.pandora_provider_selection_policies%rowtype;
  v_mode text;
  v_required text;
  v_preferred text[]:='{}'::text[];
  v_fallback text[]:='{}'::text[];
  v_allow_required_fallback boolean:=false;
  v_required_residency text[]:='{}'::text[];
  v_max_cost numeric;
  v_weights jsonb:='{"reliability":0.5,"latency":0.25,"cost":0.25}'::jsonb;
  v_approval_required boolean:=false;
  v_eligible jsonb:='[]'::jsonb;
  v_excluded jsonb:='[]'::jsonb;
  v_scores jsonb:='[]'::jsonb;
  v_selected text;
  v_reason text;
  v_receipt_id uuid;
begin
  if not exists(
    select 1 from public.pandora_capability_specs
    where capability_key=p_capability_key
      and capability_version=p_capability_version
      and lifecycle_state='active'
  ) then
    raise exception 'capability_not_active' using errcode='22023';
  end if;

  select * into v_policy
  from public.pandora_provider_selection_policies
  where organization_id=p_organization_id
    and capability_key=p_capability_key
    and capability_version=p_capability_version;

  if found then
    v_mode:=coalesce(p_mode,v_policy.selection_mode);
    v_required:=v_policy.required_provider;
    v_preferred:=v_policy.preferred_providers;
    v_fallback:=v_policy.fallback_providers;
    v_allow_required_fallback:=v_policy.allow_required_fallback;
    v_required_residency:=v_policy.required_data_residency;
    v_max_cost:=v_policy.max_cost_per_unit;
    v_weights:=v_policy.score_weights;
    v_approval_required:=v_policy.approval_required;
  else
    v_mode:=coalesce(p_mode,'AUTO');
  end if;

  if v_mode not in ('AUTO','PREFERRED','REQUIRED') then
    raise exception 'invalid_provider_selection_mode' using errcode='22023';
  end if;

  with universe as (
    select
      pc.provider_key,
      pc.manifest_version,
      pc.implementation_state,
      pm.lifecycle_state,
      pm.data_residency,
      pc.regions,
      pa.activation_state,
      pa.health_state,
      pa.granted_capabilities,
      m.verified_success_count,
      m.verified_failure_count,
      m.p95_latency_ms,
      m.cost_per_unit
    from public.pandora_provider_capabilities pc
    join public.pandora_provider_manifests pm
      on pm.provider_key=pc.provider_key and pm.manifest_version=pc.manifest_version
    left join public.pandora_provider_activations pa
      on pa.organization_id=p_organization_id
     and pa.provider_key=pc.provider_key
     and pa.manifest_version=pc.manifest_version
    left join lateral (
      select mm.*
      from public.pandora_provider_capability_metrics mm
      where mm.organization_id=p_organization_id
        and mm.provider_key=pc.provider_key
        and mm.capability_key=pc.capability_key
        and mm.capability_version=pc.capability_version
        and (p_region is null or mm.region=p_region or mm.region='global')
      order by mm.window_end desc
      limit 1
    ) m on true
    where pc.capability_key=p_capability_key
      and pc.capability_version=p_capability_version
  ), scored0 as (
    select *,
      coalesce(verified_success_count::numeric/nullif(verified_success_count+verified_failure_count,0),0.5) reliability_score,
      1/(1+(coalesce(p95_latency_ms,1000)/1000)) latency_score,
      1/(1+coalesce(cost_per_unit,1)) cost_score,
      (
        lifecycle_state='active'
        and implementation_state='native'
        and activation_state='authorized'
        and coalesce(health_state,'unknown')<>'down'
        and (p_capability_key=any(coalesce(granted_capabilities,'{}'::text[])) or '*'=any(coalesce(granted_capabilities,'{}'::text[])))
        and (p_region is null or p_region=any(regions) or 'global'=any(regions))
        and (cardinality(v_required_residency)=0 or data_residency && v_required_residency)
        and (v_max_cost is null or (cost_per_unit is not null and cost_per_unit<=v_max_cost))
      ) eligible
    from universe
  ), scored as (
    select *,
      (
        coalesce((v_weights->>'reliability')::numeric,0.5)*reliability_score +
        coalesce((v_weights->>'latency')::numeric,0.25)*latency_score +
        coalesce((v_weights->>'cost')::numeric,0.25)*cost_score
      ) total_score,
      array_remove(array[
        case when lifecycle_state<>'active' then 'manifest_not_active' end,
        case when implementation_state<>'native' then 'adapter_not_native' end,
        case when activation_state is distinct from 'authorized' then 'provider_not_authorized' end,
        case when coalesce(health_state,'unknown')='down' then 'provider_down' end,
        case when not (p_capability_key=any(coalesce(granted_capabilities,'{}'::text[])) or '*'=any(coalesce(granted_capabilities,'{}'::text[]))) then 'capability_not_granted' end,
        case when p_region is not null and not (p_region=any(regions) or 'global'=any(regions)) then 'region_ineligible' end,
        case when cardinality(v_required_residency)>0 and not (data_residency && v_required_residency) then 'data_residency_ineligible' end,
        case when v_max_cost is not null and (cost_per_unit is null or cost_per_unit>v_max_cost) then 'cost_constraint_ineligible' end
      ],null) exclusion_reasons
    from scored0
  )
  select
    coalesce(jsonb_agg(jsonb_build_object(
      'providerKey',provider_key,
      'manifestVersion',manifest_version,
      'score',total_score
    ) order by provider_key) filter(where eligible),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'providerKey',provider_key,
      'reasons',to_jsonb(exclusion_reasons)
    ) order by provider_key) filter(where not eligible),'[]'::jsonb),
    coalesce(jsonb_agg(jsonb_build_object(
      'providerKey',provider_key,
      'score',total_score,
      'reliability',reliability_score,
      'latency',latency_score,
      'cost',cost_score
    ) order by provider_key) filter(where eligible),'[]'::jsonb)
  into v_eligible,v_excluded,v_scores
  from scored;

  if v_mode='REQUIRED' then
    if v_required is null then
      v_reason:='required_provider_not_configured';
    elsif exists(select 1 from jsonb_array_elements(v_eligible) e where e->>'providerKey'=v_required) then
      v_selected:=v_required;
      v_reason:='required_provider_selected';
    elsif v_allow_required_fallback then
      select f.provider_key into v_selected
      from unnest(v_fallback) with ordinality f(provider_key,ord)
      where exists(select 1 from jsonb_array_elements(v_eligible) e where e->>'providerKey'=f.provider_key)
      order by f.ord
      limit 1;
      v_reason:=case when v_selected is null then 'required_provider_unavailable_no_eligible_fallback' else 'required_provider_unavailable_explicit_fallback' end;
    else
      v_reason:='required_provider_unavailable_fail_closed';
    end if;
  elsif v_mode='PREFERRED' then
    select p.provider_key into v_selected
    from unnest(v_preferred) with ordinality p(provider_key,ord)
    where exists(select 1 from jsonb_array_elements(v_eligible) e where e->>'providerKey'=p.provider_key)
    order by p.ord
    limit 1;

    if v_selected is not null then
      v_reason:='preferred_provider_selected';
    else
      select f.provider_key into v_selected
      from unnest(v_fallback) with ordinality f(provider_key,ord)
      where exists(select 1 from jsonb_array_elements(v_eligible) e where e->>'providerKey'=f.provider_key)
      order by f.ord
      limit 1;
      v_reason:=case when v_selected is null then 'preferred_provider_unavailable_no_approved_fallback' else 'preferred_provider_unavailable_explicit_fallback' end;
    end if;
  else
    select e->>'providerKey' into v_selected
    from jsonb_array_elements(v_scores) e
    order by (e->>'score')::numeric desc,e->>'providerKey'
    limit 1;
    v_reason:=case when v_selected is null then 'no_eligible_provider' else 'auto_highest_explainable_score' end;
  end if;

  insert into public.pandora_provider_selection_receipts(
    organization_id,capability_key,capability_version,requested_mode,requested_region,
    selected_provider,result_state,eligible_providers,excluded_providers,score_components,
    selection_reason,approval_required
  ) values (
    p_organization_id,p_capability_key,p_capability_version,v_mode,p_region,
    v_selected,case when v_selected is null then 'no_eligible_provider' else 'selected' end,
    v_eligible,v_excluded,v_scores,v_reason,v_approval_required
  ) returning id into v_receipt_id;

  return jsonb_build_object(
    'ok',v_selected is not null,
    'selectionReceiptId',v_receipt_id,
    'mode',v_mode,
    'selectedProvider',v_selected,
    'approvalRequired',v_approval_required,
    'reason',v_reason,
    'eligibleProviders',v_eligible,
    'excludedProviders',v_excluded,
    'scores',v_scores
  );
end;
$$;

create or replace function public.pandora_select_provider_v1(
  p_organization_id uuid,
  p_capability_key text,
  p_capability_version text default '1.0.0',
  p_region text default null,
  p_mode text default null
)
returns jsonb
language plpgsql
security invoker
set search_path='pg_catalog','public','private'
as $legacy$
declare
  v_policy public.pandora_provider_selection_policies%rowtype;
begin
  select * into v_policy
  from public.pandora_provider_selection_policies
  where organization_id=p_organization_id
    and capability_key=p_capability_key
    and capability_version=p_capability_version;

  if found and v_policy.consent_required then
    raise exception 'consent_context_required' using errcode='42501';
  end if;

  return private.pandora_select_provider_core_v1(
    p_organization_id,
    p_capability_key,
    p_capability_version,
    p_region,
    p_mode
  );
end;
$legacy$;

create or replace function private.pandora_select_provider_authorized_v1(
  p_organization_id uuid,
  p_capability_key text,
  p_capability_version text default '1.0.0',
  p_region text default null,
  p_mode text default null,
  p_consent_grant_id uuid default null,
  p_consent_purpose text default null,
  p_subject_entity_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path='pg_catalog','public','private'
as $authorized$
declare
  v_policy public.pandora_provider_selection_policies%rowtype;
  v_grant public.pandora_consent_grants%rowtype;
  v_now timestamptz:=clock_timestamp();
  v_purpose text:=nullif(btrim(coalesce(p_consent_purpose,'')),'');
begin
  select * into v_policy
  from public.pandora_provider_selection_policies
  where organization_id=p_organization_id
    and capability_key=p_capability_key
    and capability_version=p_capability_version;

  if found and v_policy.consent_required then
    if p_consent_grant_id is null then
      raise exception 'consent_grant_required' using errcode='42501';
    end if;
    if v_purpose is null then
      raise exception 'consent_purpose_required' using errcode='42501';
    end if;
    if v_purpose is distinct from btrim(v_policy.consent_purpose) then
      raise exception 'consent_purpose_mismatch' using errcode='42501';
    end if;
    if v_policy.consent_subject_required and p_subject_entity_id is null then
      raise exception 'consent_subject_required' using errcode='42501';
    end if;

    select * into v_grant
    from public.pandora_consent_grants
    where id=p_consent_grant_id
      and organization_id=p_organization_id
      and capability_key=p_capability_key
      and capability_version=p_capability_version;

    if not found then
      raise exception 'consent_grant_not_found' using errcode='42501';
    end if;
    if btrim(v_grant.purpose) is distinct from v_purpose then
      raise exception 'consent_purpose_mismatch' using errcode='42501';
    end if;
    if v_grant.granted_at>v_now then
      raise exception 'consent_not_active' using errcode='42501';
    end if;
    if v_grant.revoked_at is not null then
      raise exception 'consent_revoked' using errcode='42501';
    end if;
    if v_grant.expires_at is not null and v_grant.expires_at<v_now then
      raise exception 'consent_expired' using errcode='42501';
    end if;
    if jsonb_typeof(v_grant.evidence_refs)<>'array'
       or jsonb_array_length(v_grant.evidence_refs)=0 then
      raise exception 'consent_evidence_required' using errcode='42501';
    end if;

    if v_policy.consent_subject_required then
      if v_grant.subject_entity_id is distinct from p_subject_entity_id then
        raise exception 'consent_subject_mismatch' using errcode='42501';
      end if;
    elsif v_grant.subject_entity_id is not null
       and v_grant.subject_entity_id is distinct from p_subject_entity_id then
      raise exception 'consent_subject_mismatch' using errcode='42501';
    end if;
  end if;

  return private.pandora_select_provider_core_v1(
    p_organization_id,
    p_capability_key,
    p_capability_version,
    p_region,
    p_mode
  );
end;
$authorized$;

create or replace function public.pandora_select_provider_authorized_v1(
  p_organization_id uuid,
  p_capability_key text,
  p_capability_version text default '1.0.0',
  p_region text default null,
  p_mode text default null,
  p_consent_grant_id uuid default null,
  p_consent_purpose text default null,
  p_subject_entity_id uuid default null
)
returns jsonb
language sql
security invoker
set search_path='pg_catalog','public','private'
as $public_authorized$
  select private.pandora_select_provider_authorized_v1(
    p_organization_id,
    p_capability_key,
    p_capability_version,
    p_region,
    p_mode,
    p_consent_grant_id,
    p_consent_purpose,
    p_subject_entity_id
  );
$public_authorized$;

revoke all on function private.pandora_select_provider_core_v1(uuid,text,text,text,text)
  from public,anon,authenticated,service_role;
revoke all on function private.pandora_select_provider_authorized_v1(uuid,text,text,text,text,uuid,text,uuid)
  from public,anon,authenticated;
grant execute on function private.pandora_select_provider_authorized_v1(uuid,text,text,text,text,uuid,text,uuid)
  to service_role;

revoke all on function public.pandora_select_provider_v1(uuid,text,text,text,text)
  from public,anon,authenticated,service_role;
revoke all on function public.pandora_select_provider_authorized_v1(uuid,text,text,text,text,uuid,text,uuid)
  from public,anon,authenticated;
grant execute on function public.pandora_select_provider_authorized_v1(uuid,text,text,text,text,uuid,text,uuid)
  to service_role;

comment on function public.pandora_select_provider_authorized_v1(uuid,text,text,text,text,uuid,text,uuid)
is 'Service-role provider selection entry point. Consent-bound policies require an exact active evidence-backed consent grant with matching purpose and subject context; non-consent policies preserve existing routing behavior.';

comment on function public.pandora_select_provider_v1(uuid,text,text,text,text)
is 'Legacy internal provider selector retained for source compatibility. Direct service-role execution is revoked by consent enforcement v1; use pandora_select_provider_authorized_v1.';
