-- Worker B/J: durable ProjectSpec compiler claim + atomic commit boundary.
-- Model execution remains server-side. No provider credential is stored here.

create unique index if not exists pandora_project_specs_source_intent_uidx
  on public.pandora_project_specs(source_intent_id);

create table if not exists public.pandora_project_spec_compilations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  project_id uuid not null references public.projectos_projects(id) on delete cascade,
  source_intent_id uuid not null references public.pandora_project_intents(id) on delete restrict,
  status text not null default 'running',
  attempt_count integer not null default 1,
  claim_token uuid not null default gen_random_uuid(),
  project_spec_id uuid null references public.pandora_project_specs(id) on delete set null,
  safe_error_code text null,
  started_at timestamptz not null default now(),
  finished_at timestamptz null,
  retry_after_at timestamptz null,
  updated_at timestamptz not null default now(),
  constraint pandora_project_spec_compilations_status_check
    check (status in ('running','succeeded','failed')),
  constraint pandora_project_spec_compilations_attempt_check
    check (attempt_count between 1 and 20),
  constraint pandora_project_spec_compilations_error_check
    check (safe_error_code is null or safe_error_code ~ '^[A-Z0-9_]{3,80}$'),
  unique (source_intent_id)
);
alter table public.pandora_project_spec_compilations enable row level security;
revoke all on public.pandora_project_spec_compilations from public, anon, authenticated;
grant select, insert, update on public.pandora_project_spec_compilations to service_role;

create or replace function private.pandora_claim_project_spec_compilation_20260829(
  p_source_intent_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','private','public'
as $$
declare
  v_org uuid;
  v_project uuid;
  v_existing public.pandora_project_spec_compilations%rowtype;
  v_spec_id uuid;
  v_token uuid;
begin
  select organization_id, project_id into v_org, v_project
  from public.pandora_project_intents
  where id = p_source_intent_id;
  if v_project is null then
    raise exception 'source intent not found' using errcode='22023';
  end if;

  select id into v_spec_id
  from public.pandora_project_specs
  where source_intent_id = p_source_intent_id;
  if v_spec_id is not null then
    insert into public.pandora_project_spec_compilations(
      organization_id, project_id, source_intent_id, status, project_spec_id,
      finished_at, updated_at
    ) values (
      v_org, v_project, p_source_intent_id, 'succeeded', v_spec_id, now(), now()
    ) on conflict (source_intent_id) do update set
      status='succeeded', project_spec_id=excluded.project_spec_id,
      finished_at=coalesce(public.pandora_project_spec_compilations.finished_at, now()),
      safe_error_code=null, retry_after_at=null, updated_at=now();
    return jsonb_build_object('state','succeeded','projectSpecId',v_spec_id);
  end if;

  select * into v_existing
  from public.pandora_project_spec_compilations
  where source_intent_id = p_source_intent_id
  for update;

  if found then
    if v_existing.status = 'succeeded' then
      return jsonb_build_object('state','succeeded','projectSpecId',v_existing.project_spec_id);
    end if;
    if v_existing.status = 'running' and v_existing.started_at > now() - interval '2 minutes' then
      return jsonb_build_object('state','running');
    end if;
    if v_existing.status = 'failed' and v_existing.retry_after_at is not null and v_existing.retry_after_at > now() then
      return jsonb_build_object('state','waiting','retryAfter',v_existing.retry_after_at);
    end if;
    if v_existing.attempt_count >= 20 then
      return jsonb_build_object('state','failed','errorCode','COMPILATION_RETRY_LIMIT');
    end if;

    v_token := gen_random_uuid();
    update public.pandora_project_spec_compilations
    set status='running', attempt_count=attempt_count+1, claim_token=v_token,
        safe_error_code=null, started_at=now(), finished_at=null,
        retry_after_at=null, updated_at=now()
    where id=v_existing.id;
    return jsonb_build_object('state','claimed','claimToken',v_token);
  end if;

  v_token := gen_random_uuid();
  insert into public.pandora_project_spec_compilations(
    organization_id, project_id, source_intent_id, status, claim_token
  ) values (v_org, v_project, p_source_intent_id, 'running', v_token);
  return jsonb_build_object('state','claimed','claimToken',v_token);
end;
$$;
revoke all on function private.pandora_claim_project_spec_compilation_20260829(uuid) from public, anon, authenticated;
grant execute on function private.pandora_claim_project_spec_compilation_20260829(uuid) to service_role;

create or replace function public.pandora_claim_project_spec_compilation_20260829(
  p_source_intent_id uuid
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.pandora_claim_project_spec_compilation_20260829(p_source_intent_id);
$$;
revoke all on function public.pandora_claim_project_spec_compilation_20260829(uuid) from public, anon, authenticated;
grant execute on function public.pandora_claim_project_spec_compilation_20260829(uuid) to service_role;

create or replace function private.pandora_commit_compiled_project_spec_20260829(
  p_source_intent_id uuid,
  p_claim_token uuid,
  p_candidate jsonb,
  p_compiler_provider text,
  p_compiler_model text,
  p_compiler_version text,
  p_compiler_provenance jsonb,
  p_content_sha256 text
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','private','public'
as $$
declare
  v_org uuid;
  v_project uuid;
  v_requester uuid;
  v_existing uuid;
  v_previous uuid;
  v_version integer;
  v_spec_id uuid;
  v_project_type text;
  v_business jsonb;
  v_product jsonb;
  v_data jsonb;
  v_integrations jsonb;
  v_design jsonb;
  v_deployment jsonb;
  v_acceptance jsonb;
  v_target_users text;
  v_objective text;
  v_expected text;
  v_metric text;
  v_baseline text;
  v_target text;
  v_item text;
  v_ord bigint;
  v_serialized text;
begin
  if p_candidate is null or jsonb_typeof(p_candidate) <> 'object' then
    raise exception 'ProjectSpec candidate must be an object' using errcode='22023';
  end if;
  if p_content_sha256 !~ '^[0-9a-f]{64}$' then
    raise exception 'invalid ProjectSpec content digest' using errcode='22023';
  end if;
  if p_compiler_provider !~ '^[a-z][a-z0-9_-]{1,31}$'
     or p_compiler_model !~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,99}$'
     or length(coalesce(p_compiler_version,'')) not between 1 and 40 then
    raise exception 'invalid compiler identity' using errcode='22023';
  end if;
  if p_compiler_provenance is null or jsonb_typeof(p_compiler_provenance) <> 'object'
     or octet_length(p_compiler_provenance::text) > 8192 then
    raise exception 'invalid compiler provenance' using errcode='22023';
  end if;

  if exists (
    select 1 from jsonb_object_keys(p_candidate) k
    where k not in ('version','business','product','data','integrations','design','deployment','acceptance','metadata')
  ) then
    raise exception 'unknown ProjectSpec top-level field' using errcode='22023';
  end if;
  if p_candidate->>'version' <> '1.0' then
    raise exception 'unsupported ProjectSpec candidate version' using errcode='22023';
  end if;

  v_business := coalesce(p_candidate->'business','{}'::jsonb);
  v_product := coalesce(p_candidate->'product','{}'::jsonb);
  v_data := coalesce(p_candidate->'data','{}'::jsonb);
  v_integrations := coalesce(p_candidate->'integrations','{}'::jsonb);
  v_design := coalesce(p_candidate->'design','{}'::jsonb);
  v_deployment := coalesce(p_candidate->'deployment','{}'::jsonb);
  v_acceptance := coalesce(p_candidate->'acceptance','{}'::jsonb);
  if jsonb_typeof(v_business) <> 'object' or jsonb_typeof(v_product) <> 'object'
     or jsonb_typeof(v_data) <> 'object' or jsonb_typeof(v_integrations) <> 'object'
     or jsonb_typeof(v_design) <> 'object' or jsonb_typeof(v_deployment) <> 'object'
     or jsonb_typeof(v_acceptance) <> 'object' then
    raise exception 'ProjectSpec sections must be objects' using errcode='22023';
  end if;

  v_objective := trim(coalesce(v_business->>'objective',''));
  v_project_type := trim(coalesce(v_product->>'projectType',''));
  if length(v_objective) not between 1 and 5000 then
    raise exception 'business objective is required' using errcode='22023';
  end if;
  if v_project_type not in ('website','web_application','mobile_application','system','api','automation','other') then
    raise exception 'invalid project type' using errcode='22023';
  end if;
  if jsonb_typeof(v_acceptance->'functional') <> 'array'
     or jsonb_array_length(v_acceptance->'functional') < 1
     or jsonb_array_length(v_acceptance->'functional') > 50 then
    raise exception 'functional acceptance criteria are required' using errcode='22023';
  end if;

  v_serialized := p_candidate::text;
  if octet_length(v_serialized) > 262144
     or v_serialized ~* '"(gemini_api_key|github_supabase|github_pat|service_role_key|supabase_service_role|vercel_token|authorization|cookie|private_key|database_password)"[[:space:]]*:'
     or v_serialized ~ 'AIza[0-9A-Za-z_-]{20,}'
     or v_serialized ~ 'gh[pousr]_[A-Za-z0-9_]{20,}'
     or v_serialized ~ 'github_pat_[A-Za-z0-9_]{20,}'
     or v_serialized ~ '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----' then
    raise exception 'credential material rejected from ProjectSpec' using errcode='22023';
  end if;

  select organization_id, project_id, requester_id
    into v_org, v_project, v_requester
  from public.pandora_project_intents
  where id=p_source_intent_id;
  if v_project is null then
    raise exception 'source intent not found' using errcode='22023';
  end if;

  perform 1 from public.projectos_projects where id=v_project and organization_id=v_org for update;

  select id into v_existing from public.pandora_project_specs
  where source_intent_id=p_source_intent_id;
  if v_existing is not null then
    update public.pandora_project_spec_compilations
    set status='succeeded', project_spec_id=v_existing, finished_at=coalesce(finished_at,now()),
        safe_error_code=null, retry_after_at=null, updated_at=now()
    where source_intent_id=p_source_intent_id;
    return jsonb_build_object('state','succeeded','projectSpecId',v_existing);
  end if;

  if not exists (
    select 1 from public.pandora_project_spec_compilations
    where source_intent_id=p_source_intent_id and status='running' and claim_token=p_claim_token
  ) then
    raise exception 'ProjectSpec compilation claim mismatch' using errcode='55000';
  end if;

  select id, version into v_previous, v_version
  from public.pandora_project_specs
  where project_id=v_project and status='active'
  order by version desc limit 1 for update;
  if v_previous is null then
    select coalesce(max(version),0)+1 into v_version
    from public.pandora_project_specs where project_id=v_project;
  else
    v_version := v_version + 1;
    update public.pandora_project_specs
    set status='superseded', superseded_at=now()
    where id=v_previous;
  end if;

  select left(string_agg(trim(value), '; ' order by ordinality),2000)
  into v_target_users
  from jsonb_array_elements_text(case when jsonb_typeof(v_product->'users')='array' then v_product->'users' else '[]'::jsonb end)
       with ordinality as u(value,ordinality)
  where trim(value)<>'' and ordinality<=8;

  insert into public.pandora_project_specs(
    organization_id,project_id,version,status,source_intent_id,previous_spec_id,
    schema_version,project_type,target_user_summary,business_summary,
    product_scope,data_scope,integration_scope,experience_scope,deployment_scope,acceptance_scope,
    compiler_provider,compiler_model,compiler_version,compiler_provenance,content_sha256,created_by
  ) values (
    v_org,v_project,v_version,'active',p_source_intent_id,v_previous,
    '1.0.0',v_project_type,nullif(v_target_users,''),left(v_objective,5000),
    v_product,v_data,v_integrations,v_design,v_deployment,v_acceptance,
    p_compiler_provider,p_compiler_model,p_compiler_version,p_compiler_provenance,p_content_sha256,v_requester
  ) returning id into v_spec_id;

  v_expected := nullif(trim(coalesce(v_business->>'expectedOutcome','')),'');
  v_metric := nullif(trim(coalesce(v_business->>'successMetric','')),'');
  v_baseline := nullif(trim(coalesce(v_business->>'baseline','')),'');
  v_target := nullif(trim(coalesce(v_business->>'target','')),'');
  insert into public.pandora_project_business_objectives(
    organization_id,project_id,project_spec_id,ordinal,objective,desired_outcome,success_metric,baseline,target,provenance,created_by
  ) values (
    v_org,v_project,v_spec_id,1,v_objective,v_expected,v_metric,v_baseline,v_target,
    jsonb_build_object('source_intent_id',p_source_intent_id,'compiler_version',p_compiler_version),v_requester
  );

  for v_item,v_ord in
    select trim(value), ordinality from jsonb_array_elements_text(case when jsonb_typeof(v_product->'features')='array' then v_product->'features' else '[]'::jsonb end) with ordinality t(value,ordinality)
    where trim(value)<>'' and ordinality<=30
  loop
    insert into public.pandora_project_requirements(organization_id,project_id,project_spec_id,source_intent_id,requirement_key,category,priority,statement,provenance,created_by)
    values(v_org,v_project,v_spec_id,p_source_intent_id,'product.feature.'||v_ord,'product','must',left(v_item,10000),jsonb_build_object('compiler_version',p_compiler_version),v_requester);
  end loop;
  for v_item,v_ord in
    select trim(value), ordinality from jsonb_array_elements_text(case when jsonb_typeof(v_product->'workflows')='array' then v_product->'workflows' else '[]'::jsonb end) with ordinality t(value,ordinality)
    where trim(value)<>'' and ordinality<=20
  loop
    insert into public.pandora_project_requirements(organization_id,project_id,project_spec_id,source_intent_id,requirement_key,category,priority,statement,provenance,created_by)
    values(v_org,v_project,v_spec_id,p_source_intent_id,'product.workflow.'||v_ord,'product','must',left(v_item,10000),jsonb_build_object('compiler_version',p_compiler_version),v_requester);
  end loop;
  for v_item,v_ord in
    select trim(value), ordinality from jsonb_array_elements_text(case when jsonb_typeof(v_design->'accessibility')='array' then v_design->'accessibility' else '[]'::jsonb end) with ordinality t(value,ordinality)
    where trim(value)<>'' and ordinality<=20
  loop
    insert into public.pandora_project_requirements(organization_id,project_id,project_spec_id,source_intent_id,requirement_key,category,priority,statement,provenance,created_by)
    values(v_org,v_project,v_spec_id,p_source_intent_id,'experience.accessibility.'||v_ord,'experience','must',left(v_item,10000),jsonb_build_object('compiler_version',p_compiler_version),v_requester);
  end loop;
  for v_item,v_ord in
    select trim(value), ordinality from jsonb_array_elements_text(case when jsonb_typeof(v_business->'constraints')='array' then v_business->'constraints' else '[]'::jsonb end) with ordinality t(value,ordinality)
    where trim(value)<>'' and ordinality<=20
  loop
    insert into public.pandora_project_constraints(organization_id,project_id,project_spec_id,source_intent_id,constraint_key,constraint_type,severity,statement,provenance,created_by)
    values(v_org,v_project,v_spec_id,p_source_intent_id,'business.constraint.'||v_ord,'business','required',left(v_item,10000),jsonb_build_object('compiler_version',p_compiler_version),v_requester);
  end loop;
  for v_item,v_ord in
    select trim(value), ordinality from jsonb_array_elements_text(v_acceptance->'functional') with ordinality t(value,ordinality)
    where trim(value)<>'' and ordinality<=50
  loop
    insert into public.pandora_project_acceptance_criteria(organization_id,project_id,project_spec_id,criterion_key,criterion,test_kind,required,provenance,created_by)
    values(v_org,v_project,v_spec_id,'functional.'||v_ord,left(v_item,10000),'acceptance',true,jsonb_build_object('compiler_version',p_compiler_version),v_requester);
  end loop;

  update public.pandora_project_spec_compilations
  set status='succeeded', project_spec_id=v_spec_id, safe_error_code=null,
      finished_at=now(), retry_after_at=null, updated_at=now()
  where source_intent_id=p_source_intent_id and claim_token=p_claim_token and status='running';

  return jsonb_build_object('state','succeeded','projectSpecId',v_spec_id,'version',v_version,'sourceIntentId',p_source_intent_id);
end;
$$;
revoke all on function private.pandora_commit_compiled_project_spec_20260829(uuid,uuid,jsonb,text,text,text,jsonb,text) from public, anon, authenticated;
grant execute on function private.pandora_commit_compiled_project_spec_20260829(uuid,uuid,jsonb,text,text,text,jsonb,text) to service_role;

create or replace function public.pandora_commit_compiled_project_spec_20260829(
  p_source_intent_id uuid,
  p_claim_token uuid,
  p_candidate jsonb,
  p_compiler_provider text,
  p_compiler_model text,
  p_compiler_version text,
  p_compiler_provenance jsonb,
  p_content_sha256 text
)
returns jsonb
language sql
security definer
set search_path = ''
as $$
  select private.pandora_commit_compiled_project_spec_20260829(
    p_source_intent_id,p_claim_token,p_candidate,p_compiler_provider,p_compiler_model,
    p_compiler_version,p_compiler_provenance,p_content_sha256
  );
$$;
revoke all on function public.pandora_commit_compiled_project_spec_20260829(uuid,uuid,jsonb,text,text,text,jsonb,text) from public, anon, authenticated;
grant execute on function public.pandora_commit_compiled_project_spec_20260829(uuid,uuid,jsonb,text,text,text,jsonb,text) to service_role;

create or replace function public.pandora_fail_project_spec_compilation_20260829(
  p_source_intent_id uuid,
  p_claim_token uuid,
  p_safe_error_code text
)
returns jsonb
language plpgsql
security definer
set search_path = 'pg_catalog','public'
as $$
declare
  v_attempt integer;
begin
  if p_safe_error_code !~ '^[A-Z0-9_]{3,80}$' then
    raise exception 'invalid safe compilation error code' using errcode='22023';
  end if;
  update public.pandora_project_spec_compilations
  set status='failed', safe_error_code=p_safe_error_code, finished_at=now(),
      retry_after_at=now()+case when attempt_count>=5 then interval '5 minutes' else interval '30 seconds' end,
      updated_at=now()
  where source_intent_id=p_source_intent_id and claim_token=p_claim_token and status='running'
  returning attempt_count into v_attempt;
  if v_attempt is null then
    return jsonb_build_object('state','ignored');
  end if;
  return jsonb_build_object('state','failed','retryable',v_attempt<20);
end;
$$;
revoke all on function public.pandora_fail_project_spec_compilation_20260829(uuid,uuid,text) from public, anon, authenticated;
grant execute on function public.pandora_fail_project_spec_compilation_20260829(uuid,uuid,text) to service_role;
