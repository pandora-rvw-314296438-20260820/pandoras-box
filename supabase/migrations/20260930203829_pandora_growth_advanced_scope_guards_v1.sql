
begin;

create or replace function private.pandora_growth_creative_scope_guard_v1()
returns trigger
language plpgsql
set search_path='pg_catalog','public','private'
as $function$
begin
  if not exists(
    select 1
    from public.pandora_growth_brand_contexts b
    where b.id=new.brand_context_id
      and b.organization_id=new.organization_id
      and b.project_id=new.project_id
      and b.status='approved'
  ) then
    raise exception 'PANDORA_GROWTH_BRAND_SCOPE_DENIED' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_pandora_growth_creative_scope_guard_v1 on public.pandora_growth_creative_candidates;
create trigger trg_pandora_growth_creative_scope_guard_v1
before insert or update on public.pandora_growth_creative_candidates
for each row execute function private.pandora_growth_creative_scope_guard_v1();

create or replace function private.pandora_growth_variant_scope_guard_v1()
returns trigger
language plpgsql
set search_path='pg_catalog','public','private'
as $function$
begin
  if not exists(
    select 1
    from public.pandora_growth_creative_candidates c
    where c.id=new.creative_candidate_id
      and c.organization_id=new.organization_id
      and c.project_id=new.project_id
  ) then
    raise exception 'PANDORA_GROWTH_VARIANT_CREATIVE_SCOPE_DENIED' using errcode='42501';
  end if;
  if new.tracking_campaign_id is not null and not exists(
    select 1
    from public.pandora_tracking_campaigns c
    join public.pandora_tracking_tenants t on t.id=c.tenant_id
    where c.id=new.tracking_campaign_id
      and t.organization_id=new.organization_id
      and t.project_id=new.project_id
  ) then
    raise exception 'PANDORA_GROWTH_VARIANT_CAMPAIGN_SCOPE_DENIED' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_pandora_growth_variant_scope_guard_v1 on public.pandora_growth_funnel_variants;
create trigger trg_pandora_growth_variant_scope_guard_v1
before insert or update on public.pandora_growth_funnel_variants
for each row execute function private.pandora_growth_variant_scope_guard_v1();

create or replace function private.pandora_growth_variant_observation_scope_guard_v1()
returns trigger
language plpgsql
set search_path='pg_catalog','public','private'
as $function$
begin
  if not exists(
    select 1
    from public.pandora_growth_funnel_variants v
    where v.id=new.variant_id
      and v.organization_id=new.organization_id
      and v.project_id=new.project_id
  ) then
    raise exception 'PANDORA_GROWTH_VARIANT_OBSERVATION_SCOPE_DENIED' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_pandora_growth_variant_observation_scope_guard_v1 on private.pandora_growth_variant_observations;
create trigger trg_pandora_growth_variant_observation_scope_guard_v1
before insert or update on private.pandora_growth_variant_observations
for each row execute function private.pandora_growth_variant_observation_scope_guard_v1();

create or replace function private.pandora_growth_client_context_scope_guard_v1()
returns trigger
language plpgsql
set search_path='pg_catalog','public','private'
as $function$
begin
  if not exists(
    select 1 from public.pandora_tracking_tenants t
    where t.id=new.tracking_tenant_id
      and t.organization_id=new.organization_id
      and t.project_id=new.project_id
      and t.status='active'
  ) then
    raise exception 'PANDORA_GROWTH_CLIENT_TENANT_SCOPE_DENIED' using errcode='42501';
  end if;
  if not exists(
    select 1 from public.pandora_growth_client_provisioning_templates p
    where p.id=new.template_id
      and p.status='approved'
      and p.cross_tenant_allowed is false
  ) then
    raise exception 'PANDORA_GROWTH_CLIENT_TEMPLATE_DENIED' using errcode='42501';
  end if;
  return new;
end;
$function$;

drop trigger if exists trg_pandora_growth_client_context_scope_guard_v1 on public.pandora_growth_client_contexts;
create trigger trg_pandora_growth_client_context_scope_guard_v1
before insert or update on public.pandora_growth_client_contexts
for each row execute function private.pandora_growth_client_context_scope_guard_v1();

commit;
;
